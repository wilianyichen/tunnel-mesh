#!/bin/bash
# ========================================
# Tunnel Mesh 配置导出 (被连接端)
# 在任何需要被远程访问的服务器上运行
# ========================================

echo ""
echo "╔════════════════════════════════════════╗"
echo "║     Tunnel Mesh - 缔结契约             ║"
echo "╠════════════════════════════════════════╣"
echo "║  本脚本生成一份「契约文书」，           ║"
echo "║  复制到对方电脑即可建立连接。           ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ========================================
# 自动获取本机信息
# ========================================
SERVER_NAME=$(hostname)
SERVER_IP=$(hostname -I | awk '{print $1}')
SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$SSH_PORT" ] && SSH_PORT=22

# 获取公钥
PUB_KEY=""
if [ -f ~/.ssh/id_ed25519.pub ]; then
    PUB_KEY=$(cat ~/.ssh/id_ed25519.pub)
elif [ -f ~/.ssh/id_rsa.pub ]; then
    PUB_KEY=$(cat ~/.ssh/id_rsa.pub)
fi

echo "【本机信息】（已自动获取）"
echo "  主机名: $SERVER_NAME"
echo "  IP地址: $SERVER_IP"
echo "  SSH端口: $SSH_PORT"
echo ""

# ========================================
# 选择契约类型
# ========================================
echo "【选择契约类型】"
echo ""
echo "  [1] 平等契约 - 双向连接，互相可以访问"
echo "      条件：两台服务器网络互通，或都有公网IP"
echo "      用法：两台机器都运行此脚本，互相交换契约文书"
echo ""
echo "  [2] 主仆契约 - 单向连接，主端访问仆端"
echo "      条件：需要一台有公网IP的服务器作为「契约之塔」（中转）"
echo "      用法：仆端运行此脚本，契约文书交给主端"
echo ""

read -p "请选择 [1/2]: " CONTRACT_TYPE
CONTRACT_TYPE=${CONTRACT_TYPE:-2}

if [ "$CONTRACT_TYPE" = "1" ]; then
    # 平等契约：双向直连
    echo ""
    echo "════════════════════════════════════════"
    echo "  缔结平等契约"
    echo "════════════════════════════════════════"
    echo ""
    echo "双方网络互通即可，无需中转服务器。"
    echo ""

elif [ "$CONTRACT_TYPE" = "2" ]; then
    # 主仆契约：需要中转服务器
    echo ""
    echo "════════════════════════════════════════"
    echo "  缔结主仆契约"
    echo "════════════════════════════════════════"
    echo ""
    echo "需要一台「契约之塔」（中转服务器）。"
    echo "它必须有一串公网IP，双方都能通过SSH连上它。"
    echo ""
    echo "通常这是你的云服务器（如阿里云、腾讯云）。"
    echo ""

    echo "【契约之塔】"
    read -p "  名称 [aliyun]（给中转服务器起个名，方便记）: " RELAY_NAME
    RELAY_NAME=${RELAY_NAME:-aliyun}

    read -p "  公网IP（中转服务器的公网地址，如 1.2.3.4）: " RELAY_IP

    read -p "  SSH端口 [22]（中转服务器的SSH端口，默认22）: " RELAY_PORT
    RELAY_PORT=${RELAY_PORT:-22}

    read -p "  SSH用户 [root]（用哪个账号登录中转服务器）: " RELAY_USER
    RELAY_USER=${RELAY_USER:-root}
fi

# ========================================
# 生成契约文书
# ========================================
echo ""
echo "────────────────────────────────────────"
echo "  契约文书（复制以下全部内容）"
echo "────────────────────────────────────────"
echo ""
echo "===CONTRACT_START==="
echo "CONTRACT_TYPE=$CONTRACT_TYPE"
echo "CONTRACT_NAME=$SERVER_NAME"
echo "SERVER_NAME=$SERVER_NAME"
echo "SERVER_IP=$SERVER_IP"
echo "SERVER_PORT=$SSH_PORT"
echo "PUB_KEY=$PUB_KEY"

if [ "$CONTRACT_TYPE" = "2" ]; then
    echo "RELAY_NAME=$RELAY_NAME"
    echo "RELAY_IP=$RELAY_IP"
    echo "RELAY_PORT=$RELAY_PORT"
    echo "RELAY_USER=$RELAY_USER"
fi

echo "===CONTRACT_END==="
echo ""
echo "────────────────────────────────────────"
echo ""
echo "【下一步】"
echo "  把上面的「契约文书」复制到对方电脑，"
echo "  在 Tunnel Mesh 中选择「缔结契约」即可。"
echo ""
