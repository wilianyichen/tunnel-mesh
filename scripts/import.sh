#!/bin/bash
# import.sh - 导入身份卡 / 部署公钥

# ── 解析身份卡（共用） ──
parse_identity() {
    local IDENTITY="$1"
    PEER_NAME=$(echo "$IDENTITY" | grep "^NAME=" | cut -d= -f2)
    PEER_IP=$(echo "$IDENTITY" | grep "^IP=" | cut -d= -f2)
    PEER_PUBLIC_IP=$(echo "$IDENTITY" | grep "^PUBLIC_IP=" | cut -d= -f2)
    PEER_PORT=$(echo "$IDENTITY" | grep "^PORT=" | cut -d= -f2)
    PEER_USER=$(echo "$IDENTITY" | grep "^USER=" | cut -d= -f2)
    PEER_PUBKEY=$(echo "$IDENTITY" | grep "^PUBKEY=" | cut -d= -f2-)
    [ -z "$PEER_PUBKEY" ] || [ "$PEER_PUBKEY" = "PUBKEY=" ] && \
        PEER_PUBKEY=$(echo "$IDENTITY" | grep -E "^ssh-(rsa|ed25519|dss|ecdsa) ")
    PEER_FP=$(echo "$IDENTITY" | grep "^FINGERPRINT=" | cut -d= -f2)
    PEER_TUNNEL_IP="$PEER_IP"
    [ -n "$PEER_PUBLIC_IP" ] && PEER_TUNNEL_IP="$PEER_PUBLIC_IP"
}

# ── 读取身份卡 ──
read_identity() {
    echo ""
    echo "──────────────────────────────────────"
    echo "  请粘贴对方的身份卡（含 === 行）"
    echo "  粘贴后按 Ctrl+D 然后回车"
    echo "──────────────────────────────────────"
    cat
}

# ══════════════════════════════════════════════════════════
# 部署公钥：对方是主，我是仆。只加公钥，不建立契约。
# ══════════════════════════════════════════════════════════
do_deploy_key() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║   部署公钥                                       ║"
    echo "║                                                  ║"
    echo "║   对方($HOSTNAME的访问者)要连你，你就是仆          ║"
    echo "║   把对方公钥加入 authorized_keys 即可             ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"

    IDENTITY=$(read_identity)
    parse_identity "$IDENTITY"
    [ -z "$PEER_NAME" ] && { echo "❌ 无效身份卡"; return; }

    echo ""
    echo "  📋 对方: $PEER_NAME ($PEER_IP)"

    if [ -n "$PEER_PUBKEY" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if grep -qF "$PEER_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "  ✓ 公钥已存在"
        else
            echo "$PEER_PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "  ✓ 公钥已部署 — $PEER_NAME 现在可以免密登录本机"
        fi
    else
        echo "  ⚠ 未找到公钥"
    fi

    # 保存对方信息到配置
    CONFIG=$(config_load)
    CONFIG=$(config_json_get "
import json,sys;d=json.load(sys.stdin)
d['servers']['$PEER_NAME']={'name':'$PEER_NAME','ip':'$PEER_IP','port':${PEER_PORT:-22},'user':'${PEER_USER:-root},'role':'master','imported_at':'$(date -Iseconds)'}
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"
    echo ""
}

# ══════════════════════════════════════════════════════════
# 导入身份卡：我是主，对方是仆。建立连接契约。
# ══════════════════════════════════════════════════════════
do_import() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║   导入身份卡 — 建立连接                           ║"
    echo "║                                                  ║"
    echo "║   你是主($HOSTNAME)，要连接对方                     ║"
    echo "║   对方是仆，把身份卡给你                          ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"

    IDENTITY=$(read_identity)
    parse_identity "$IDENTITY"
    [ -z "$PEER_NAME" ] && { echo "❌ 无效身份卡"; return; }

    # ── 先部署对方公钥 ──
    if [ -n "$PEER_PUBKEY" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if ! grep -qF "$PEER_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "$PEER_PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "  ✓ 对方公钥已部署"
        fi
    fi

    # 重复检测
    if config_json_get "import json,sys;d=json.load(sys.stdin);cs=d.get('contracts',[]);print(len([c for c in cs if c.get('servant')=='$PEER_NAME']))" | grep -qv "^0$"; then
        echo ""; read -p "⚠ $PEER_NAME 已有契约，覆盖？[y/N]: " OV
        [ "$OV" != "y" ] && [ "$OV" != "Y" ] && { echo "已取消"; return; }
        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['contracts']=[c for c in d.get('contracts',[]) if c.get('servant')!='$PEER_NAME'];print(json.dumps(d,indent=2))")
    fi

    CONFIG=$(config_json_get "
import json,sys;d=json.load(sys.stdin)
d['servers']['$PEER_NAME']={'name':'$PEER_NAME','ip':'$PEER_IP','public_ip':'${PEER_PUBLIC_IP:-}','port':${PEER_PORT:-22},'user':'${PEER_USER:-root},'role':'servant','imported_at':'$(date -Iseconds)'}
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"

    echo ""
    echo "  📋 仆: $PEER_NAME ($PEER_IP:$PEER_PORT)"
    [ -n "$PEER_PUBLIC_IP" ] && [ "$PEER_PUBLIC_IP" != "$PEER_IP" ] && echo "      公网: $PEER_PUBLIC_IP"
    echo "  📋 主: $HOSTNAME"

    # ── TCP 检测 ──
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  检测: $HOSTNAME → $PEER_NAME                    ║"
    echo "╚══════════════════════════════════════════════════╝"

    CAN_REACH=0
    timeout 3 bash -c "echo >/dev/tcp/${PEER_TUNNEL_IP}/${PEER_PORT}" 2>/dev/null && CAN_REACH=1

    if [ $CAN_REACH -eq 1 ]; then
        echo "  ✅ 可达 → [1]直连 [2]隧道"
        read -p "  选择 [1]: " REACH; REACH=${REACH:-1}
    else
        echo "  ❌ 不可达 → 反向隧道"
        REACH=2
    fi

    if [ "$REACH" = "1" ]; then
        mkdir -p ~/.ssh
        [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null
        if ! grep -q "Host $PEER_NAME" ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $PEER_NAME（直连 · 主:$HOSTNAME → 仆:$PEER_NAME）
Host $PEER_NAME
    HostName $PEER_IP
    Port ${PEER_PORT:-22}
    User ${PEER_USER:-root}
    StrictHostKeyChecking no
EOF
            chmod 600 ~/.ssh/config
        fi
        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['contracts'].append({'id':'${HOSTNAME}→${PEER_NAME}','master':'$HOSTNAME','servant':'$PEER_NAME','type':'direct','status':'active','created':'$(date -Iseconds)'});print(json.dumps(d,indent=2))")
        config_save "$CONFIG"
        echo ""; echo "  ✅ ssh $PEER_NAME"
        timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PEER_NAME" "hostname" 2>/dev/null && echo "  ✅ 连接成功" || echo "  ⚠ 连接失败"

    else
        # 反向隧道
        echo ""
        if [ $CAN_REACH -eq 1 ]; then echo "  [1] 我自己维持  [2] 外部机器"; else echo "  [1] 不可行  [2] 外部机器维持"; fi
        read -p "  选择 [2]: " MAINTAINER; MAINTAINER=${MAINTAINER:-2}
        [ "$MAINTAINER" = "1" ] && [ $CAN_REACH -eq 0 ] && { echo "  ⚠ 自动选 [2]"; MAINTAINER=2; }

        TUNNEL_PORT=$(port_allocate)
        read -p "  隧道端口 [$TUNNEL_PORT]: " INPUT_PORT; TUNNEL_PORT=${INPUT_PORT:-$TUNNEL_PORT}

        CONFIG_PORT_NEXT=$((TUNNEL_PORT + 1))
        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['ports']['used'].append($TUNNEL_PORT);d['ports']['next']=${CONFIG_PORT_NEXT};print(json.dumps(d,indent=2))")
        config_save "$CONFIG"

        # IP 选择
        if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && [ "$MAINTAINER" = "2" ]; then
            echo ""; echo "  本机IP，维持者用哪个连你？"
            echo "    [1] 内网: $IP        [2] 公网: $PUBLIC_IP"
            read -p "  选择 [2]: " IP_CHOICE; IP_CHOICE=${IP_CHOICE:-2}
            [ "$IP_CHOICE" = "1" ] && TUNNEL_IP="$IP"
        fi
        if [ -n "$PEER_PUBLIC_IP" ] && [ "$PEER_PUBLIC_IP" != "$PEER_IP" ] && [ "$MAINTAINER" = "2" ]; then
            echo ""; echo "  隧道目标IP？"
            echo "    [1] 内网: $PEER_IP   [2] 公网: $PEER_PUBLIC_IP"
            read -p "  选择 [2]: " PER_IP_CHOICE; PER_IP_CHOICE=${PER_IP_CHOICE:-2}
            [ "$PER_IP_CHOICE" = "1" ] && PEER_TUNNEL_IP="$PEER_IP"
        fi

        if [ "$MAINTAINER" = "1" ]; then
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:localhost:${PORT} ${PEER_USER}@${PEER_TUNNEL_IP} -p ${PEER_PORT}"
            echo ""; echo "  隧道命令: $TUNNEL_CMD"
        else
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:${PEER_TUNNEL_IP}:${PEER_PORT} ${USER}@${TUNNEL_IP} -p ${PORT}"

            mkdir -p ~/.ssh
            [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null
            if ! grep -q "Host $PEER_NAME" ~/.ssh/config 2>/dev/null; then
                cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $PEER_NAME（隧道 · 主:$HOSTNAME → 仆:$PEER_NAME :$TUNNEL_PORT）
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
            echo "╔══════════════════════════════════════════════════╗"
            echo "║  主($HOSTNAME) → 仆($PEER_NAME)                   ║"
            echo "╠══════════════════════════════════════════════════╣"
            echo "║  ┌─────────┐       ┌──────────┐       ┌─────────┐║"
            echo "║  │$HOSTNAME│ ←─── │  维持者   │ ───→ │$PEER_NAME│║"
            echo "║  │ :$TUNNEL_PORT  │          │       │ :$PEER_PORT │║"
            echo "║  └─────────┘       └──────────┘       └─────────┘║"
            echo "║  ssh $PEER_NAME                                    ║"
            echo "║  维持者命令: $TUNNEL_CMD"
            echo "╚══════════════════════════════════════════════════╝"
        fi

        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['contracts'].append({'id':'${HOSTNAME}→${PEER_NAME}','master':'$HOSTNAME','servant':'$PEER_NAME','type':'reverse','tunnel_port':$TUNNEL_PORT,'tunnel_cmd':'$TUNNEL_CMD','maintainer':'${MAINTAINER}','status':'active','created':'$(date -Iseconds)'});print(json.dumps(d,indent=2))")
        config_save "$CONFIG"
    fi
}
