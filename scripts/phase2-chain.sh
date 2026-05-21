#!/bin/bash
# phase2-chain.sh - 探路链：帮用户发现 A→B 的内部连接链

do_chain_discovery() {
    local MASTER=$1 SERVANT=$2

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  探路链：$MASTER → ... → $SERVANT                   ║"
    echo "║  一步步找出中间的连接路径                         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    local current="$MASTER"
    local chain="$MASTER"
    local depth=0

    while true; do
        depth=$((depth+1))
        if [ $depth -gt 10 ]; then echo "⚠ 太深了，停止"; return; fi

        echo "【第${depth}步】当前节点: $current"
        
        # 检测当前节点能否连到目标
        local sip="" sport=""
        if [ "$current" = "$HOSTNAME" ]; then
            sip="$SIP"; sport="$SPORT"
        else
            local info=$(config_json "import json,sys;d=json.load(sys.stdin);s=d['servers']['$SERVANT'];print(s['ip'],s.get('port',22))" 2>/dev/null)
            read sip sport <<< "$info"
        fi

        echo "  $current 能直接连到 $SERVANT ($sip:$sport) 吗？"
        
        local reachable=0
        if [ "$current" = "$HOSTNAME" ]; then
            tcp_reachable "$sip" "$sport" && reachable=1
        fi

        if [ $reachable -eq 1 ]; then
            echo "  ✓ 可达！链完成"
            chain="$chain → $SERVANT"
            break
        fi

        echo "  → 不通。$current 能连到哪些已知服务器？"
        echo ""
        server_list
        echo ""
        echo "  [N] 输入新服务器"
        echo "  [B] 桥接（维持者模式）"
        read -p "  选哪个: " NEXT

        case $NEXT in
            [bB])
                echo ""
                echo "  使用桥接维持者模式："
                echo "  谁同时连通 $current 和 $SERVANT？"
                read -p "  维持者名称: " BRIDGE
                [ -z "$BRIDGE" ] && { echo "取消"; return; }
                
                # 子边1: current→BRIDGE（反向，BRIDGE维持）
                plan_sub_edge "$current" "$BRIDGE" "reverse"
                # 子边2: BRIDGE→SERVANT（正向）
                plan_sub_edge "$BRIDGE" "$SERVANT" "forward"
                
                chain="$chain → $BRIDGE → $SERVANT"
                echo "  ✓ 链完成: $chain"
                return
                ;;
            [nN])
                echo ""; echo "  新服务器信息:"
                read -p "  名称: " NEW_NAME; [ -z "$NEW_NAME" ] && return
                read -p "  IP: " NEW_IP; [ -z "$NEW_IP" ] && return
                read -p "  端口 [22]: " NEW_PORT; NEW_PORT=${NEW_PORT:-22}
                read -p "  用户 [root]: " NEW_USER; NEW_USER=${NEW_USER:-root}
                server_add "$NEW_NAME" "$NEW_IP" "$NEW_PORT" "$NEW_USER" "" ""
                NEXT="$NEW_NAME"
                ;;&
        esac

        [ -z "$NEXT" ] && { echo "取消"; return; }

        # 判定 current→NEXT 这条子边
        echo ""
        echo "  判定子边: $current → $NEXT"
        plan_sub_edge "$current" "$NEXT"

        chain="$chain → $NEXT"
        current="$NEXT"
    done

    # 配目标边
    echo ""
    echo "════════════════════════════════════════"
    echo "  链: $chain"
    echo "════════════════════════════════════════"

    # 配 ProxyJump
    local jumps=$(echo "$chain" | sed 's/.*→ //' | tr ' →' ',' | sed 's/,$//')
    jumps=$(echo "$chain" | python3 -c "
s='$chain'.split(' → ')
jump_list=s[1:-1]
print(','.join(jump_list))
" 2>/dev/null)

    if [ -n "$jumps" ]; then
        mkdir -p ~/.ssh
        if ! grep -q "Host $SERVANT" ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $SERVANT (链: $chain)
Host $SERVANT
    HostName $SERVANT
    ProxyJump $jumps
    User ${SUSER:-root}
    StrictHostKeyChecking no
EOF
            chmod 600 ~/.ssh/config
        fi
        edge_add "$MASTER" "$SERVANT" "chain" "0" "" ""
        echo "  ✓ ssh $SERVANT → 自动: ssh -J $jumps $SERVANT"
    fi
}

# 判定并配置一条子边
plan_sub_edge() {
    local from=$1 to=$2 type=${3:-auto}

    echo "  检测: $from → $to"

    if [ "$from" = "$HOSTNAME" ]; then
        local tip=$(config_json "import json,sys;d=json.load(sys.stdin);s=d['servers'].get('$to',{});print(s.get('ip','?'),s.get('port',22),s.get('user','root'))" 2>/dev/null)
        read TO_IP TO_PORT TO_USER <<< "$tip"

        if tcp_reachable "$TO_IP" "$TO_PORT"; then
            echo "  ✓ 可达 → 正向直连"
            edge_add "$from" "$to" "forward" "0" "" ""
            
            mkdir -p ~/.ssh
            if ! grep -q "Host $to" ~/.ssh/config 2>/dev/null; then
                cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $to (直连)
Host $to
    HostName $TO_IP
    Port ${TO_PORT:-22}
    User ${TO_USER:-root}
    StrictHostKeyChecking no
EOF
                chmod 600 ~/.ssh/config
            fi
        else
            echo "  ✗ 不可达 → 反向隧道"
            local TUNNEL_PORT=$(port_allocate)
            local TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:${TO_IP}:${TO_PORT} ${USER}@${TUNNEL_IP} -p ${PORT}"

            mkdir -p ~/.ssh
            if ! grep -q "Host $to" ~/.ssh/config 2>/dev/null; then
                cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $to (反向隧道 :$TUNNEL_PORT)
Host $to
    HostName localhost
    Port $TUNNEL_PORT
    User ${TO_USER:-root}
    StrictHostKeyChecking no
    HostKeyAlias $to
EOF
                chmod 600 ~/.ssh/config
            fi
            edge_add "$from" "$to" "reverse" "$TUNNEL_PORT" "$TUNNEL_CMD" "2"
            echo ""
            echo "  📋 维持者命令: $TUNNEL_CMD"
        fi
    fi
}
