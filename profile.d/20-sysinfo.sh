#!/bin/bash

GREEN="\e[1;32m"
RED="\e[1;31m"
DIM="\e[2m"
RESET="\e[0m"

# 获取处理器信息
CPU_NAME=$(grep "model name" /proc/cpuinfo | cut -d ' ' -f3- | head -1)
CPU_COUNT=$(grep -c '^processor' /proc/cpuinfo)
# 获取系统运行天数
DAYS=$(awk '{print int($1/86400)}' /proc/uptime)
# 获取CPU负载平均值
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg

echo
echo -e "  $CPU_NAME ($GREEN$CPU_COUNT$RESET vCPU)"
echo -e "  $GREEN$DAYS$RESET days / $GREEN$LOAD1$RESET 1m / $GREEN$LOAD5$RESET 5m / $GREEN$LOAD15$RESET 15m"
echo

print_bar() {
    local usage=$1
    local max_usage=90
    local bar_width=50
    local used_width=$(( ($usage*$bar_width) / 100))

    local color=$([ "$usage" -ge "$max_usage" ] && echo "$RED" || echo "$GREEN")
    local bar=$(printf "%-${bar_width}s" | tr ' ' '=')
    echo -e " [${color}${bar:0:used_width}${RESET}${DIM}${bar:used_width}${RESET}]"
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
