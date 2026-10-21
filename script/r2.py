#!/usr/bin/env python3
"""Convert images under archive/<site>/static to hashed WebP files under dist/."""
import hashlib
import io
import sys
from pathlib import Path

from PIL import Image, ImageOps

# ---------------------------------------------------------------- configuration
ARCHIVE_DIR = Path(__file__).resolve().parent.parent / "archive"
OUTPUT_DIR = Path(__file__).resolve().parent.parent / "dist"
STATIC_DIR = "static"
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".tif", ".tiff", ".bmp"}
WEBP_QUALITY = 60
MAX_EDGE = None  # Optional longest edge in pixels; None keeps the original size.
HASH_LENGTH = 12  # Truncated sha256 used in output filenames.
# -----------------------------------------------------------------------------


def convert(path):
    """Return the encoded WebP bytes for one source image."""
    with Image.open(path) as image:
        if getattr(image, "is_animated", False):
            raise ValueError("animated image")
        image = ImageOps.exif_transpose(image)
        if image.mode not in ("RGB", "RGBA"):
            has_alpha = "A" in image.getbands() or "transparency" in image.info
            image = image.convert("RGBA" if has_alpha else "RGB")
        if MAX_EDGE:
            image.thumbnail((MAX_EDGE, MAX_EDGE), Image.Resampling.LANCZOS)
        buffer = io.BytesIO()
        image.info.clear()  # Drop EXIF, ICC profile, comments, etc.
        image.save(buffer, format="WEBP", quality=WEBP_QUALITY, method=6)
        return buffer.getvalue()


def main():
    if not ARCHIVE_DIR.is_dir():
        sys.exit(f"Error: archive directory not found: {ARCHIVE_DIR}")

    converted = failed = 0
    before = after = 0
    for site in sorted(p for p in ARCHIVE_DIR.iterdir() if p.is_dir()):
        source_root = site / STATIC_DIR
        if not source_root.is_dir():
            continue
        for path in sorted(source_root.rglob("*")):
            if not path.is_file() or path.is_symlink():
                continue
            if path.suffix.lower() not in IMAGE_SUFFIXES:
                continue
            try:
                data = convert(path)
            except (OSError, ValueError) as error:
                print(f"Skip {path}: {error}", file=sys.stderr)
                failed += 1
                continue
            digest = hashlib.sha256(data).hexdigest()[:HASH_LENGTH]
            relative = path.relative_to(source_root)
            target = OUTPUT_DIR / site.name / relative.parent / f"{relative.stem}.{digest}.webp"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            converted += 1
            before += path.stat().st_size
            after += len(data)
            print(f"Built: {target}")
    if not converted:
        sys.exit("Error: no supported images found")
    saved = (1 - after / before) * 100 if before else 0
    print(f"\nConverted {converted} images: {before:,} -> {after:,} bytes ({saved:.1f}% saved)")
    if failed:
        sys.exit(f"{failed} images skipped")


if __name__ == "__main__":
    try:
        main()
    except OSError as error:
        sys.exit(f"Error: {error}")
