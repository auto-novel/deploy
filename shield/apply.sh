#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/linux"

install_if_changed() {
    local source="$1" target="$2" mode="$3"
    if [[ ! -f "$target" ]] || ! cmp -s "$source" "$target" || [[ "$(stat -c '%a' "$target")" != "$mode" ]]; then
        install -Dm"$mode" "$source" "$target"
    fi
}

echo "[INFO] 同步 Shield 配置..."
timedatectl set-timezone Asia/Shanghai
[[ ! -s /etc/motd ]] || : > /etc/motd
hostnamectl set-hostname shield
install_if_changed ./etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo.sh 0644
install_if_changed ./root/.bashrc /root/.bashrc 0644

if [[ -n "${SSH_PORT:-}" ]]; then
    [[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) || { echo "SSH_PORT 必须是 1 到 65535 的端口号" >&2; exit 1; }
    temporary="$(mktemp)"
    trap 'rm -f "$temporary"' EXIT
    sed "s/12345/${SSH_PORT}/g" ./etc/nftables.conf > "$temporary"
    nft -c -f "$temporary"
    install_if_changed "$temporary" /etc/nftables.conf 0644
    systemctl restart nftables
fi
