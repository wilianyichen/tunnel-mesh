#!/bin/bash
# ========================================
# Tunnel Mesh 一键导出 (任意Linux服务器)
# 自动获取本机信息，生成契约文书
# 复制到对方服务器即可
# ========================================

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║     Tunnel Mesh - 契约文书生成器                  ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  自动获取本机信息，生成一段「契约文书」。         ║"
echo "║  把文书复制到对方服务器粘贴，即可建立连接。       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── 自动获取本机信息 ──
MY_HOSTNAME=$(hostname)
MY_IP=$(hostname -I | awk '{print $1}')
MY_PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
[ -z "$MY_PORT" ] && MY_PORT=22
MY_USER=$(whoami)

# 获取公钥
MY_PUBKEY=""
if [ -f ~/.ssh/id_ed25519.pub ]; then
    MY_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
elif [ -f ~/.ssh/id_rsa.pub ]; then
    MY_PUBKEY=$(cat ~/.ssh/id_rsa.pub)
fi

echo "【本机信息】（以下内容已自动检测）"
echo "  主机名 : $MY_HOSTNAME"
echo "  IP地址 : $MY_IP"
echo "  SSH端口: $MY_PORT"
echo "  当前用户: $MY_USER"
if [ -n "$MY_PUBKEY" ]; then
    echo "  公钥    : $(echo $MY_PUBKEY | cut -c1-40)..."
else
    echo "  公钥    : 未找到（将自动生成）"
fi
echo ""

# ── 收集对方信息 ──
echo "【对方信息】（就是你想连的那台服务器）"
echo ""
echo "  对方是做什么的？"
echo "  [1] 中转服务器 - 有公网IP，做隧道中转（如阿里云）"
echo "  [2] 普通服务器 - 要跟我直连"
read -p "  选择 [1]: " PEER_ROLE
PEER_ROLE=${PEER_ROLE:-1}

echo ""
read -p "  给对方起个名 [peer]: " PEER_NAME
PEER_NAME=${PEER_NAME:-peer}

read -p "  对方的IP地址: " PEER_IP
read -p "  对方的SSH端口 [22]: " PEER_PORT
PEER_PORT=${PEER_PORT:-22}
read -p "  对方的SSH用户 [root]: " PEER_USER
PEER_USER=${PEER_USER:-root}

# ── 如果没有密钥，自动生成 ──
if [ -z "$MY_PUBKEY" ]; then
    echo ""
    echo "正在生成SSH密钥..."
    ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "${MY_HOSTNAME}@tunnel"
    MY_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    echo "  ✓ 密钥已生成"
fi

# ── 确定触达方式 ──
echo ""
echo "【触达方式】"
echo "  你能直接连到 $PEER_NAME 吗？"
echo "  [1] 能 - 正向连接（直接SSH）"
echo "  [2] 不能 - 反向隧道（对方通过隧道连你）"
read -p "  选择 [1]: " REACH
REACH=${REACH:-1}

# ── 分配隧道端口 ──
if [ "$REACH" = "2" ]; then
    TUNNEL_PORT=2201
    read -p "  隧道端口（对方访问你用的端口）[$TUNNEL_PORT]: " INPUT_PORT
    TUNNEL_PORT=${INPUT_PORT:-$TUNNEL_PORT}
    REACH_TYPE="reverse"
    REACH_DESC="反向隧道 - 对方通过隧道访问你"
else
    TUNNEL_PORT=$PEER_PORT
    REACH_TYPE="forward"
    REACH_DESC="正向连接 - 直接SSH"
fi

# ── 生成契约文书 ──
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  契约文书（复制以下全部内容给对方）               ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║                                                  ║"
echo "║  使用方法：                                      ║"
echo "║  对方登录服务器后，粘贴以下全部内容并回车         ║"
echo "║                                                  ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "────────────────────────────────────────"
echo ""

# 生成对方需要执行的命令
if [ "$REACH" = "2" ]; then
    # 反向隧道：对方需要添加SSH config + 知道怎么建隧道
    cat << SCRIPT
# ==== 复制下面全部内容，粘贴到 $PEER_NAME 的终端 ====

# 1. 添加SSH config
cat >> ~/.ssh/config << 'HEREDOC_EOF'

# Tunnel Mesh - $MY_HOSTNAME（反向隧道）
Host $MY_HOSTNAME
    HostName localhost
    Port $TUNNEL_PORT
    User $MY_USER
    StrictHostKeyChecking no
    HostKeyAlias $MY_HOSTNAME
HEREDOC_EOF

chmod 600 ~/.ssh/config

# 2. 添加公钥
echo '$MY_PUBKEY' >> ~/.ssh/authorized_keys

# 3. 告诉维持者（Windows）建立隧道：
echo ""
echo "========================================="
echo " 请将此命令发给维持隧道的人（Windows）："
echo "========================================="
echo ""
echo "  ssh -R $TUNNEL_PORT:$MY_IP:$MY_PORT $PEER_USER@$PEER_IP"
echo ""
echo "  对方IP: $PEER_IP"
echo "  隧道端口: $TUNNEL_PORT"
echo "  你的IP: $MY_IP"
echo "  你的端口: $MY_PORT"
echo ""
echo "========================================="
echo " 建立完成后，在这里验证："
echo " ssh $MY_HOSTNAME hostname"
echo "========================================="
SCRIPT

else
    # 正向连接：对方直接SSH过来
    cat << SCRIPT
# ==== 复制下面全部内容，粘贴到 $PEER_NAME 的终端 ====

# 1. 添加SSH config
cat >> ~/.ssh/config << 'HEREDOC_EOF'

# Tunnel Mesh - $MY_HOSTNAME（正向连接）
Host $MY_HOSTNAME
    HostName $MY_IP
    Port $MY_PORT
    User $MY_USER
    StrictHostKeyChecking no
HEREDOC_EOF

chmod 600 ~/.ssh/config

# 2. 添加公钥
echo '$MY_PUBKEY' >> ~/.ssh/authorized_keys

# 3. 验证连接
echo ""
echo "========================================="
echo " 验证连接："
echo " ssh $MY_HOSTNAME hostname"
echo "========================================="
SCRIPT
fi

echo ""
echo "────────────────────────────────────────"
echo ""
echo "【总结】你需要做的事："
echo "  1. 复制上面 ==== 之间的全部内容"
echo "  2. 登录 $PEER_NAME ($PEER_IP)"
echo "  3. 粘贴到终端，回车"
echo "  4. 完成！"
echo ""
