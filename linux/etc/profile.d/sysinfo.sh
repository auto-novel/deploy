#!/bin/bash

# if [[ $- != *i* || ! -t 1 ]]; then
#     return 0 2>/dev/null || exit 0
# fi

(
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
DIM="\e[2m"
RESET="\e[0m"

#######################################
# 处理器信息、负载和运行时间
#######################################

# 获取处理器信息
CPU_NAME=$(grep "model name" /proc/cpuinfo | cut -d ' ' -f3- | head -1)
CPU_COUNT=$(grep -c '^processor' /proc/cpuinfo)
# 获取系统运行天数
DAYS=$(awk '{print int($1/86400)}' /proc/uptime)
# 获取CPU负载平均值
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg

echo
printf ' CPU:     %s (%b%s%b vCPU)\n' "$CPU_NAME" "$GREEN" "$CPU_COUNT" "$RESET"
printf ' Load:    %b%s%b 1m / %b%s%b 5m / %b%s%b 15m\n' \
    "$GREEN" "$LOAD1" "$RESET" \
    "$GREEN" "$LOAD5" "$RESET" \
    "$GREEN" "$LOAD15" "$RESET"
printf ' Uptime:  %b%s%b days\n' "$GREEN" "$DAYS" "$RESET"

#######################################
# 内存、磁盘使用
#######################################

echo
echo "Usage:"
print_bar() {
    local usage=$1
    local max_usage=90
    local bar_width=50
    local used_width=$(( ($usage*$bar_width) / 100))

    local color=$([ "$usage" -ge "$max_usage" ] && echo "$RED" || echo "$GREEN")
    local bar=$(printf "%-${bar_width}s" | tr ' ' '=')
    printf ' [%b%s%b%b%s%b]\n' \
        "$color" "${bar:0:used_width}" "$RESET" \
        "$DIM" "${bar:used_width}" "$RESET"
}

# 显示内存使用情况
read -r USED TOTAL _ <<< "$(free -b | awk '/Mem:/ {print $3, $2}')"
mem_pcent=$(( USED * 100 / TOTAL ))
printf "  %-28s %4d%% used out of %3dG\n" "memory" "$mem_pcent" "$((TOTAL / 1024/1024/1024))"
print_bar "$mem_pcent"

# 显示磁盘使用情况，忽略 zfs、squashfs 和 tmpfs
mapfile -t dfs < <(df -H -x zfs -x squashfs -x tmpfs -x devtmpfs -x overlay --output=target,pcent,size | tail -n+2)
for line in "${dfs[@]}"; do
    read -r mount_point usage size <<< "$(echo "$line" | awk '{gsub(/%/, "", $2); print $1, $2, $3}')"
    printf "  %-28s %4d%% used out of %4s\n" "$mount_point" "$usage" "$size"
    print_bar "$usage"
done

unset -f print_bar

#######################################
# 服务状态
#######################################

services=(
    "nftables"
    "tailscaled"
    "deploy@auto-novel.timer"
    "deploy@auth.timer"
    "deploy@monitor.timer"
    "docker-image-prune.timer"
    "auto-novel-tmp-cleanup.timer"
)

echo
echo "Services status:"
for i in "${!services[@]}"; do
    service=${services[i]}
    load_state="not-found"
    active_state="inactive"

    while IFS='=' read -r property value; do
        case "$property" in
            LoadState) load_state=$value ;;
            ActiveState) active_state=$value ;;
        esac
    done < <(systemctl show "$service" --property=LoadState,ActiveState 2>/dev/null)

    if [[ "$load_state" == "not-found" ]]; then
        symbol="○"
        status="missing"
        color=$DIM
    else
        case "$active_state" in
            active)
                symbol="●"
                status="active"
                color=$GREEN
                ;;
            failed)
                symbol="✕"
                status="failed"
                color=$RED
                ;;
            *)
                symbol="○"
                status="inactive"
                color=$YELLOW
                ;;
        esac
    fi

    (( i % 2 == 0 )) && printf ' '
    printf '%-28s %b%s %-8s%b' "$service" "$color" "$symbol" "$status" "$RESET"
    if (( i % 2 == 0 )); then
        printf '  '
    else
        printf '\n'
    fi
done
(( ${#services[@]} % 2 == 1 )) && printf '\n'

#######################################
# Docker 容器状态
#######################################

echo
echo "Docker status:"

if ! docker_output=$(docker ps -a \
    --format '{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.service"}}|{{.Names}}|{{.State}}' \
    2>/dev/null); then
    printf '  %bDocker is unavailable%b\n' "$DIM" "$RESET"
elif [[ -z "$docker_output" ]]; then
    printf '  %bNo containers%b\n' "$DIM" "$RESET"
else
    mapfile -t containers < <(
        printf '%s\n' "$docker_output" |
            awk -F '|' 'BEGIN { OFS=FS } {
                if ($1 == "") $1 = "standalone"
                if ($2 == "") $2 = $3
                print
            }' |
            sort -t '|' -k1,1 -k2,2 -k3,3
    )

    current_project=""
    project_item_count=0
    for container in "${containers[@]}"; do
        IFS='|' read -r project service name state <<< "$container"

        if [[ "$project" != "$current_project" ]]; then
            if [[ -n "$current_project" ]]; then
                (( project_item_count % 2 == 1 )) && printf '\n'
                echo
            fi
            printf '  %s:\n' "$project"
            current_project=$project
            project_item_count=0
        fi

        case "$state" in
            running)
                symbol="●"
                color=$GREEN
                ;;
            paused|restarting)
                symbol="●"
                color=$YELLOW
                ;;
            *)
                symbol="✕"
                color=$RED
                ;;
        esac

        printf '    %-20s %b%s %-10s%b' \
            "$service" "$color" "$symbol" "$state" "$RESET"
        (( project_item_count += 1 ))
        if (( project_item_count % 2 == 1 )); then
            printf '  '
        else
            printf '\n'
        fi
    done
    (( project_item_count % 2 == 1 )) && printf '\n'
fi
echo
)
