#!/bin/bash
# phase2-edge.sh - 边规划：交互式构建单条边

do_edge_plan() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  边规划 — 构建一条主→仆连接                       ║"
    echo "║  你告诉我谁连谁，我检测网络并给出方案              ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    # Step 1: 主是谁？
    echo "【第1步】谁是「主」（发起连接的一方）？"
    echo "  当前本机是: $HOSTNAME"
    echo "  [1] 就是本机 ($HOSTNAME)"
    echo "  [2] 其他服务器"
    read -p "  选择 [1]: " MC; MC=${MC:-1}
    if [ "$MC" = "1" ]; then
        MASTER="$HOSTNAME"
        MASTER_IP="$IP"; MASTER_PORT="$PORT"; MASTER_USER="$USER"
    else
        read -p "  主服务器名称: " MASTER
        server_exists "$MASTER" || { echo "  ❌ $MASTER 不在已知列表中"; return; }
    fi

    # Step 2: 仆是谁？
    echo ""
    echo "【第2步】谁是「仆」（被连接的一方）？"
    echo "  已知服务器:"
    server_list
    echo ""
    read -p "  仆服务器名称: " SERVANT

    if server_exists "$SERVANT"; then
        # 从图里取
        SI=$(config_json "import json,sys;d=json.load(sys.stdin);s=d['servers']['$SERVANT'];print(s['ip'],s.get('port',22),s.get('user','root'),s.get('public_ip',''))" 2>/dev/null)
        read SIP SPORT SUSER SPUBIP <<< "$SI"
        echo "  ✓ 已知: $SERVANT ($SIP:$SPORT)"
    else
        echo "  新服务器，请输入信息:"
        read -p "  IP地址: " SIP
        read -p "  SSH端口 [22]: " SPORT; SPORT=${SPORT:-22}
        read -p "  用户名 [root]: " SUSER; SUSER=${SUSER:-root}
        read -p "  有公网IP吗？[无]: " SPUBIP
        server_add "$SERVANT" "$SIP" "$SPORT" "$SUSER" "" ""
    fi

    # Step 3: 检测连通性
    echo ""
    echo "【第3步】检测网络连通性..."
    echo "  测试: $MASTER → $SERVANT ($SIP:$SPORT)"

    local reachable=0
    if [ "$MASTER" = "$HOSTNAME" ]; then
        tcp_reachable "$SIP" "$SPORT" && reachable=1
    fi

    # 也检测反向
    echo "  对方能连到你吗？"
    echo "    [1] 能    [2] 不能    [3] 不知道"
    read -p "  选择 [3]: " REV; REV=${REV:-3}

    # Step 4: 判定边类型
    echo ""
    echo "【第4步】判定连接方式..."

    if [ $reachable -eq 1 ] && [ "$REV" = "1" ]; then
        EDGE_TYPE="forward"
        echo "  ✓ 双向可达 → 默认正向直连"
    elif [ $reachable -eq 1 ]; then
        EDGE_TYPE="forward"
        echo "  ✓ 你能直接连到对方 → 正向直连"
    elif [ "$REV" = "1" ]; then
        EDGE_TYPE="reverse"
        echo "  → 对方能连你，你不能连对方 → 反向隧道"
    else
        # ── 双方不能互连 → 搜索整个图找路径 ──
        echo ""
        echo "  双方不能直连。在图里搜索路径..."

        # 从图中找 multi-hop 路径
        local path_json=$(graph_path "$MASTER" "$SERVANT")
        local path_ok=$(echo "$path_json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('ok',False))" 2>/dev/null)

        if [ "$path_ok" = "True" ]; then
            local path_str hops nodes
            path_str=$(echo "$path_json" | python3 -c "import json,sys;print(' → '.join(json.load(sys.stdin)['path']))" 2>/dev/null)
            hops=$(echo "$path_json" | python3 -c "import json,sys;print(json.load(sys.stdin)['hops'])" 2>/dev/null)
            nodes=$(echo "$path_json" | python3 -c "import json,sys;p=json.load(sys.stdin)['path'];print(' '.join(p[1:-1]))" 2>/dev/null)

            echo "  ✓ 找到路径: $path_str ($hops 跳)"

            if [ "$hops" -eq 1 ]; then
                # 直连 → forward
                EDGE_TYPE="forward"
            else
                # 多跳：检查每条中间边是否已存在
                echo ""
                echo "  这条路径需要以下中间边:"
                local missing=0
                local prev="$MASTER"
                for node in $nodes "$SERVANT"; do
                    local eid="${prev}→${node}"
                    local exists=$(config_json "import json,sys;d=json.load(sys.stdin);print(len([e for e in d.get('edges',[]) if e.get('id','')=='$eid']))" 2>/dev/null)
                    if [ "0" = "$exists" ]; then
                        echo "    ✗ $eid (未配置)"
                        missing=1
                    else
                        echo "    ✓ $eid"
                    fi
                    prev="$node"
                done

                if [ $missing -eq 1 ]; then
                    echo ""
                    echo "  部分中间边未配置。你需要先在对应的中间服务器上"
                    echo "  运行边规划，配置好每一条中间边。"
                    echo ""
                    echo "  已配置的边可以直接用 ProxyJump。"
                    server_list
                    return
                else
                    # 全部中间边已配好 → 直接 ProxyJump
                    local jumps=$(echo "$nodes" | tr ' ' ',')
                    mkdir -p ~/.ssh
                    if ! grep -q "Host $SERVANT" ~/.ssh/config 2>/dev/null; then
                        cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $SERVANT (多跳 ProxyJump: $jumps)
Host $SERVANT
    HostName $SERVANT
    ProxyJump $jumps
    User ${SUSER:-root}
    StrictHostKeyChecking no
EOF
                        chmod 600 ~/.ssh/config
                    fi
                    edge_add "$MASTER" "$SERVANT" "proxyjump" "0" "" ""
                    echo ""
                    echo "  ✓ 多跳连接已配置: ssh $SERVANT"
                    echo "  路径: $path_str"
                    return
                fi
            fi
        fi

        # 图里也没有 → 问是否有桥接
        echo "  ✗ 图里也没有路径"
        echo ""
        echo "  有没有一台维持者能同时连你和 $SERVANT？"
        echo "    [1] 有（如 Windows）→ 我来配反向隧道"
        echo "    [2] 没有 → 需要先配中间连接"
        read -p "  选择: " HAS_BRIDGE; HAS_BRIDGE=${HAS_BRIDGE:-1}

        if [ "$HAS_BRIDGE" = "1" ]; then
            EDGE_TYPE="reverse"
            echo "  → 使用反向隧道 + 外部维持者"
        else
            echo "  你需要先配好中间节点的连接，再回来规划这条边"
            server_list
            return
        fi
    fi

    # Step 5: 如果是 reverse → 问维持者
    if [ "$EDGE_TYPE" = "reverse" ]; then
        echo ""
        echo "【第5步】谁维持反向隧道？"
        echo "  [1] 仆自己维持（仆能连主）"
        echo "  [2] 外部机器（如 Windows 能同时连双方）"
        read -p "  选择 [2]: " MAINTAINER; MAINTAINER=${MAINTAINER:-2}

        TUNNEL_PORT=$(port_allocate)
        read -p "  隧道端口 [$TUNNEL_PORT]: " TP; TUNNEL_PORT=${TP:-$TUNNEL_PORT}

        if [ "$MAINTAINER" = "2" ]; then
            local TARGET_IP="$SIP"
            [ -n "$SPUBIP" ] && TARGET_IP="$SPUBIP"
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:${TARGET_IP}:${SPORT} ${USER}@${TUNNEL_IP} -p ${PORT}"

            echo ""
            echo "╔══════════════════════════════════════════════════╗"
            echo "║  边: $MASTER → $SERVANT (反向隧道)                ║"
            echo "╠══════════════════════════════════════════════════╣"
            echo "║  本机 ssh $SERVANT                                ║"
            echo "║  发给维持者的隧道命令:                            ║"
            echo "║  $TUNNEL_CMD"
            echo "╚══════════════════════════════════════════════════╝"

            # 写本机 SSH config
            mkdir -p ~/.ssh
            if ! grep -q "Host $SERVANT" ~/.ssh/config 2>/dev/null; then
                cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $SERVANT (反向隧道 :$TUNNEL_PORT)
Host $SERVANT
    HostName localhost
    Port $TUNNEL_PORT
    User ${SUSER:-root}
    StrictHostKeyChecking no
    HostKeyAlias $SERVANT
EOF
                chmod 600 ~/.ssh/config
            fi
        else
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:localhost:${PORT} ${SUSER}@${SIP} -p ${SPORT}"
            echo "  维持命令: $TUNNEL_CMD"
        fi

        # 保存边
        edge_add "$MASTER" "$SERVANT" "reverse" "$TUNNEL_PORT" "$TUNNEL_CMD" "$MAINTAINER"
    else
        # 正向
        mkdir -p ~/.ssh
        if ! grep -q "Host $SERVANT" ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $SERVANT (直连)
Host $SERVANT
    HostName $SIP
    Port ${SPORT:-22}
    User ${SUSER:-root}
    StrictHostKeyChecking no
EOF
            chmod 600 ~/.ssh/config
        fi
        edge_add "$MASTER" "$SERVANT" "forward" "0" "" ""
        echo ""
        echo "  ✓ 正向连接已配置: ssh $SERVANT"
        timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SERVANT" "hostname" 2>/dev/null && echo "  ✓ 连接测试成功"
    fi
}
