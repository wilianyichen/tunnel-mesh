#!/bin/bash
# ========================================
# Tunnel Mesh - Linux 通用契约脚本
# export: 自动检测本机信息 + 问清网络关系 → 生成契约文书
# import: 粘贴对方契约文书 → 自动配置 SSH
# ========================================

set -e

ACTION="${1:-menu}"

detect_identity() {
    MY_HOSTNAME=$(hostname)
    MY_IP=$(hostname -I | awk '{print $1}')
    MY_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [ -z "$MY_PORT" ] && MY_PORT=22
    MY_USER=$(whoami)

    if [ -f ~/.ssh/id_ed25519.pub ]; then
        MY_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        MY_PUBKEY=$(cat ~/.ssh/id_rsa.pub)
    else
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "${MY_HOSTNAME}@tunnel" >/dev/null 2>&1
        MY_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    fi
}

do_export() {
    detect_identity

    FINGERPRINT=$(echo "$MY_PUBKEY" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  本服务器身份（自动检测）               ║"
    echo "╠════════════════════════════════════════╣"
    echo "║  主机名 : $MY_HOSTNAME"
    echo "║  IP     : $MY_IP"
    echo "║  SSH端口: $MY_PORT"
    echo "║  用户名 : $MY_USER"
    if [ -n "$FINGERPRINT" ]; then
        echo "║  公钥指纹: $FINGERPRINT"
    fi
    echo "║  公钥    : [已检测到，会包含在输出的契约文书里]"
    echo "╚════════════════════════════════════════╝"

    # ── 触达方式 ──
    echo "对方能直接连到你吗？"
    echo "  [1] 能       → 直接SSH就行"
    echo "  [2] 不能     → 需要反向隧道"
    read -p "选择: " REACH
    REACH=${REACH:-2}

    if [ "$REACH" = "1" ]; then
        # ── 正向：对方直接SSH ──
        echo ""
        echo "════════════════════════════════════════"
        echo "  契约文书（复制给对方）"
        echo "════════════════════════════════════════"
        echo ""
        echo "===CONTRACT==="
        echo "TYPE=direct"
        echo "NAME=$MY_HOSTNAME"
        echo "IP=$MY_IP"
        echo "PORT=$MY_PORT"
        echo "USER=$MY_USER"
        echo "PUBKEY=$MY_PUBKEY"
        echo "===END==="
        echo ""
        echo "对方收到后运行: bash linux-contract.sh import"
        return
    fi

    # ── 反向隧道 ──
    echo ""
    echo "谁来维持反向隧道？"
    echo "  反向隧道需要有一个"维持者"一直运行 SSH 进程。"
    echo "  [1] 我自己维持     — 我能连到对方服务器"
    echo "  [2] 别人替我维持   — 如一台能同时连我和对方的 Windows"
    read -p "选择: " MAINTAINER
    MAINTAINER=${MAINTAINER:-2}

    if [ "$MAINTAINER" = "1" ]; then
        # 我自己维持
        echo ""
        read -p "对方服务器的IP: " PEER_IP
        read -p "对方SSH端口 [22]: " PEER_PORT
        PEER_PORT=${PEER_PORT:-22}
        read -p "对方用户名 [root]: " PEER_USER
        PEER_USER=${PEER_USER:-root}
        read -p "隧道端口（对方通过哪个端口连你）[2201]: " TUNNEL_PORT
        TUNNEL_PORT=${TUNNEL_PORT:-2201}

        echo ""
        echo "════════════════════════════════════════"
        echo "  你需要运行的命令:"
        echo "  ssh -R ${TUNNEL_PORT}:localhost:${MY_PORT} ${PEER_USER}@${PEER_IP} -p ${PEER_PORT}"
        echo ""
        echo "  对方需要添加到 ~/.ssh/config:"
        echo "  Host $MY_HOSTNAME"
        echo "      HostName localhost"
        echo "      Port $TUNNEL_PORT"
        echo "════════════════════════════════════════"

    else
        # 别人(Bridge)替我维持
        echo ""
        echo "维持者（Windows）需要连接到哪台服务器来建立隧道？"
        echo "  维持者会执行: ssh -R <端口>:你:${MY_PORT} <这台服务器>"
        echo "  这台服务器就是「隧道接收端」。"
        echo "  （比如阿里云的公网IP，Windows 连到它去开隧道端口）"
        echo ""
        read -p "隧道接收端 IP（Windows 要连的那台服务器）: " REMOTE_IP
        read -p "隧道接收端 SSH端口 [22]: " REMOTE_PORT
        REMOTE_PORT=${REMOTE_PORT:-22}
        read -p "隧道接收端 用户名 [root]: " REMOTE_USER
        REMOTE_USER=${REMOTE_USER:-root}
        read -p "隧道接收端 上开的端口（对方通过它连你）[2201]: " TUNNEL_PORT
        TUNNEL_PORT=${TUNNEL_PORT:-2201}

        # 生成隧道命令
        TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:${MY_IP}:${MY_PORT} ${REMOTE_USER}@${REMOTE_IP}"

        echo ""
        echo "════════════════════════════════════════"
        echo "  契约文书（复制给维持者 Windows）"
        echo "════════════════════════════════════════"
        echo ""
        echo "===CONTRACT==="
        echo "TYPE=reverse"
        echo "SERVANT_NAME=$MY_HOSTNAME"
        echo "SERVANT_IP=$MY_IP"
        echo "SERVANT_PORT=$MY_PORT"
        echo "SERVANT_USER=$MY_USER"
        echo "REMOTE_IP=$REMOTE_IP"
        echo "TUNNEL_PORT=$TUNNEL_PORT"
        echo "TUNNEL_CMD=$TUNNEL_CMD"
        echo "PUBKEY=$MY_PUBKEY"
        echo "===END==="
        echo ""
        echo "────────────────────────────────────────"
        echo "  复制到 ${REMOTE_IP}（隧道接收端）:"
        echo "────────────────────────────────────────"
        echo ""
        echo "cat >> ~/.ssh/config << 'EOF'"
        echo ""
        echo "# Tunnel Mesh - $MY_HOSTNAME"
        echo "Host $MY_HOSTNAME"
        echo "    HostName localhost"
        echo "    Port $TUNNEL_PORT"
        echo "    User $MY_USER"
        echo "    StrictHostKeyChecking no"
        echo "    HostKeyAlias $MY_HOSTNAME"
        echo "EOF"
        echo "chmod 600 ~/.ssh/config"
        echo ""
        if [ -n "$MY_PUBKEY" ]; then
            echo "echo '$MY_PUBKEY' >> ~/.ssh/authorized_keys"
        fi
    fi
}

do_import() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   导入契约文书                          ║"
    echo "╠════════════════════════════════════════╣"
    echo "║   粘贴对方的契约文书（包含 === 行）      ║"
    echo "║   粘贴后按 Ctrl+D 然后回车              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    CONTRACT=$(cat)

    TYPE=$(echo "$CONTRACT" | grep "^TYPE=" | cut -d= -f2)
    NAME=$(echo "$CONTRACT" | grep "^NAME=" | cut -d= -f2)
    [ -z "$NAME" ] && NAME=$(echo "$CONTRACT" | grep "^SERVANT_NAME=" | cut -d= -f2)
    IP=$(echo "$CONTRACT" | grep "^IP=" | cut -d= -f2)
    [ -z "$IP" ] && IP=$(echo "$CONTRACT" | grep "^SERVANT_IP=" | cut -d= -f2)
    PORT=$(echo "$CONTRACT" | grep "^PORT=" | cut -d= -f2)
    [ -z "$PORT" ] && PORT=$(echo "$CONTRACT" | grep "^SERVANT_PORT=" | cut -d= -f2)
    USER=$(echo "$CONTRACT" | grep "^USER=" | cut -d= -f2)
    [ -z "$USER" ] && USER=$(echo "$CONTRACT" | grep "^SERVANT_USER=" | cut -d= -f2)
    TUNNEL_PORT=$(echo "$CONTRACT" | grep "^TUNNEL_PORT=" | cut -d= -f2)
    PUBKEY=$(echo "$CONTRACT" | grep "^PUBKEY=" | cut -d= -f2-)
    TUNNEL_CMD=$(echo "$CONTRACT" | grep "^TUNNEL_CMD=" | cut -d= -f2-)

    if [ -z "$NAME" ]; then
        echo "错误：无效的契约文书"
        exit 1
    fi

    echo "契约类型: ${TYPE:-unknown}"
    echo "对方名称: $NAME"

    # 添加公钥
    if [ -n "$PUBKEY" ] && [ "$PUBKEY" != "PUBKEY=" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if ! grep -qF "$PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "$PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "✓ 公钥已添加"
        fi
    fi

    # 备份并写入 SSH config
    mkdir -p ~/.ssh
    [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null

    if grep -q "Host $NAME" ~/.ssh/config 2>/dev/null; then
        echo "  已存在 Host $NAME，跳过"
    else
        if [ "$TYPE" = "direct" ]; then
            cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $NAME（直连）
Host $NAME
    HostName ${IP}
    Port ${PORT:-22}
    User ${USER:-root}
    StrictHostKeyChecking no
EOF
        elif [ "$TYPE" = "reverse" ] && [ -n "$TUNNEL_PORT" ]; then
            cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $NAME（反向隧道）
Host $NAME
    HostName localhost
    Port ${TUNNEL_PORT}
    User ${USER:-root}
    StrictHostKeyChecking no
    HostKeyAlias $NAME
EOF
        fi
        chmod 600 ~/.ssh/config
        echo "✓ SSH config 已添加"
    fi

    # 输出隧道命令
    if [ -n "$TUNNEL_CMD" ]; then
        echo ""
        echo "════════════════════════════════════════"
        echo "  需要维持的隧道命令（发送给维持者）:"
        echo "  $TUNNEL_CMD"
        echo "════════════════════════════════════════"
    fi

    echo ""
    echo "✓ 导入完成！"
    echo "  验证: ssh $NAME hostname"
}

# ── 入口 ──
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
    [ "$ACTION" = "export" ] && do_export
    [ "$ACTION" = "import" ] && do_import
fi
