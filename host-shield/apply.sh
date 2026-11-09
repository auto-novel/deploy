#!/bin/bash
set -euo pipefail

apply_firewall=false
for arg in "$@"; do
    case "$arg" in
        --firewall) apply_firewall=true ;;
        *) echo "用法: $0 [--firewall]" >&2; exit 1 ;;
    esac
done

cd "$(dirname "$0")/linux"

install_if_changed() {
    local source="$1" target="$2" mode="$3"
    if [[ ! -f "$target" ]] || ! cmp -s "$source" "$target" || [[ "$(stat -c '%a' "$target")" != "$mode" ]]; then
        install -Dm"$mode" "$source" "$target"
    fi
}

echo "[INFO] 同步 Shield 配置..."
install_if_changed ./etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo.sh 0644
install_if_changed ./root/.bashrc /root/.bashrc 0644

if "$apply_firewall"; then
    port="$(/usr/sbin/sshd -T | awk '$1 == "port" && !found {print $2; found = 1}')"
    if [[ -z "$port" ]]; then
        echo "未检测到 SSH 端口；未修改防火墙" >&2
        exit 1
    fi
    temporary="$(mktemp)"
    trap 'rm -f -- "$temporary"' EXIT
    sed "s/tcp dport 12345/tcp dport $port/" ./etc/nftables.conf > "$temporary"
    nft -c -f "$temporary"
    # Do not restart nftables: its ExecStop may flush Docker/Tailscale rules.
    nft -f "$temporary"
    install -Dm0644 "$temporary" /etc/nftables.conf
    systemctl enable --now nftables
    echo "[INFO] 已更新防火墙（SSH 端口 $port），请另开连接确认可登录。"
fi
