#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/linux"

echo "[INFO] 配置软件源并安装依赖..."
install -m 0755 -d /etc/apt/keyrings /usr/share/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
printf '%s\n' "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
printf '%s\n' "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" > /etc/apt/sources.list.d/cloudflared.list
codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:?未找到 Debian VERSION_CODENAME}")"
curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin cloudflared tailscale

if [[ -n "${SSH_PORT:-}" ]]; then
    [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) || { echo "SSH_PORT 必须是 1 到 65535 的端口号" >&2; exit 1; }
    temporary="$(mktemp)"
    trap 'rm -f "$temporary"' EXIT
    sed "s/12345/${SSH_PORT}/g" ./etc/nftables.conf > "$temporary"
    nft -c -f "$temporary"
    install -Dm0644 "$temporary" /etc/nftables.conf
    systemctl restart nftables
fi

if ! tailscale status --json 2>/dev/null | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
    echo "[INFO] 请完成 Tailscale 登录..."
    tailscale up
fi

exec ../apply.sh "$@"
