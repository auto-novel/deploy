#!/usr/bin/env python3
"""从本地 latest 回退，按创建时间选择同仓库、同平台的旧 untag 镜像。"""

import argparse
import copy
import datetime as dt
from dataclasses import dataclass
import json
import os
import re
from pathlib import Path
import subprocess
import sys


class RollbackError(Exception):
    pass


def run(args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise RollbackError(result.stderr.strip() or result.stdout.strip() or str(args))
    return result.stdout


def inspect_images(references):
    images = []
    for start in range(0, len(references), 100):
        images.extend(
            json.loads(
                run(["docker", "image", "inspect", *references[start : start + 100]])
            )
        )
    return images


class ComposeProject:
    def __init__(self, path):
        self.path = path
        self.config = self._load_config()
        with self.path.open(newline="") as stream:
            self.original = stream.read()

    @staticmethod
    def _load_config():
        # Preserve Compose's current-directory and environment-based file discovery.
        return json.loads(run(["docker", "compose", "config", "--format", "json"]))

    def render_images(self, target_images):
        modified = self.original
        for name, image in target_images.items():
            old_image = self.config["services"][name]["image"]
            if modified.count(old_image) != 1:
                raise RollbackError(f"{name}: 文件中的镜像引用缺失或不唯一")
            modified = modified.replace(old_image, image, 1)
        return modified

    def apply_images(self, target_images, modified):
        with self.path.open(newline="") as stream:
            if stream.read() != self.original:
                raise RollbackError("Compose 文件已变更，取消写入")
        try:
            with self.path.open("w", newline="") as stream:
                stream.write(modified)
            # Ensure anchors, includes or interpolation did not alter other settings.
            expected = copy.deepcopy(self.config)
            for name, image in target_images.items():
                expected["services"][name]["image"] = image
            actual = self._load_config()
            if actual != expected:
                raise RollbackError("Compose 配置变更与预期不符")
        except (Exception, KeyboardInterrupt):
            with self.path.open("w", newline="") as stream:
                stream.write(self.original)
            raise

    def recreate(self, services):
        # Rebuild failures retain the target configuration rather than restoring it.
        result = subprocess.run(
            [
                "docker",
                "compose",
                "up",
                "-d",
                "--no-deps",
                "--pull",
                "never",
                *services,
            ]
        )
        if result.returncode:
            raise RollbackError("容器重建失败，目标配置已保留；请检查服务状态")


@dataclass(frozen=True)
class RollbackTarget:
    name: str
    steps: int
    latest: dict
    target: dict
    target_reference: str


def find_older_images(repository, latest, local_image_rows):
    def created_at(image):
        # Docker timestamps can contain nanoseconds; compare at microsecond precision.
        return dt.datetime.fromisoformat(image["Created"].replace("Z", "+00:00"))

    untagged_image_ids = {
        row["ID"]
        for row in local_image_rows
        if row["Repository"] == repository and row["Tag"] == "<none>"
    }
    latest_created_at = created_at(latest)
    candidates = []
    for image in inspect_images(sorted(untagged_image_ids)):
        if any(
            image.get(key) != latest.get(key)
            for key in ("Os", "Architecture", "Variant")
        ):
            continue
        if created_at(image) < latest_created_at:
            candidates.append(image)
    candidates.sort(key=lambda image: (created_at(image), image["Id"]), reverse=True)
    return candidates


def resolve_digest_reference(repository, image):
    references = sorted(
        value
        for value in image.get("RepoDigests", []) or []
        if value.startswith(repository + "@")
    )
    if not references:
        raise RollbackError(f"目标镜像缺少 {repository} 的 digest")
    return references[0]


def resolve_plan(config, targets):
    # Share one local listing across all target services.
    listing = run(
        ["docker", "image", "ls", "--all", "--no-trunc", "--format", "{{json .}}"]
    )
    local_image_rows = [
        json.loads(line) for line in listing.splitlines() if line.strip()
    ]

    # Resolve every target before displaying the plan or modifying the file.
    plan = []
    for name, steps in targets:
        service = config.get("services", {}).get(name)
        if service is None:
            raise RollbackError(f"服务不存在: {name!r}")
        current_reference = service.get("image", "")
        if not current_reference.startswith("ghcr.io/"):
            raise RollbackError(f"{name}: image 必须使用 ghcr.io/ 仓库引用")
        repository = current_reference.split("@", 1)[0].split(":", 1)[0]
        # Always use local latest, even when the file pins an older digest.
        latest = inspect_images([repository + ":latest"])[0]
        candidates = find_older_images(repository, latest, local_image_rows)
        if steps > len(candidates):
            raise RollbackError(
                f"{name}: 仅有 {len(candidates)} 个可回退镜像，无法回退 -{steps}"
            )
        target = candidates[steps - 1]
        target_reference = resolve_digest_reference(repository, target)
        plan.append(RollbackTarget(name, steps, latest, target, target_reference))
    return plan


def print_plan(plan):
    for item in plan:
        latest_id = item.latest["Id"].removeprefix("sha256:")[:12]
        target_digest = item.target_reference.rsplit("@", 1)[-1].removeprefix(
            "sha256:"
        )[:12]
        print(
            f"{item.name}: latest ID {latest_id} ({item.latest['Created']})"
            f" -> -{item.steps} digest {target_digest} ({item.target['Created']})",
            flush=True,
        )


def main():
    def parse_target(value):
        match = re.fullmatch(r"(.+)-([1-9][0-9]*)", value)
        if not match:
            raise argparse.ArgumentTypeError("格式: 服务名-回退步数，如 app-1")
        return match[1], int(match[2])

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", help="项目名，对应 /root/<项目名>")
    parser.add_argument(
        "targets",
        nargs="+",
        type=parse_target,
        metavar="SERVICE-N",
        help="服务名-回退步数，如 app-1 web-2",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="仅预览，不修改配置或重建容器"
    )
    args = parser.parse_args()
    if len({name for name, _ in args.targets}) != len(args.targets):
        parser.error("服务名不能重复")

    if args.project in (".", "..") or "/" in args.project:
        parser.error("项目名不能包含路径")
    os.chdir(Path("/root") / args.project)
    project = ComposeProject(Path.cwd() / "docker-compose.yml")
    plan = resolve_plan(project.config, args.targets)
    target_images = {item.name: item.target_reference for item in plan}
    modified = project.render_images(target_images)
    print_plan(plan)

    if args.dry_run:
        return

    project.apply_images(target_images, modified)
    project.recreate([item.name for item in plan])
    print("回退完成，请验证业务状态。")


if __name__ == "__main__":
    try:
        main()
    except (RollbackError, OSError, ValueError, KeyError) as error:
        print(f"回退失败: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
