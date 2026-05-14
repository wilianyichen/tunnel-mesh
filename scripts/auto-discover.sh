#!/bin/bash
# 自动发现可达服务器

set -e

echo "🔍 扫描网络发现服务器..."
echo ""

# 1. 检查已知 SSH config
echo "1. 检查 SSH config 中的已知服务器:"
echo "-----------------------------------"
if [ -f ~/.ssh/config ]; then
    grep -E "^Host " ~/.ssh/config | grep -v "^Host \*" | while read line; do
        host=$(echo "$line" | awk '{print $2}')
        echo "  - $host"
    done
fi
echo ""

# 2. 检查 config.d 目录
echo "2. 检查 SSH config.d 目录:"
echo "-----------------------------------"
if [ -d ~/.ssh/config.d ]; then
    for conf in ~/.ssh/config.d/*.conf; do
        if [ -f "$conf" ]; then
            hosts=$(grep -E "^Host " "$conf" | awk '{print $2}')
            echo "  文件: $conf"
            for h in $hosts; do
                echo "    - $h"
            done
        fi
    done
fi
echo ""

# 3. 测试连接
echo "3. 测试已知服务器连接:"
echo "-----------------------------------"
for host in $(grep -E "^Host " ~/.ssh/config ~/.ssh/config.d/*.conf 2>/dev/null | awk '{print $2}' | grep -v "\*"); do
    echo "  测试 $host..."
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" "echo ok" 2>/dev/null; then
        echo "    ✓ 连接成功"
    else
        echo "    ✗ 连接失败"
    fi
done
echo ""

# 4. 扫描本地网络（可选）
echo "4. 扫描本地网络（需要 nmap）:"
echo "-----------------------------------"
if command -v nmap &> /dev/null; then
    echo "  扫描常见端口..."
    # 扫描本地网络中开放 SSH 端口的机器
    # nmap -p 22 --open -T4 192.168.1.0/24 2>/dev/null | grep "Nmap scan report"
    echo "  （跳过，需要指定网络范围）"
else
    echo "  nmap 未安装，跳过网络扫描"
fi
echo ""

echo "✅ 发现完成"