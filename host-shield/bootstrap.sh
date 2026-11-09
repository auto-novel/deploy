#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/linux"

timedatectl set-timezone Asia/Shanghai
[[ ! -s /etc/motd ]] || : > /etc/motd
hostnamectl set-hostname "${HOST_NAME:-shd}"

echo "[INFO] 安装基础软件包..."
apt-get update
apt-get install -y zip unzip mtr nftables

install -m 0755 -d /etc/apt/keyrings /usr/share/keyrings

echo "[INFO] 配置 Docker 软件源并安装..."
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
printf '%s\n' "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[INFO] 配置 Cloudflared 软件源并安装..."
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
printf '%s\n' "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" > /etc/apt/sources.list.d/cloudflared.list
apt-get update
apt-get install -y cloudflared

echo "[INFO] 配置 Tailscale 软件源并安装..."
codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:?未找到 Debian VERSION_CODENAME}")"
curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.noarmor.gpg" -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL "https://pkgs.tailscale.com/stable/debian/${codename}.tailscale-keyring.list" -o /etc/apt/sources.list.d/tailscale.list
apt-get update
apt-get install -y tailscale

if ! tailscale status --json 2>/dev/null | grep -q '"BackendState"[[:space:]]*:[[:space:]]*"Running"'; then
    echo "[INFO] 请完成 Tailscale 登录..."
    tailscale up
fi

exec ../apply.sh --firewall "$@"
