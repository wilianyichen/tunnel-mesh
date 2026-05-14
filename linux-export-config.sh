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

# 获取跳板服务器信息
echo "请输入跳板服务器信息："
echo ""
read -p "跳板名称 [aliyun]: " JUMP_NAME
JUMP_NAME=${JUMP_NAME:-aliyun}

read -p "跳板公网IP: " JUMP_IP
read -p "跳板SSH端口 [22]: " JUMP_PORT
JUMP_PORT=${JUMP_PORT:-22}

read -p "跳板用户 [root]: " JUMP_USER
JUMP_USER=${JUMP_USER:-root}

echo ""
echo "────────────────────────────────────────"
echo "  配置文本（复制以下内容到 Windows）"
echo "────────────────────────────────────────"
echo ""
echo "===TUNNEL_CONFIG_START==="
echo "SERVER_NAME=$SERVER_NAME"
echo "SERVER_IP=$SERVER_IP"
echo "SERVER_PORT=$SSH_PORT"
echo "JUMP_NAME=$JUMP_NAME"
echo "JUMP_IP=$JUMP_IP"
echo "JUMP_PORT=$JUMP_PORT"
echo "JUMP_USER=$JUMP_USER"
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
