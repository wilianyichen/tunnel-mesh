#!/bin/bash
# import.sh - 导入身份卡 + TCP检测 + 生成隧道命令

do_import() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  粘贴对方身份卡（含 === 行）            ║"
    echo "║  粘贴后 Ctrl+D 回车                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    IDENTITY=$(cat)

    PEER_NAME=$(echo "$IDENTITY" | grep "^NAME=" | cut -d= -f2)
    PEER_IP=$(echo "$IDENTITY" | grep "^IP=" | cut -d= -f2)
    PEER_PUBLIC_IP=$(echo "$IDENTITY" | grep "^PUBLIC_IP=" | cut -d= -f2)
    PEER_PORT=$(echo "$IDENTITY" | grep "^PORT=" | cut -d= -f2)
    PEER_USER=$(echo "$IDENTITY" | grep "^USER=" | cut -d= -f2)
    PEER_PUBKEY=$(echo "$IDENTITY" | grep "^PUBKEY=" | cut -d= -f2-)
    PEER_FP=$(echo "$IDENTITY" | grep "^FINGERPRINT=" | cut -d= -f2)

    PEER_TUNNEL_IP="$PEER_IP"
    [ -n "$PEER_PUBLIC_IP" ] && PEER_TUNNEL_IP="$PEER_PUBLIC_IP"
    [ -z "$PEER_NAME" ] && { echo "❌ 无效身份卡"; return; }

    # 重复检测
    if config_json_get "import json,sys;d=json.load(sys.stdin);cs=d.get('contracts',[]);print(len([c for c in cs if c.get('servant')=='$PEER_NAME']))" | grep -qv "^0$"; then
        echo ""; read -p "⚠ $PEER_NAME 已有契约，覆盖？[y/N]: " OV
        [ "$OV" != "y" ] && [ "$OV" != "Y" ] && { echo "已取消"; return; }
        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['contracts']=[c for c in d.get('contracts',[]) if c.get('servant')!='$PEER_NAME'];print(json.dumps(d,indent=2))")
    fi

    # 保存对方信息
    CONFIG=$(config_json_get "
import json,sys;d=json.load(sys.stdin)
d['servers']['$PEER_NAME']={'name':'$PEER_NAME','ip':'$PEER_IP','public_ip':'${PEER_PUBLIC_IP:-}','port':${PEER_PORT:-22},'user':'${PEER_USER:-root}','fingerprint':'${PEER_FP:-unknown}','imported_at':'$(date -Iseconds)'}
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"

    echo "对方: $PEER_NAME ($PEER_IP:$PEER_PORT)"
    [ -n "$PEER_PUBLIC_IP" ] && [ "$PEER_PUBLIC_IP" != "$PEER_IP" ] && echo "      公网IP: $PEER_PUBLIC_IP"

    # 公钥
    if [ -n "$PEER_PUBKEY" ] && [ "$PEER_PUBKEY" != "PUBKEY=" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if ! grep -qF "$PEER_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "$PEER_PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "✓ 公钥已添加"
        fi
    fi

    # TCP 检测
    echo ""; echo "检测 $PEER_NAME 连通性..."
    [ -n "$PEER_PUBLIC_IP" ] && [ "$PEER_PUBLIC_IP" != "$PEER_IP" ] && echo "  内网IP: $PEER_IP  公网IP: $PEER_PUBLIC_IP"
    echo ""

    CAN_REACH=0
    timeout 3 bash -c "echo >/dev/tcp/${PEER_TUNNEL_IP}/${PEER_PORT}" 2>/dev/null && CAN_REACH=1

    if [ $CAN_REACH -eq 1 ]; then
        echo "✓ 网络可达"
        echo "  [1] 正向直连（推荐）  [2] 反向隧道"
        read -p "选择 [1]: " REACH; REACH=${REACH:-1}
    else
        echo "✗ 网络不可达 → 反向隧道"
        REACH=2
    fi

    if [ "$REACH" = "1" ]; then
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
        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['contracts'].append({'id':'${HOSTNAME}→${PEER_NAME}','master':'$HOSTNAME','servant':'$PEER_NAME','type':'direct','status':'active','created':'$(date -Iseconds)'});print(json.dumps(d,indent=2))")
        config_save "$CONFIG"
        echo ""; echo "✓ ssh $PEER_NAME"
        timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PEER_NAME" "hostname" 2>/dev/null && echo "✓ 连接成功" || echo "⚠ 连接失败，检查密钥"
    else
        echo ""
        if [ $CAN_REACH -eq 1 ]; then echo "  [1] 我自己维持  [2] 外部机器维持"; else echo "  [1] 我自己维持（不可行）  [2] 外部机器维持"; fi
        read -p "选择 [2]: " MAINTAINER; MAINTAINER=${MAINTAINER:-2}
        [ "$MAINTAINER" = "1" ] && [ $CAN_REACH -eq 0 ] && { echo "⚠ 不可行，自动选 [2]"; MAINTAINER=2; }

        TUNNEL_PORT=$(port_allocate)
        read -p "隧道端口 [$TUNNEL_PORT]: " INPUT_PORT; TUNNEL_PORT=${INPUT_PORT:-$TUNNEL_PORT}

        CONFIG_PORT_NEXT=$((TUNNEL_PORT + 1))
        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['ports']['used'].append($TUNNEL_PORT);d['ports']['next']=${CONFIG_PORT_NEXT};print(json.dumps(d,indent=2))")
        config_save "$CONFIG"

        if [ "$MAINTAINER" = "1" ]; then
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:localhost:${PORT} ${PEER_USER}@${PEER_TUNNEL_IP} -p ${PEER_PORT}"
            echo ""; echo "维持命令: $TUNNEL_CMD"; echo "对方访问: ssh -p $TUNNEL_PORT $USER@$IP"
        else
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:${PEER_TUNNEL_IP}:${PEER_PORT} ${USER}@${TUNNEL_IP} -p ${PORT}"
            mkdir -p ~/.ssh
            [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null
            if ! grep -q "Host $PEER_NAME" ~/.ssh/config 2>/dev/null; then
                cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $PEER_NAME（反向隧道:${TUNNEL_PORT}）
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
            echo "  ┌─────────┐       ┌──────────┐       ┌─────────┐"
            echo "  │$HOSTNAME│ ←─── │  维持者   │ ───→ │$PEER_NAME│"
            echo "  │ :$TUNNEL_PORT  │  隧道  │  (桥)    │       │ :$PEER_PORT │"
            echo "  └─────────┘       └──────────┘       └─────────┘"
            echo ""
            echo "  访问: ssh $PEER_NAME"
            echo "  发给 Windows 的隧道命令:"
            echo "  $TUNNEL_CMD"
            echo "════════════════════════════════════════"
        fi

        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['contracts'].append({'id':'${HOSTNAME}→${PEER_NAME}','master':'$HOSTNAME','servant':'$PEER_NAME','type':'reverse','tunnel_port':$TUNNEL_PORT,'tunnel_cmd':'$TUNNEL_CMD','maintainer':'${MAINTAINER}','status':'active','created':'$(date -Iseconds)'});print(json.dumps(d,indent=2))")
        config_save "$CONFIG"
    fi
}
