#!/bin/bash
# ========================================
# 身份检测 - 自动获取本机全部信息
# ========================================

detect_identity() {
    HOSTNAME=$(hostname)
    IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(timeout 3 curl -s ifconfig.me 2>/dev/null || timeout 3 curl -s icanhazip.com 2>/dev/null || echo "")
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

    # 判断网络类型
    if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ]; then
        NET_TYPE="cloud"
        TUNNEL_IP="$PUBLIC_IP"
    else
        NET_TYPE="lan"
        TUNNEL_IP="$IP"
    fi
}

show_identity() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  本机: $HOSTNAME"
    echo "╠════════════════════════════════════════╣"
    echo "║  内网IP : $IP"
    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "║  公网IP : $PUBLIC_IP"
    echo "║  SSH端口: $PORT"
    echo "║  用户   : $USER"
    [ -n "$FINGERPRINT" ] && echo "║  指纹   : $FINGERPRINT"
    echo "║  类型   : $NET_TYPE"
    echo "╚════════════════════════════════════════╝"
}

export_identity() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  身份卡（复制给对方）"
    echo "════════════════════════════════════════"
    echo ""
    echo "===IDENTITY==="
    echo "NAME=$HOSTNAME"
    echo "IP=$IP"
    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "PUBLIC_IP=$PUBLIC_IP"
    echo "PORT=$PORT"
    echo "USER=$USER"
    echo "PUBKEY=$PUBKEY"
    echo "FINGERPRINT=${FINGERPRINT:-unknown}"
    echo "===END==="
    echo ""
}
