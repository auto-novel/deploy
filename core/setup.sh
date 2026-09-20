#!/bin/bash
set -euo pipefail

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

install_if_changed() {
    local source="$1" target="$2" mode="$3"

    if [[ ! -f "$target" ]] || ! cmp -s "$source" "$target" || [[ "$(stat -c '%a' "$target")" != "$mode" ]]; then
        install -Dm"$mode" "$source" "$target"
    fi
}

download_if_changed() {
    local url="$1" target="$2" mode="$3" temporary
    temporary="$(mktemp)"

    if ! curl -fsSL "$url" -o "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    install_if_changed "$temporary" "$target" "$mode"
    rm -f "$temporary"
}

write_if_changed() {
    local target="$1" mode="$2" content="$3" temporary
    temporary="$(mktemp)"
    printf '%s\n' "$content" > "$temporary"
    install_if_changed "$temporary" "$target" "$mode"
    rm -f "$temporary"
}

setup_login_shell() {
    log_info "配置登录 shell..."

    # 设置系统时区
    timedatectl set-timezone Asia/Shanghai

    # 清空默认的今日消息
    [[ ! -s /etc/motd ]] || : > /etc/motd

    # 同步登录信息；每次运行均以仓库版本为准。
    install_if_changed ./etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo.sh 0644

    # 修改hostname
    hostnamectl set-hostname core

    # 同步 root 的 shell 配置。
    install_if_changed ./root/.bashrc /root/.bashrc 0644
}

setup_docker() {
    log_info "安装 Docker..."

    # Add Docker's official GPG key:
    install -m 0755 -d /etc/apt/keyrings
    download_if_changed https://download.docker.com/linux/debian/gpg /etc/apt/keyrings/docker.asc 0644

    # Add the repository to Apt sources:
    write_if_changed /etc/apt/sources.list.d/docker.list 0644 "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable"
}

setup_cloudflared() {
    log_info "安装 Cloudflared..."

    # Add Cloudflare's package signing key:
    install -d -m 0755 /usr/share/keyrings
    download_if_changed https://pkg.cloudflare.com/cloudflare-main.gpg /usr/share/keyrings/cloudflare-main.gpg 0644

    # Add Cloudflare's apt repo to your apt repositories:
    write_if_changed /etc/apt/sources.list.d/cloudflared.list 0644 "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main"
}

setup_tailscale() {
    log_info "安装 Tailscale..."

    # Add Tailscale's package signing key and repository:
    download_if_changed https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg /usr/share/keyrings/tailscale-archive-keyring.gpg 0644
    download_if_changed https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list /etc/apt/sources.list.d/tailscale.list 0644
}

install_packages() {
    log_info "更新软件包索引并安装依赖..."

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin cloudflared tailscale
}

setup_tailscale_login() {
    # 已连接的节点无需重复认证；未连接时输出认证链接并等待用户完成登录。
    if ! tailscale ip -4 >/dev/null 2>&1; then
        tailscale up
    fi
}

setup_services() {
    log_info "安装并启用 Core 定时服务..."

    install_if_changed ./etc/systemd/system/update-apps.service /etc/systemd/system/update-apps.service 0644
    install_if_changed ./etc/systemd/system/update-apps.timer /etc/systemd/system/update-apps.timer 0644
    install_if_changed ./etc/systemd/system/auto-novel-tmp-cleanup.service /etc/systemd/system/auto-novel-tmp-cleanup.service 0644
    install_if_changed ./etc/systemd/system/auto-novel-tmp-cleanup.timer /etc/systemd/system/auto-novel-tmp-cleanup.timer 0644
    install_if_changed ./usr/local/bin/update-apps /usr/local/bin/update-apps 0755

    systemctl daemon-reload
    systemctl enable --now update-apps.timer auto-novel-tmp-cleanup.timer
    systemctl restart update-apps.timer auto-novel-tmp-cleanup.timer
}

setup_login_shell
setup_docker
setup_cloudflared
setup_tailscale
install_packages
setup_tailscale_login
setup_services
