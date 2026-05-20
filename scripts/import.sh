#!/bin/bash
# import.sh - 接收对方身份卡，建立连接

do_import() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║   你现在是：$HOSTNAME                              ║"
    echo "║   你要连接对方，需要对方的身份卡                    ║"
    echo "║                                                  ║"
    echo "║   📋 拿到对方的身份卡了吗？                        ║"
    echo "║      对方运行过 bash tunnel-mesh.sh export        ║"
    echo "║      会输出一段 ===IDENTITY=== ... ===END===      ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "──────────────────────────────────────"
    echo "  请粘贴对方的身份卡（含 === 行）"
    echo "  粘贴后按 Ctrl+D 然后回车"
    echo "──────────────────────────────────────"

    IDENTITY=$(cat)

    PEER_NAME=$(echo "$IDENTITY" | grep "^NAME=" | cut -d= -f2)
    PEER_IP=$(echo "$IDENTITY" | grep "^IP=" | cut -d= -f2)
    PEER_PUBLIC_IP=$(echo "$IDENTITY" | grep "^PUBLIC_IP=" | cut -d= -f2)
    PEER_PORT=$(echo "$IDENTITY" | grep "^PORT=" | cut -d= -f2)
    PEER_USER=$(echo "$IDENTITY" | grep "^USER=" | cut -d= -f2)
    PEER_PUBKEY=$(echo "$IDENTITY" | grep "^PUBKEY=" | cut -d= -f2-)
    PEER_FP=$(echo "$IDENTITY" | grep "^FINGERPRINT=" | cut -d= -f2)

    # 兼容 Windows 导出的身份卡（无 PUBKEY= 标签，直接 ssh- 开头）
    [ -z "$PEER_PUBKEY" ] || [ "$PEER_PUBKEY" = "PUBKEY=" ] && \
        PEER_PUBKEY=$(echo "$IDENTITY" | grep -E "^ssh-(rsa|ed25519|dss|ecdsa) ") 

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

    echo ""
    echo "  📋 对方身份解析成功:"
    echo "     名称: $PEER_NAME"
    echo "     地址: $PEER_IP:$PEER_PORT"
    [ -n "$PEER_PUBLIC_IP" ] && [ "$PEER_PUBLIC_IP" != "$PEER_IP" ] && echo "     公网: $PEER_PUBLIC_IP"
    echo "     用户: $PEER_USER"

    # 公钥
    if [ -n "$PEER_PUBKEY" ] && [ "$PEER_PUBKEY" != "PUBKEY=" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if ! grep -qF "$PEER_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "$PEER_PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "  ✓ 对方公钥已添加 → 对方可以免密登录本机"
        fi
    fi

    # ── 可达性检测 ──
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  正在检测网络连通性...                            ║"
    echo "║                                                  ║"
    echo "║  本机($HOSTNAME) → $PEER_NAME                    ║"
    echo "╚══════════════════════════════════════════════════╝"
    [ -n "$PEER_PUBLIC_IP" ] && [ "$PEER_PUBLIC_IP" != "$PEER_IP" ] && echo "  内网IP: $PEER_IP (本机可能不可达)"; echo "  公网IP: $PEER_PUBLIC_IP (隧道将使用此IP)"

    CAN_REACH=0
    timeout 3 bash -c "echo >/dev/tcp/${PEER_TUNNEL_IP}/${PEER_PORT}" 2>/dev/null && CAN_REACH=1

    if [ $CAN_REACH -eq 1 ]; then
        echo ""
        echo "  ✅ 网络可达 — 你可以直接连接到 $PEER_NAME"
        echo ""
        echo "  选择连接方式："
        echo "    [1] 直连    → 直接 SSH 过去，简单快速"
        echo "    [2] 隧道    → 通过中间服务器转发，更稳定"
        read -p "  选择 [1]: " REACH; REACH=${REACH:-1}
    else
        echo ""
        echo "  ❌ 网络不可达 — 你不能直接连到 $PEER_NAME"
        echo "     这意味着 $PEER_NAME 可能在另一个网络里"
        echo "     需要用「反向隧道」来解决"
        REACH=2
    fi

    if [ "$REACH" = "1" ]; then
        # ── 直连 ──
        echo ""
        echo "  配置直连..."
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
        echo ""
        echo "  ✅ 配置完成!"
        echo "  连接命令: ssh $PEER_NAME"
        timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$PEER_NAME" "hostname" 2>/dev/null && echo "  ✅ 连接测试成功!" || echo "  ⚠️ 连接测试失败，检查对方防火墙/密钥"

    else
        # ── 反向隧道 ──
        echo ""
        echo "╔══════════════════════════════════════════════════╗"
        echo "║  反向隧道：需要一台「维持者」                     ║"
        echo "║                                                  ║"
        echo "║  原理：有一台机器能同时连到你($HOSTNAME)和对方($PEER_NAME)"
        echo "║        它帮你转发流量                             ║"
        echo "║                                                  ║"
        echo "║  谁是这台维持者？                                 ║"
        echo "╚══════════════════════════════════════════════════╝"
        echo ""
        if [ $CAN_REACH -eq 1 ]; then 
            echo "  [1] 我自己 → 本机运行 ssh -R 维持隧道"; 
        else 
            echo "  [1] 我自己 → ❌ 不可行（你无法连到对方）"; 
        fi
        echo "  [2] 外部机器 → 如一台能同时连你和对方的 Windows"
        read -p "  选择 [2]: " MAINTAINER; MAINTAINER=${MAINTAINER:-2}
        [ "$MAINTAINER" = "1" ] && [ $CAN_REACH -eq 0 ] && { echo "  ⚠️ 不可行，自动选 [2]"; MAINTAINER=2; }

        TUNNEL_PORT=$(port_allocate)
        echo ""
        echo "  隧道端口（对方通过此端口访问你）"
        read -p "  端口号 [$TUNNEL_PORT]: " INPUT_PORT; TUNNEL_PORT=${INPUT_PORT:-$TUNNEL_PORT}

        CONFIG_PORT_NEXT=$((TUNNEL_PORT + 1))
        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['ports']['used'].append($TUNNEL_PORT);d['ports']['next']=${CONFIG_PORT_NEXT};print(json.dumps(d,indent=2))")
        config_save "$CONFIG"

        if [ "$MAINTAINER" = "1" ]; then
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:localhost:${PORT} ${PEER_USER}@${PEER_TUNNEL_IP} -p ${PEER_PORT}"
            echo ""
            echo "  运行此命令维持隧道: $TUNNEL_CMD"
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
            echo "╔══════════════════════════════════════════════════╗"
            echo "║  连接已配置！                                     ║"
            echo "╠══════════════════════════════════════════════════╣"
            echo "║                                                  ║"
            echo "║  ┌─────────┐       ┌──────────┐       ┌─────────┐║"
            echo "║  │$HOSTNAME │ ←─── │  维持者   │ ───→ │$PEER_NAME │║"
            echo "║  │ :$TUNNEL_PORT   │  隧道  │  (桥)    │       │ :$PEER_PORT │║"
            echo "║  └─────────┘       └──────────┘       └─────────┘║"
            echo "║                                                  ║"
            echo "║  📋 本机访问对方: ssh $PEER_NAME                   ║"
            echo "║  📋 发给维持者的隧道命令:                          ║"
            echo "║     $TUNNEL_CMD"
            echo "║                                                  ║"
            echo "║  👉 维持者在 Windows 上:                           ║"
            echo "║     双击 tunnel-mesh.bat → [1]导入 → 粘贴命令     ║"
            echo "╚══════════════════════════════════════════════════╝"
        fi

        CONFIG=$(config_json_get "import json,sys;d=json.load(sys.stdin);d['contracts'].append({'id':'${HOSTNAME}→${PEER_NAME}','master':'$HOSTNAME','servant':'$PEER_NAME','type':'reverse','tunnel_port':$TUNNEL_PORT,'tunnel_cmd':'$TUNNEL_CMD','maintainer':'${MAINTAINER}','status':'active','created':'$(date -Iseconds)'});print(json.dumps(d,indent=2))")
        config_save "$CONFIG"
    fi
}
