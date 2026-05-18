#!/bin/bash
# ========================================
# Tunnel Mesh - Linux 通用契约脚本
# 
# 两种模式：
#   export - 导出本机身份信息（在任何服务器上运行）
#   import - 导入契约文书，自动配置 SSH
# ========================================

set -e

ACTION="${1:-menu}"

# ── 自动获取本机信息 ──
detect_identity() {
    MY_HOSTNAME=$(hostname)
    MY_IP=$(hostname -I | awk '{print $1}')
    MY_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [ -z "$MY_PORT" ] && MY_PORT=22
    MY_USER=$(whoami)

    MY_PUBKEY=""
    if [ -f ~/.ssh/id_ed25519.pub ]; then
        MY_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        MY_PUBKEY=$(cat ~/.ssh/id_rsa.pub)
    fi
    if [ -z "$MY_PUBKEY" ]; then
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "${MY_HOSTNAME}@tunnel" >/dev/null 2>&1
        MY_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    fi
}

# ── 导出模式 ──
do_export() {
    detect_identity

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  本服务器身份信息                                  ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  主机名 : $MY_HOSTNAME"
    echo "║  IP地址 : $MY_IP"
    echo "║  SSH端口: $MY_PORT"
    echo "║  用户名 : $MY_USER"
    echo "║  公钥   : $(echo $MY_PUBKEY | cut -c1-40)..."
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    echo "这个服务器在网络中的角色是？"
    echo "  [1] 我是「仆」- 别人要连我（我需要导出身份给对方）"
    echo "  [2] 我是「中转」- 有公网IP，做隧道中转"
    read -p "选择 [1]: " ROLE
    ROLE=${ROLE:-1}

    echo ""
    if [ "$ROLE" = "2" ]; then
        echo "════════════════════════════════════════"
        echo "  中转服务器身份卡"
        echo "════════════════════════════════════════"
        echo ""
        echo "===IDENTITY==="
        echo "ROLE=relay"
        echo "NAME=$MY_HOSTNAME"
        echo "IP=$MY_IP"
        echo "SSH_PORT=$MY_PORT"
        echo "SSH_USER=$MY_USER"
        echo "PUBKEY=$MY_PUBKEY"
        echo "===END==="
        echo ""
        echo "把上面这段复制给对方。"
    else
        echo "对方能用什么方式连你？"
        echo "  [1] 直接SSH - 对方网络能直接访问你的IP"
        echo "  [2] 反向隧道 - 对方不能直连你，需要中转"
        read -p "选择 [1]: " REACH
        REACH=${REACH:-1}

        if [ "$REACH" = "2" ]; then
            echo ""
            echo "需要一个「中转服务器」（有公网IP，大家都能连）"
            read -p "中转服务器IP（如云服务器地址）: " RELAY_IP
            read -p "中转服务器SSH端口 [22]: " RELAY_PORT
            RELAY_PORT=${RELAY_PORT:-22}
            read -p "中转服务器用户 [root]: " RELAY_USER
            RELAY_USER=${RELAY_USER:-root}
            read -p "分配给此连接的隧道端口 [2201]: " TUNNEL_PORT
            TUNNEL_PORT=${TUNNEL_PORT:-2201}

            echo ""
            echo "谁来维持这个反向隧道？"
            echo "  [1] 我自己（我能连到中转服务器）"
            echo "  [2] 别人替我维持（如一台能同时连我和中转的Windows）"
            read -p "选择 [1]: " MAINTAINER
            MAINTAINER=${MAINTAINER:-1}

            echo ""
            echo "════════════════════════════════════════"
            echo "  契约文书"
            echo "════════════════════════════════════════"
            echo ""
            echo "===CONTRACT==="
            echo "TYPE=reverse"
            echo "SERVANT_NAME=$MY_HOSTNAME"
            echo "SERVANT_IP=$MY_IP"
            echo "SERVANT_PORT=$MY_PORT"
            echo "SERVANT_USER=$MY_USER"
            echo "RELAY_IP=$RELAY_IP"
            echo "RELAY_PORT=$RELAY_PORT"
            echo "RELAY_USER=$RELAY_USER"
            echo "TUNNEL_PORT=$TUNNEL_PORT"
            echo "PUBKEY=$MY_PUBKEY"

            if [ "$MAINTAINER" = "2" ]; then
                echo "TUNNEL_CMD=ssh -R ${TUNNEL_PORT}:${MY_IP}:${MY_PORT} ${RELAY_USER}@${RELAY_IP}"
                echo "MAINTAINER=bridge"
            else
                echo "MAINTAINER=self"
            fi
            echo "===END==="
            echo ""

            if [ "$MAINTAINER" = "2" ]; then
                echo "【操作指南】"
                echo "  1. 把上面「契约文书」复制给隧道维持者（Windows）"
                echo "  2. 维持者运行: bash linux-contract.sh import"
                echo "  3. 把下面这段复制给中转服务器:"
                echo ""
                echo "  ┌─────────────────────────────────────┐"
                echo "  │ cat >> ~/.ssh/config << 'EF'        │"
                echo "  │ Host $MY_HOSTNAME"
                echo "  │     HostName localhost"
                echo "  │     Port $TUNNEL_PORT"
                echo "  │     User $MY_USER"
                echo "  │     StrictHostKeyChecking no"
                echo "  │     HostKeyAlias $MY_HOSTNAME"
                echo "  │ EF                                   │"
                echo "  │ chmod 600 ~/.ssh/config              │"
                echo "  │ echo '$MY_PUBKEY' >> ~/.ssh/authorized_keys │"
                echo "  └─────────────────────────────────────┘"
            fi
        else
            # 正向：对方直接SSH
            echo ""
            echo "════════════════════════════════════════"
            echo "  契约文书"
            echo "════════════════════════════════════════"
            echo ""
            echo "===CONTRACT==="
            echo "TYPE=direct"
            echo "SERVANT_NAME=$MY_HOSTNAME"
            echo "SERVANT_IP=$MY_IP"
            echo "SERVANT_PORT=$MY_PORT"
            echo "SERVANT_USER=$MY_USER"
            echo "PUBKEY=$MY_PUBKEY"
            echo "===END==="
            echo ""
            echo "【操作指南】"
            echo "  把上面的「契约文书」复制给对方。"
            echo "  对方运行: bash linux-contract.sh import"
            echo "  然后粘贴契约文书即可。"
        fi
    fi
}

# ── 导入模式 ──
do_import() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   导入契约文书                          ║"
    echo "╠════════════════════════════════════════╣"
    echo "║   粘贴对方给你的契约文书（包含 === 行） ║"
    echo "║   粘贴后按 Ctrl+D 然后回车              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    CONTRACT=$(cat)

    # 解析契约
    TYPE=$(echo "$CONTRACT" | grep "^TYPE=" | cut -d= -f2)
    SERVANT_NAME=$(echo "$CONTRACT" | grep "^SERVANT_NAME=" | cut -d= -f2)
    SERVANT_IP=$(echo "$CONTRACT" | grep "^SERVANT_IP=" | cut -d= -f2)
    SERVANT_PORT=$(echo "$CONTRACT" | grep "^SERVANT_PORT=" | cut -d= -f2)
    SERVANT_USER=$(echo "$CONTRACT" | grep "^SERVANT_USER=" | cut -d= -f2)
    TUNNEL_PORT=$(echo "$CONTRACT" | grep "^TUNNEL_PORT=" | cut -d= -f2)
    PUBKEY=$(echo "$CONTRACT" | grep "^PUBKEY=" | cut -d= -f2-)
    TUNNEL_CMD=$(echo "$CONTRACT" | grep "^TUNNEL_CMD=" | cut -d= -f2-)

    if [ -z "$SERVANT_NAME" ]; then
        echo "错误：无效的契约文书"
        exit 1
    fi

    echo ""
    echo "契约类型: $TYPE"
    echo "对方名称: $SERVANT_NAME"

    # 添加公钥
    if [ -n "$PUBKEY" ] && [ "$PUBKEY" != "PUBKEY=" ]; then
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        echo "$PUBKEY" >> ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        echo "✅ 公钥已添加"
    fi

    # 添加SSH config
    mkdir -p ~/.ssh
    [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S)

    if grep -q "Host $SERVANT_NAME" ~/.ssh/config 2>/dev/null; then
        sed -i "/^# Tunnel Mesh.*$SERVANT_NAME/,/^$/d" ~/.ssh/config 2>/dev/null
        sed -i "/^Host ${SERVANT_NAME}$/,/^$/d" ~/.ssh/config 2>/dev/null
    fi

    if [ "$TYPE" = "direct" ]; then
        cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $SERVANT_NAME（直连）
Host $SERVANT_NAME
    HostName $SERVANT_IP
    Port ${SERVANT_PORT:-22}
    User ${SERVANT_USER:-root}
    StrictHostKeyChecking no
EOF
    elif [ "$TYPE" = "reverse" ] && [ -n "$TUNNEL_PORT" ]; then
        cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $SERVANT_NAME（反向隧道）
Host $SERVANT_NAME
    HostName localhost
    Port ${TUNNEL_PORT}
    User ${SERVANT_USER:-root}
    StrictHostKeyChecking no
    HostKeyAlias $SERVANT_NAME
EOF
    fi

    chmod 600 ~/.ssh/config
    echo "✅ SSH config 已添加"

    # 如果有隧道命令，输出
    if [ -n "$TUNNEL_CMD" ]; then
        echo ""
        echo "════════════════════════════════════════"
        echo "  需要维持的隧道命令:"
        echo "  $TUNNEL_CMD"
        echo ""
        echo "  请将此命令配置为开机自启。"
        echo "════════════════════════════════════════"
    fi

    echo ""
    echo "════════════════════════════════════════"
    echo "  导入完成！验证:"
    echo "  ssh $SERVANT_NAME hostname"
    echo "════════════════════════════════════════"
}

# ── 主菜单 ──
if [ "$ACTION" = "export" ]; then
    do_export
elif [ "$ACTION" = "import" ]; then
    do_import
else
    echo "Tunnel Mesh - Linux 契约脚本"
    echo ""
    echo "用法:"
    echo "  bash linux-contract.sh export    导出本机身份"
    echo "  bash linux-contract.sh import    导入对方契约"
    echo ""
    read -p "选择 [export/import]: " ACTION
    if [ "$ACTION" = "export" ]; then
        do_export
    elif [ "$ACTION" = "import" ]; then
        do_import
    fi
fi
