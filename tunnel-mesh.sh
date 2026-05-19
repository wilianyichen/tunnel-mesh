#!/bin/bash
# ========================================
# Tunnel Mesh - 统一配置向导
# 用法: bash tunnel-mesh.sh
# ========================================

set -e

detect_identity() {
    HOSTNAME=$(hostname)
    IP=$(hostname -I | awk '{print $1}')
    PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [ -z "$PORT" ] && PORT=22
    USER=$(whoami)

    if [ -f ~/.ssh/id_ed25519.pub ]; then
        PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        PUBKEY=$(cat ~/.ssh/id_rsa.pub)
    else
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "${HOSTNAME}@tunnel" >/dev/null 2>&1
        PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    fi
    FINGERPRINT=$(echo "$PUBKEY" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
}

# ── 显示身份 ──
show_identity() {
    detect_identity
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  当前服务器                             ║"
    echo "╠════════════════════════════════════════╣"
    echo "║  主机名 : $HOSTNAME"
    echo "║  IP     : $IP"
    echo "║  SSH端口: $PORT"
    echo "║  用户   : $USER"
    [ -n "$FINGERPRINT" ] && echo "║  公钥指纹: $FINGERPRINT"
    echo "╚════════════════════════════════════════╝"
}

# ── 导出身份卡 ──
do_export() {
    show_identity
    echo ""
    echo "════════════════════════════════════════"
    echo "  身份卡（复制给其他服务器）"
    echo "════════════════════════════════════════"
    echo ""
    echo "===IDENTITY==="
    echo "NAME=$HOSTNAME"
    echo "IP=$IP"
    echo "PORT=$PORT"
    echo "USER=$USER"
    echo "PUBKEY=$PUBKEY"
    echo "===END==="
    echo ""
    echo "对方收到后运行: bash tunnel-mesh.sh import"
}

# ── 导入身份卡 ──
do_import() {
    show_identity

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  粘贴对方的身份卡（含 === 行）          ║"
    echo "║  粘贴后按 Ctrl+D 回车                   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    IDENTITY=$(cat)

    PEER_NAME=$(echo "$IDENTITY" | grep "^NAME=" | cut -d= -f2)
    PEER_IP=$(echo "$IDENTITY" | grep "^IP=" | cut -d= -f2)
    PEER_PORT=$(echo "$IDENTITY" | grep "^PORT=" | cut -d= -f2)
    PEER_USER=$(echo "$IDENTITY" | grep "^USER=" | cut -d= -f2)
    PEER_PUBKEY=$(echo "$IDENTITY" | grep "^PUBKEY=" | cut -d= -f2-)

    if [ -z "$PEER_NAME" ]; then
        echo "❌ 无效的身份卡"
        exit 1
    fi

    echo ""
    echo "对方: $PEER_NAME ($PEER_IP:$PEER_PORT)"

    # ── 添加对方公钥 ──
    if [ -n "$PEER_PUBKEY" ] && [ "$PEER_PUBKEY" != "PUBKEY=" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if ! grep -qF "$PEER_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "$PEER_PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "✓ 对方公钥已添加"
        fi
    fi

    # ── 选择连接方式 ──
    echo ""
    echo "你能直接连到 $PEER_NAME ($PEER_IP) 吗？"
    echo "  [1] 能  → 直接SSH"
    echo "  [2] 不能 → 需要反向隧道"
    read -p "选择: " REACH
    REACH=${REACH:-2}

    if [ "$REACH" = "1" ]; then
        # ── 正向直连 ──
        mkdir -p ~/.ssh
        [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null

        if ! grep -q "Host $PEER_NAME" ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $PEER_NAME（直连）
Host $PEER_NAME
    HostName $PEER_IP
    Port ${PEER_PORT:-22}
    User ${PEER_USER:-root}
    StrictHostKeyChecking no
EOF
            chmod 600 ~/.ssh/config
        fi

        echo ""
        echo "✓ 直连已配置！"
        echo "  ssh $PEER_NAME"

    else
        # ── 反向隧道 ──
        echo ""
        echo "反向隧道需要一台「维持者」机器（能同时连你我）。"
        echo "维持者是？"
        echo "  [1] 我自己（我能连到对方）"
        echo "  [2] 其他机器（如 Windows）"
        read -p "选择: " MAINTAINER
        MAINTAINER=${MAINTAINER:-2}

        # 分配端口
        USED_PORTS=$(grep "Port " ~/.ssh/config 2>/dev/null | grep -oE "[0-9]+" | sort -n)
        TUNNEL_PORT=2201
        while echo "$USED_PORTS" | grep -q "^${TUNNEL_PORT}$"; do
            TUNNEL_PORT=$((TUNNEL_PORT + 1))
        done
        read -p "隧道端口 [$TUNNEL_PORT]: " INPUT_PORT
        TUNNEL_PORT=${INPUT_PORT:-$TUNNEL_PORT}

        if [ "$MAINTAINER" = "1" ]; then
            # 我自己维持
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:localhost:${PORT} ${PEER_USER}@${PEER_IP} -p ${PEER_PORT}"

            echo ""
            echo "════════════════════════════════════════"
            echo "  运行此命令建立隧道:"
            echo "  $TUNNEL_CMD"
            echo ""
            echo "  对方访问你: ssh -p $TUNNEL_PORT $USER@localhost"
            echo "════════════════════════════════════════"

        else
            # 维持者是其他机器（Windows）
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:${PEER_IP}:${PEER_PORT} ${USER}@${IP} -p ${PORT}"
            # 修正：远程端口是本机，转发目标是对端
            # ssh -R <本机监听端口>:<对方IP>:<对方端口> <本机用户>@<本机IP> -p <本机端口>
            # Windows 连本机 → 本机监听 tunnel_port → 转发到对方
            
            # 写入本机 SSH config
            mkdir -p ~/.ssh
            [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null

            if ! grep -q "Host $PEER_NAME" ~/.ssh/config 2>/dev/null; then
                cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $PEER_NAME（反向隧道，由外部维持）
Host $PEER_NAME
    HostName localhost
    Port $TUNNEL_PORT
    User ${PEER_USER:-root}
    StrictHostKeyChecking no
    HostKeyAlias $PEER_NAME
EOF
                chmod 600 ~/.ssh/config
            fi

            echo ""
            echo "════════════════════════════════════════"
            echo "  ✓ 本机 SSH config 已添加:"
            echo "    ssh $PEER_NAME"
            echo ""
            echo "  发给维持者（Windows）的隧道命令:"
            echo "  $TUNNEL_CMD"
            echo ""
            echo "  维持者收到后，在 Windows 契约大厅 [1]导入"
            echo "════════════════════════════════════════"
        fi
    fi
}

# ── 双向连接向导（仅在本机运行，指导全局）
do_wizard() {
    show_identity
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           双向连接配置向导                        ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║                                                  ║"
    echo "║  此向导帮你建立三台服务器的双向连接。              ║"
    echo "║                                                  ║"
    echo "║  你需要准备:                                      ║"
    echo "║  · 两台 Linux 服务器的 SSH 登录信息               ║"
    echo "║  · 一台 Windows 电脑（维持隧道用）                ║"
    echo "║                                                  ║"
    echo "║  操作流程:                                        ║"
    echo "║  ┌─────────┐    ┌─────────┐    ┌─────────┐      ║"
    echo "║  │ 服务器A ├───→│ 服务器B │←───│ Windows │      ║"
    echo "║  │ export  │    │ import  │    │ import  │      ║"
    echo "║  │ 身份卡  │    │+补全隧道│    │ 创隧道  │      ║"
    echo "║  └─────────┘    └─────────┘    └─────────┘      ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "你想做什么？"
    echo "  [1] 我是其中一台 Linux 服务器，导出身份卡"
    echo "  [2] 我是其中一台 Linux 服务器，导入对方身份卡"
    echo "  [3] 我是 Windows，导入隧道命令"
    read -p "选择: " WIZARD
    case $WIZARD in
        1) do_export ;;
        2) do_import ;;
        3) echo "请在 Windows 上运行 windows-contract.bat → [1]导入" ;;
    esac
}

# ── 入口 ──
show_identity 2>/dev/null || detect_identity

if [ "$1" = "export" ]; then
    do_export
elif [ "$1" = "import" ]; then
    do_import
elif [ "$1" = "wizard" ]; then
    do_wizard
else
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     Tunnel Mesh $(hostname)            ║"
    echo "╠════════════════════════════════════════╣"
    echo "║                                        ║"
    echo "║  [1] 导出身份卡（给别人）              ║"
    echo "║  [2] 导入身份卡（连接别人）            ║"
    echo "║  [3] 配置向导（双向连接指导）          ║"
    echo "║                                        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    read -p "选择: " CHOICE
    case $CHOICE in
        1) do_export ;;
        2) do_import ;;
        3) do_wizard ;;
        *) echo "无效选择" ;;
    esac
fi
