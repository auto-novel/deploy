#!/bin/bash
set -e

# 进入脚本所在目录的 linux 子文件夹
cd "$(dirname "$0")/linux" || exit 1

GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
RESET="\e[0m"

log_info() {
    echo -e "${GREEN}[INFO]${RESET} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

setup_login_shell() {
    local hostname=$1

    log_info "配置登录 shell..."

    # 清空默认的今日消息
    > /etc/motd

    # 修改hostname
    cp -n ./etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo.sh

    # 修改hostname
    hostnamectl set-hostname $hostname

    # 配置 bashrc
    cp -n ./root/.bashrc /root/.bashrc
}

setup_docker() {
    log_info "安装 Docker..."

    # Add Docker's official GPG key:
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update

    # Install the Docker packages:
    apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

setup_cloudflared() {
    log_info "安装 Cloudflared..."

    # Add Cloudflare's package signing key:
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null

    # Add Cloudflare's apt repo to your apt repositories:
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" | tee /etc/apt/sources.list.d/cloudflared.list

    # Update repositories and install cloudflared:
    apt-get update && apt-get install cloudflared
}

setup_tailscale() {
    log_info "安装 Tailscale..."

    # Add Tailscale's package signing key and repository:
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list

    # Install Tailscale:
    apt-get update
    apt-get install tailscale

    # Connect your machine to your Tailscale network and authenticate in your browser:
    tailscale up
}

setup_login_shell "$1"
setup_docker
setup_cloudflared
setup_tailscale
