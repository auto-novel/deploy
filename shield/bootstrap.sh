#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/linux"

install_if_changed() {
    local source="$1" target="$2" mode="$3"
    if [[ ! -f "$target" ]] || ! cmp -s "$source" "$target" || [[ "$(stat -c '%a' "$target")" != "$mode" ]]; then
        install -Dm"$mode" "$source" "$target"
    fi
}

download_if_changed() {
    local url="$1" target="$2" mode="$3" temporary
    temporary="$(mktemp)"
    trap 'rm -f "$temporary"' RETURN
    curl -fsSL "$url" -o "$temporary"
    install_if_changed "$temporary" "$target" "$mode"
    trap - RETURN
    rm -f "$temporary"
}

write_if_changed() {
    local target="$1" mode="$2" content="$3" temporary
    temporary="$(mktemp)"
    printf '%s\n' "$content" > "$temporary"
    install_if_changed "$temporary" "$target" "$mode"
    rm -f "$temporary"
}

echo "[INFO] 配置软件源并安装依赖..."
install -m 0755 -d /etc/apt/keyrings /usr/share/keyrings
download_if_changed https://download.docker.com/linux/debian/gpg /etc/apt/keyrings/docker.asc 0644
write_if_changed /etc/apt/sources.list.d/docker.list 0644 "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable"
download_if_changed https://pkg.cloudflare.com/cloudflare-main.gpg /usr/share/keyrings/cloudflare-main.gpg 0644
write_if_changed /etc/apt/sources.list.d/cloudflared.list 0644 "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main"
codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:?未找到 Debian VERSION_CODENAME}")"
download_if_changed "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" /usr/share/keyrings/tailscale-archive-keyring.gpg 0644
download_if_changed "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" /etc/apt/sources.list.d/tailscale.list 0644
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin cloudflared tailscale

if ! tailscale status --json 2>/dev/null | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
    echo "[INFO] 请完成 Tailscale 登录..."
    tailscale up
fi

exec ../apply.sh "$@"
