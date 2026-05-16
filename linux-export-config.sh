#!/bin/bash
# ========================================
# Tunnel Mesh 配置导出脚本 (Linux/服务器端)
# 一键生成配置文本，复制到 Windows 即可
# ========================================

echo ""
echo "════════════════════════════════════════"
echo "  Tunnel Mesh 配置导出"
echo "════════════════════════════════════════"
echo ""

# 获取本机信息
SERVER_NAME=$(hostname)
SERVER_IP=$(hostname -I | awk '{print $1}')
SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$SSH_PORT" ] && SSH_PORT=22

# 获取公钥（如果存在）
PUB_KEY=""
if [ -f ~/.ssh/id_rsa.pub ]; then
    PUB_KEY=$(cat ~/.ssh/id_rsa.pub)
elif [ -f ~/.ssh/id_ed25519.pub ]; then
    PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)
fi

# 获取中转服务器信息（有公网IP的服务器）
echo "请输入中转服务器信息（就是那台有公网IP的服务器）："
echo "  （例如：你的阿里云服务器）"
echo ""
read -p "中转服务器名称 [aliyun]: " RELAY_NAME
RELAY_NAME=${RELAY_NAME:-aliyun}

read -p "中转服务器公网IP: " RELAY_IP
read -p "中转服务器SSH端口 [22]: " RELAY_PORT
RELAY_PORT=${RELAY_PORT:-22}

read -p "中转服务器用户 [root]: " RELAY_USER
RELAY_USER=${RELAY_USER:-root}

echo ""
echo "────────────────────────────────────────"
echo "  配置文本（复制以下内容到 Windows）"
echo "────────────────────────────────────────"
echo ""
echo "===TUNNEL_CONFIG_START==="
echo "SERVER_NAME=$SERVER_NAME"
echo "SERVER_IP=$SERVER_IP"
echo "SERVER_PORT=$SSH_PORT"
echo "RELAY_NAME=$RELAY_NAME"
echo "RELAY_IP=$RELAY_IP"
echo "RELAY_PORT=$RELAY_PORT"
echo "RELAY_USER=$RELAY_USER"
echo "PUB_KEY=$PUB_KEY"
echo "===TUNNEL_CONFIG_END==="
echo ""
echo "────────────────────────────────────────"
echo ""
echo "使用方法："
echo "1. 复制上面的配置文本（包含 === 行）"
echo "2. 在 Windows 上运行 Tunnel Mesh"
echo "3. 选择 [5] 导入配置"
echo "4. 粘贴配置文本"
echo ""
