#!/bin/bash
# ========================================
# Tunnel Mesh Linux SSH Config 配置脚本
# 在阿里云或 node3 上运行，一键添加隧道连接配置
# ========================================

set -e

echo ""
echo "╔════════════════════════════════════════╗"
echo "║   Tunnel Mesh SSH Config 配置          ║"
echo "╠════════════════════════════════════════╣"
echo "║   一键配置通过Windows隧道连接对方服务器  ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── 判断当前是哪台服务器 ──
CURRENT_HOST=$(hostname)
CURRENT_IP=$(hostname -I | awk '{print $1}')

echo "【本机信息】"
echo "  主机名: $CURRENT_HOST"
echo "  IP: $CURRENT_IP"
echo ""

# ── 选择角色 ──
echo "这台服务器是："
echo "  [1] 阿里云 - 需要通过隧道连接 node3"
echo "  [2] node3  - 需要通过隧道连接 阿里云"
echo ""
read -p "请选择 [1/2]: " ROLE

# ── 配置参数 ──
if [ "$ROLE" = "1" ]; then
    # 阿里云 → node3
    TUNNEL_PORT=2201
    REMOTE_NAME="node3"
    REMOTE_USER="wuxiaoran"
    REMOTE_IDENTITY="~/.ssh/id_node3"
    echo ""
    read -p "隧道端口 [$TUNNEL_PORT]: " INPUT_PORT
    TUNNEL_PORT=${INPUT_PORT:-$TUNNEL_PORT}
    read -p "对方用户名 [$REMOTE_USER]: " INPUT_USER
    REMOTE_USER=${INPUT_USER:-$REMOTE_USER}
elif [ "$ROLE" = "2" ]; then
    # node3 → 阿里云
    TUNNEL_PORT=2223
    REMOTE_NAME="aliyun"
    REMOTE_USER="root"
    REMOTE_IDENTITY="~/.ssh/id_aliyun"
    echo ""
    read -p "隧道端口 [$TUNNEL_PORT]: " INPUT_PORT
    TUNNEL_PORT=${INPUT_PORT:-$TUNNEL_PORT}
    read -p "对方用户名 [$REMOTE_USER]: " INPUT_USER
    REMOTE_USER=${INPUT_USER:-$REMOTE_USER}
else
    echo "无效选择"
    exit 1
fi

# ── 备份原有配置 ──
SSH_CONFIG="$HOME/.ssh/config"
if [ -f "$SSH_CONFIG" ]; then
    cp "$SSH_CONFIG" "$SSH_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    echo "  [备份] $SSH_CONFIG → $SSH_CONFIG.bak.*"
fi

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# ── 检查是否已有相同配置 ──
if grep -q "Host $REMOTE_NAME" "$SSH_CONFIG" 2>/dev/null; then
    echo ""
    echo "  [!] 已存在 Host $REMOTE_NAME 的配置"
    read -p "  是否覆盖？[y/N]: " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        echo "  已取消"
        exit 0
    fi
    # 删除旧配置块
    sed -i "/^# Tunnel Mesh.*$REMOTE_NAME/,/^$/d" "$SSH_CONFIG" 2>/dev/null
    sed -i "/^Host $REMOTE_NAME\$/,/^$/d" "$SSH_CONFIG" 2>/dev/null
fi

# ── 写入配置 ──
cat >> "$SSH_CONFIG" << EOF

# Tunnel Mesh - $REMOTE_NAME（通过 Windows 反向隧道，端口 $TUNNEL_PORT）
Host $REMOTE_NAME
    HostName localhost
    Port $TUNNEL_PORT
    User $REMOTE_USER
    IdentityFile $REMOTE_IDENTITY
    IdentitiesOnly yes
    StrictHostKeyChecking no
    HostKeyAlias $REMOTE_NAME
EOF

chmod 600 "$SSH_CONFIG"

echo ""
echo "════════════════════════════════════════"
echo "  配置完成！"
echo "════════════════════════════════════════"
echo ""
echo "【验证】ssh $REMOTE_NAME hostname"
echo ""
echo "【查看配置】cat $SSH_CONFIG | grep -A8 'Host $REMOTE_NAME'"
echo ""
