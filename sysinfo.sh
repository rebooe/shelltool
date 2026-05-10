#!/bin/bash

# 颜色定义
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

print_separator() {
    printf "%s\n" "============================================================"
}

print_info() {
    local title="$1"
    local content="$2"
    printf "  ${BOLD}%-14s${RESET}: %s\n" "$title" "$content"
}

# 获取准确的显卡型号
get_gpu_model() {
    local gpu_info=""
    
    # 方法1: nvidia-smi (最准确)
    if command -v nvidia-smi &> /dev/null; then
        gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        [ -n "$gpu_info" ] && echo "$gpu_info" && return
    fi
    
    # 方法2: lspci + 查询设备名称
    if command -v lspci &> /dev/null; then
        # 尝试获取详细输出
        gpu_info=$(lspci 2>/dev/null | grep -E "VGA|3D|Display" | head -1 | sed -E 's/^[^:]*://; s/ \(rev [^)]*\)//; s/ (prog-if [^)]*\)//')
        
        # 如果还是只显示 "NVIDIA Corporation Device xxxx"，尝试转换
        if echo "$gpu_info" | grep -qi "NVIDIA.*Device [0-9a-f]" && command -v curl &> /dev/null; then
            # 提取设备ID
            pci_id=$(lspci -n 2>/dev/null | grep -E "0300|0302|0380" | head -1 | grep -oE '[0-9a-f]{4}:[0-9a-f]{4}$')
            if [ -n "$pci_id" ]; then
                vendor="${pci_id%:*}"
                device="${pci_id#*:}"
                # 在线查询
                gpu_info=$(curl -s "https://pci-ids.ucw.cz/read/PC/$vendor/$device" 2>/dev/null | grep -oP '(?<=<a href="[^"]+">)[^<]+' | head -1)
            fi
        fi
    fi
    
    # 方法3: glxinfo
    if [ -z "$gpu_info" ] && command -v glxinfo &> /dev/null; then
        gpu_info=$(glxinfo -B 2>/dev/null | grep "OpenGL renderer" | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')
    fi
    
    # 如果还没获取到，尝试从已加载的内核模块推断
    if [ -z "$gpu_info" ] && lsmod | grep -q nvidia; then
        gpu_info="NVIDIA GPU (驱动已加载, 运行 nvidia-smi 查看型号)"
    fi
    
    echo "${gpu_info:-未检测到}"
}

echo ""
print_separator
printf "${BOLD}${BLUE}          系统硬件与系统信息${RESET}\n"
print_separator

# 系统版本
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_INFO="${PRETTY_NAME:-$NAME $VERSION}"
else
    OS_INFO="未知"
fi
print_info "系统版本" "$OS_INFO"
print_info "内核版本" "$(uname -r)"
print_info "主机名" "$(hostname)"

# 运行时间
if command -v uptime &> /dev/null; then
    UPTIME_INFO=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F 'up ' '{print $2}' | awk -F ',' '{print $1}')
else
    UPTIME_INFO="无法获取"
fi
print_info "运行时间" "$UPTIME_INFO"

# CPU信息
if command -v lscpu &> /dev/null; then
    CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')
    [ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d':' -f2 | sed 's/^[ \t]*//')
    CPU_CORES=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo)
else
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d':' -f2 | sed 's/^[ \t]*//')
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
fi
print_info "CPU 型号" "${CPU_MODEL:-无法获取}"
print_info "CPU 核心数" "${CPU_CORES:-无法获取}"

# 内存信息
if command -v free &> /dev/null; then
    MEM_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
else
    MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_MB=$((MEM_KB / 1024))
    [ $MEM_MB -gt 1024 ] && MEM_TOTAL="$((MEM_MB / 1024)) GiB" || MEM_TOTAL="${MEM_MB} MiB"
fi
print_info "内存总量" "${MEM_TOTAL:-无法获取}"

# 显卡信息（使用改进版）
GPU_INFO=$(get_gpu_model)
print_info "显卡" "$GPU_INFO"

# 硬盘信息
if command -v lsblk &> /dev/null; then
    DISK_INFO=$(lsblk -d -o MODEL,SIZE 2>/dev/null | grep -v "MODEL" | head -2 | awk '{if(NF>=2) print $0}' | paste -sd '; ' -)
    [ -z "$DISK_INFO" ] && DISK_INFO=$(lsblk -d -o SIZE 2>/dev/null | grep -v "SIZE" | head -2 | paste -sd '; ' -)
fi
[ -z "$DISK_INFO" ] && DISK_INFO=$(df -BG --total 2>/dev/null | grep '^total' | awk '{print "总容量 " $2}')
print_info "硬盘" "${DISK_INFO:-无法获取}"

# 根分区使用
if command -v df &> /dev/null; then
    ROOT_USAGE=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
fi
print_info "根分区使用" "${ROOT_USAGE:-无法获取}"

# 系统负载
if command -v uptime &> /dev/null; then
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
elif [ -f /proc/loadavg ]; then
    LOAD_AVG=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
fi
print_info "系统负载(1,5,15)" "${LOAD_AVG:-无法获取}"

print_separator
echo ""