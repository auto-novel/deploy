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
install_if_changed ./etc/profile.d/sysinfo.sh /etc/profile.d/sysinfo.sh 0644
install_if_changed ./root/.bashrc /root/.bashrc 0644
