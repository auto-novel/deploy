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

echo "[INFO] 同步 Core 配置..."
install_if_changed ./etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo.sh 0644
install_if_changed ./root/.bashrc /root/.bashrc 0644

install_if_changed ./etc/systemd/system/update-apps.service /etc/systemd/system/update-apps.service 0644
install_if_changed ./etc/systemd/system/update-apps.timer /etc/systemd/system/update-apps.timer 0644
install_if_changed ./etc/systemd/system/auto-novel-tmp-cleanup.service /etc/systemd/system/auto-novel-tmp-cleanup.service 0644
install_if_changed ./etc/systemd/system/auto-novel-tmp-cleanup.timer /etc/systemd/system/auto-novel-tmp-cleanup.timer 0644
install_if_changed ./usr/local/bin/update-apps /usr/local/bin/update-apps 0755
systemctl daemon-reload
systemctl enable --now update-apps.timer auto-novel-tmp-cleanup.timer

if "$apply_firewall"; then
    port="${SSH_PORT:-}"
    if [[ -z "$port" && -f /etc/default/deploy-firewall ]]; then
        port="$(< /etc/default/deploy-firewall)"
    fi
    [[ "$port" =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) || {
        echo "首次配置防火墙请设置 SSH_PORT（1 到 65535）；必须与 sshd 监听端口一致" >&2
        exit 1
    }
    temporary="$(mktemp)"
    trap 'rm -f -- "$temporary"' EXIT
    sed "s/12345/$port/g" ./etc/nftables.conf > "$temporary"
    nft -c -f "$temporary"
    # Do not restart nftables: its ExecStop may flush Docker/Tailscale rules.
    nft -f "$temporary"
    install -Dm0644 "$temporary" /etc/nftables.conf
    printf '%s\n' "$port" > "$temporary"
    install -Dm0600 "$temporary" /etc/default/deploy-firewall
    systemctl enable nftables
    echo "[INFO] 已更新防火墙（SSH 端口 $port），请另开连接确认可登录。"
fi
