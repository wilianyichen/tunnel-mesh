#!/bin/bash
# ========================================
set -o pipefail
# shellcheck disable=SC2034
# 身份检测 - 自动获取本机全部信息
# ========================================

# 跨平台 timeout（此处定义一份，因 detect.sh 先于 network.sh 被 source）
_timeout_detect() {
    local sec=$1; shift
    if command -v timeout &>/dev/null; then
        timeout "$sec" "$@"
    elif command -v perl &>/dev/null; then
        perl -e 'alarm shift; exec @ARGV' "$sec" "$@"
    else
        "$@"
    fi
}

detect_identity() {
    HOSTNAME=$(hostname)
    IP=$(hostname -I | awk '{print $1}')
    # 并行检测公网 IP（两个服务同时请求，取先返回的，离线延迟从 6s 降到 3s）
    _ip1=$(mktemp); _ip2=$(mktemp)
    _timeout_detect 3 curl -s ifconfig.me >"$_ip1" 2>/dev/null &
    _timeout_detect 3 curl -s icanhazip.com >"$_ip2" 2>/dev/null &
    wait 2>/dev/null
    PUBLIC_IP=$(head -c 100 "$_ip1" 2>/dev/null)
    [ -z "$PUBLIC_IP" ] && PUBLIC_IP=$(head -c 100 "$_ip2" 2>/dev/null)
    PUBLIC_IP=$(echo "$PUBLIC_IP" | tr -d '[:space:]')
    rm -f "$_ip1" "$_ip2"
    PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [ -z "$PORT" ] && PORT=22
    USER=$(whoami)

    if [ -f ~/.ssh/id_ed25519.pub ]; then
        PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        PUBKEY=$(cat ~/.ssh/id_rsa.pub)
    else
        PUBKEY=""
    fi
    if [ -n "$PUBKEY" ]; then
        FINGERPRINT=$(echo "$PUBKEY" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
    else
        FINGERPRINT=""
    fi

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

# 共享身份卡解析 — 从 stdin 读取，设置全局变量
# 成功: 设置 _ID_NAME _ID_IP _ID_PORT _ID_USER _ID_PUBKEY _ID_PUBLIC_IP _ID_CHECKSUM，返回 0
# 失败: 返回 1
parse_identity_card() {
    local card
    card=$(cat)
    _ID_NAME=$(echo "$card" | grep "^NAME=" | head -1 | cut -d= -f2)
    _ID_IP=$(echo "$card" | grep "^IP=" | head -1 | cut -d= -f2)
    _ID_PORT=$(echo "$card" | grep "^PORT=" | head -1 | cut -d= -f2)
    _ID_USER=$(echo "$card" | grep "^USER=" | head -1 | cut -d= -f2)
    _ID_PUBKEY=$(echo "$card" | grep "^PUBKEY=" | head -1 | cut -d= -f2-)
    _ID_PUBLIC_IP=$(echo "$card" | grep "^PUBLIC_IP=" | head -1 | cut -d= -f2)
    _ID_CHECKSUM=$(echo "$card" | grep "^CHECKSUM=" | head -1 | cut -d= -f2)
    [ -z "$_ID_PUBKEY" ] || [ "$_ID_PUBKEY" = "PUBKEY=" ] && _ID_PUBKEY=$(echo "$card" | grep -E "^ssh-")

    if [ -z "$_ID_NAME" ]; then
        echo "  ❌ 无效身份卡"
        return 1
    fi

    # CHECKSUM 校验
    if [ -n "$_ID_CHECKSUM" ]; then
        local raw recomputed expected
        raw=$(echo "$card" | grep -E "^(NAME|IP|PORT|USER|PUBKEY|FINGERPRINT|PUBLIC_IP)=")
        recomputed=$(echo "$raw" | sha256sum | awk '{print $1}')
        expected="${_ID_CHECKSUM#sha256:}"
        if [ "$recomputed" != "$expected" ]; then
            echo "  ❌ 身份卡校验失败！内容可能已损坏"
            return 1
        fi
        echo "  ✓ 身份卡校验通过"
    else
        echo "  ⚠ 旧格式身份卡，无法校验完整性"
    fi

    _ID_PORT=${_ID_PORT:-22}
    _ID_USER=${_ID_USER:-root}
    return 0
}
