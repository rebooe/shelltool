#!/bin/bash

# 增强版系统信息脚本 - 尽可能处理命令缺失情况

# 颜色定义（仅在终端直接输出时生效）
if [ -t 1 ]; then
    RED=$(printf '\033[31m')
    GREEN=$(printf '\033[32m')
    YELLOW=$(printf '\033[33m')
    BLUE=$(printf '\033[34m')
    BOLD=$(printf '\033[1m')
    RESET=$(printf '\033[0m')
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

# 封装命令执行，无命令时返回空
safe_cmd() {
    if command -v "$1" &> /dev/null; then
        shift
        "$@"
    else
        echo ""
    fi
}

print_separator() {
    printf "%s\n" "============================================================"
}

print_info() {
    local title="$1"
    local content="$2"
    printf "  ${BOLD}%-14s${RESET}: %s\n" "$title" "$content"
}

echo ""
print_separator
printf "${BOLD}${BLUE}          系统硬件与系统信息${RESET}\n"
print_separator

# 系统版本
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_INFO="${PRETTY_NAME:-$NAME $VERSION}"
elif [ -f /etc/redhat-release ]; then
    OS_INFO=$(cat /etc/redhat-release)
elif [ -f /etc/debian_version ]; then
    OS_INFO="Debian $(cat /etc/debian_version)"
else
    OS_INFO="未知 ($(uname -s) $(uname -r))"
fi
KERNEL_VER=$(uname -r)
print_info "系统版本" "$OS_INFO"
print_info "内核版本" "$KERNEL_VER"
print_info "主机名" "$(hostname)"

# 运行时间
if command -v uptime &> /dev/null; then
    UPTIME_INFO=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F 'up ' '{print $2}' | awk -F ',' '{print $1}')
else
    UPTIME_INFO="无法获取"
fi
print_info "运行时间" "$UPTIME_INFO"

# CPU 信息 - 多级fallback
CPU_MODEL=""
if command -v lscpu &> /dev/null; then
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')
fi
if [ -z "$CPU_MODEL" ] && [ -f /proc/cpuinfo ]; then
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | sed 's/^[ \t]*//')
fi
if [ -z "$CPU_MODEL" ]; then
    CPU_MODEL="无法获取"
fi
print_info "CPU 型号" "$CPU_MODEL"

# CPU 核心数
if command -v nproc &> /dev/null; then
    CPU_CORES=$(nproc)
elif [ -f /proc/cpuinfo ]; then
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
else
    CPU_CORES="未知"
fi
print_info "CPU 核心数" "${CPU_CORES}"

# 内存信息
MEM_TOTAL=""
if command -v free &> /dev/null; then
    MEM_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
fi
if [ -z "$MEM_TOTAL" ] && [ -f /proc/meminfo ]; then
    MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_MB=$((MEM_KB / 1024))
    if [ $MEM_MB -gt 1024 ]; then
        MEM_TOTAL="$((MEM_MB / 1024)) GiB"
    else
        MEM_TOTAL="${MEM_MB} MiB"
    fi
fi
print_info "内存总量" "${MEM_TOTAL:-无法获取}"

# 显卡信息 - 多种尝试
GPU_INFO=""
if command -v lspci &> /dev/null; then
    GPU_INFO=$(lspci 2>/dev/null | grep -E "VGA|3D|Display" | head -1 | cut -d':' -f3 | sed 's/^[ \t]*//')
fi
if [ -z "$GPU_INFO" ] && [ -f /proc/driver/nvidia/gpu0/information ]; then
    GPU_INFO=$(head -n1 /proc/driver/nvidia/gpu0/information 2>/dev/null | sed 's/Model://' | sed 's/^[ \t]*//')
fi
if [ -z "$GPU_INFO" ] && command -v glxinfo &> /dev/null; then
    GPU_INFO=$(glxinfo -B 2>/dev/null | grep "OpenGL renderer" | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')
fi
if [ -z "$GPU_INFO" ]; then
    if command -v lspci &> /dev/null; then
        GPU_INFO="未检测到独立显卡（可安装 pciutils 获取更多信息）"
    else
        GPU_INFO="未检测到（缺少 lspci 命令）"
    fi
fi
print_info "显卡" "$GPU_INFO"

# 硬盘信息
DISK_INFO=""
if command -v lsblk &> /dev/null; then
    DISK_ARR=()
    while IFS= read -r line; do
        size=$(echo "$line" | awk '{print $2}')
        model=$(echo "$line" | awk '{print $3}')
        if [ -n "$model" ] && [ "$model" != "model" ]; then
            DISK_ARR+=("${model} (${size})")
        elif [ -n "$size" ] && [ "$size" != "SIZE" ]; then
            DISK_ARR+=("${size}")
        fi
    done < <(lsblk -d -o SIZE,MODEL -b 2>/dev/null | head -4 | tail -n +2)
    
    if [ ${#DISK_ARR[@]} -gt 0 ]; then
        DISK_INFO=$(IFS='; '; echo "${DISK_ARR[*]}")
    fi
fi
if [ -z "$DISK_INFO" ] && command -v fdisk &> /dev/null; then
    DISK_INFO=$(fdisk -l 2>/dev/null | grep "Disk /dev/sd\|/dev/nvme\|/dev/vd" | awk '{print $2 $3 $4}' | head -2 | tr '\n' '; ')
fi
if [ -z "$DISK_INFO" ] && command -v df &> /dev/null; then
    TOTAL_GB=$(df -BG --total 2>/dev/null | grep '^total' | awk '{print $2}' | sed 's/G//')
    [ -n "$TOTAL_GB" ] && DISK_INFO="总容量约 ${TOTAL_GB}GB (df 估算)"
fi
print_info "硬盘" "${DISK_INFO:-无法获取}"

# 根分区使用
ROOT_USAGE=""
if command -v df &> /dev/null; then
    ROOT_USAGE=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
fi
print_info "根分区使用" "${ROOT_USAGE:-无法获取}"

# 系统负载
LOAD_AVG=""
if command -v uptime &> /dev/null; then
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
fi
if [ -f /proc/loadavg ]; then
    LOAD_AVG=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
fi
print_info "系统负载(1,5,15)" "${LOAD_AVG:-无法获取}"

# 额外信息：是否在容器中运行
if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    printf "  ${BOLD}%-14s${RESET}: ${YELLOW}检测到 Docker 容器环境${RESET}\n" "容器环境"
elif [ -f /run/systemd/container ]; then
    printf "  ${BOLD}%-14s${RESET}: ${YELLOW}检测到 systemd-nspawn/LXC 容器${RESET}\n" "容器环境"
fi

print_separator
echo ""