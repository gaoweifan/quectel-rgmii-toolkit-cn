#!/bin/bash

DEVICE=/dev/ttyOUT
BAUD=115200

setup_device() {
    stty -F $DEVICE cs8 $BAUD ignbrk -brkint -icrnl -imaxbel \
        -opost -onlcr -isig -icanon -iexten -echo -echoe -echok \
        -echoctl -echoke noflsh -ixon -crtscts
}

send_at_command() {
    local command="$1"
    
    # 清空设备缓冲区
    echo -n > $DEVICE

    # 发送AT指令
    echo -e "$command\r" > $DEVICE

    # 创建临时文件捕获输出
    tmpfile=$(mktemp)
    
    # 后台读取设备输出
    cat $DEVICE > "$tmpfile" &
    CAT_PID=$!

    # 等待OK或ERROR响应
    while ! grep -qe "OK" -e "ERROR" "$tmpfile"; do
        sleep 1
    done

    # 终止后台进程
    kill $CAT_PID
    wait $CAT_PID 2>/dev/null

    # 捕获原始响应内容
    local response_content=$(cat "$tmpfile")
    
    # 彩色打印输出到终端（标准错误）
    while IFS= read -r line; do
        echo -e "\033[0;32m$line\033[0m" >&2
    done <<< "$response_content"

    # 返回原始内容（标准输出）
    echo "$response_content"

    rm "$tmpfile"
}

# 初始化设备
setup_device

# 发送WWAN查询指令
echo "正在查询WWAN状态..."
response=$(send_at_command 'AT+QMAP="WWAN"')

# 检查AT指令是否成功
if [[ "$response" != *"OK"* ]]; then
    echo -e "\033[0;31mAT指令执行失败\033[0m"
    exit 1
fi

# 解析IPv6状态
ipv6_status=$(echo "$response" | awk -F',' '/\+QMAP: "WWAN".*"IPV6"/ {print $2}' | tr -d ' ')

if [ -z "$ipv6_status" ]; then
    echo -e "\033[0;33m未找到IPv6配置信息\033[0m"
    exit 1
fi

# 判断IPv6连接状态
if [ "$ipv6_status" -eq 1 ]; then
    echo -e "\033[0;34mIPv6连接正常，开始网络检测...\033[0m"
    
    # 执行ping测试
    if ! ping -c 1 -W 1 2409:8080::1 >/dev/null 2>&1; then
        echo -e "\033[0;31m检测到网络丢包，正在重启模块...\033[0m"
        send_at_command 'AT+CFUN=0;+CFUN=1'
    else
        echo -e "\033[0;36m网络连接正常\033[0m"
    fi
else
    echo -e "\033[0;33mIPv6连接未就绪（状态码：$ipv6_status）\033[0m"
fi