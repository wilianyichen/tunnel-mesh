# ========================================
# 身份检测库 - 自动获取本机信息
# ========================================

detect_identity() {
    HOSTNAME=$(hostname)
    IP=$(hostname -I | awk '{print $1}')
    PUBLIC_IP=$(timeout 3 curl -s ifconfig.me 2>/dev/null || timeout 3 curl -s icanhazip.com 2>/dev/null || echo "")
    TUNNEL_IP="$IP"
    [ -n "$PUBLIC_IP" ] && TUNNEL_IP="$PUBLIC_IP"
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

show_header() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     Tunnel Mesh  $HOSTNAME             ║"
    echo "╠════════════════════════════════════════╣"
    echo "║  $IP:$PORT                            ║"
    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "║  公网: $PUBLIC_IP"
    echo "╚════════════════════════════════════════╝"
}
