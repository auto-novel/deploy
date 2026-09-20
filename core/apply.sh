#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/linux"

install_if_changed() {
    local source="$1" target="$2" mode="$3"
    if [[ ! -f "$target" ]] || ! cmp -s "$source" "$target" || [[ "$(stat -c '%a' "$target")" != "$mode" ]]; then
        install -Dm"$mode" "$source" "$target"
    fi
}

echo "[INFO] 同步 Core 配置..."
timedatectl set-timezone Asia/Shanghai
[[ ! -s /etc/motd ]] || : > /etc/motd
hostnamectl set-hostname core
install_if_changed ./etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo.sh 0644
install_if_changed ./root/.bashrc /root/.bashrc 0644

install_if_changed ./etc/systemd/system/update-apps.service /etc/systemd/system/update-apps.service 0644
install_if_changed ./etc/systemd/system/update-apps.timer /etc/systemd/system/update-apps.timer 0644
install_if_changed ./etc/systemd/system/auto-novel-tmp-cleanup.service /etc/systemd/system/auto-novel-tmp-cleanup.service 0644
install_if_changed ./etc/systemd/system/auto-novel-tmp-cleanup.timer /etc/systemd/system/auto-novel-tmp-cleanup.timer 0644
install_if_changed ./usr/local/bin/update-apps /usr/local/bin/update-apps 0755
systemctl daemon-reload
systemctl enable --now update-apps.timer auto-novel-tmp-cleanup.timer
