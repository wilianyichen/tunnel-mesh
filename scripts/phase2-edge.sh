#!/bin/bash
# phase2-edge.sh - 边规划：交互式构建单条边
set -o pipefail
# shellcheck disable=SC2034

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
        # 从图里取 — 安全：通过 config_get
        SINFO=$(config_get "servers.$SERVANT" 2>/dev/null)
        SIP=$(echo "$SINFO" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('ip','?'))" 2>/dev/null)
        SPORT=$(echo "$SINFO" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('port',22))" 2>/dev/null)
        SUSER=$(echo "$SINFO" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('user','root'))" 2>/dev/null)
        SPUBIP=$(echo "$SINFO" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('public_ip',''))" 2>/dev/null)
        echo "  ✓ 已知: $SERVANT ($SIP:$SPORT)"
    else
        echo "  新服务器，请选择输入方式:"
        echo "    [1] 手动输入"
        echo "    [P] 粘贴身份卡"
        read -p "  选择 [1]: " INPUT_MODE; INPUT_MODE=${INPUT_MODE:-1}

        if [ "$INPUT_MODE" = "P" ] || [ "$INPUT_MODE" = "p" ]; then
            echo ""
            echo "  粘贴身份卡（Ctrl+D 回车）:"
            echo "  ──────────────────────────"
            if ! parse_identity_card; then return; fi
            SERVANT="$_ID_NAME"
            SIP="$_ID_IP"
            SPORT="${_ID_PORT:-22}"
            SUSER="${_ID_USER:-root}"
            SPUBIP="$_ID_PUBLIC_IP"
            server_add "$SERVANT" "$SIP" "$SPORT" "$SUSER" "" "$_ID_PUBKEY"
            echo "  ✓ 已添加: $SERVANT ($SIP:$SPORT)"
        else
            read -p "  IP地址: " SIP
            read -p "  SSH端口 [22]: " SPORT; SPORT=${SPORT:-22}
            read -p "  用户名 [root]: " SUSER; SUSER=${SUSER:-root}
            read -p "  有公网IP吗？[无]: " SPUBIP
            server_add "$SERVANT" "$SIP" "$SPORT" "$SUSER" "" ""
        fi
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
        echo "    [3] 探路链 → 一步步找出中间路径"
        read -p "  选择: " HAS_BRIDGE; HAS_BRIDGE=${HAS_BRIDGE:-1}

        if [ "$HAS_BRIDGE" = "3" ]; then
            do_chain_discovery "$MASTER" "$SERVANT"
            return
        elif [ "$HAS_BRIDGE" = "1" ]; then
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

# 基于可达报告智能建边
do_reachability_edge() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  可达报告驱动建边                                 ║"
    echo "║  粘贴 --cmd reachability-merge 的 JSON 输出       ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "  如何获得合并报告:"
    echo "  1. 每台机器: tunnel-mesh.sh --cmd reachability > r.json"
    echo "  2. 本机:     tunnel-mesh.sh --cmd reachability-merge r*.json"
    echo "  3. 粘贴下面的 JSON 输出（Ctrl+D 回车）"
    echo ""
    echo "──────────────────────────────────────"
    echo "  粘贴合并报告 JSON"
    echo "──────────────────────────────────────"

    local json_input
    json_input=$(cat)

    # 验证是有效的 JSON 且包含 edges
    if ! echo "$json_input" | python3 -c "import json,sys;d=json.load(sys.stdin);d['edges']" 2>/dev/null; then
        echo "  ❌ 无效的合并报告，请确认粘贴完整"
        return 1
    fi

    # 解析并显示推荐
    echo ""
    echo "──────────────────────────────────────"
    echo "  推荐边分析"
    echo "──────────────────────────────────────"

    local analysis
    analysis=$(echo "$json_input" | python3 -c "
import json, sys
d = json.load(sys.stdin)
edges = d.get('edges', [])

fw = [e for e in edges if e['type'] == 'forward']
rv = [e for e in edges if e['type'] == 'reverse']
ch = [e for e in edges if e['type'] == 'chained']
un = [e for e in edges if e['type'] == 'unreachable']

seen = set()
def dedup(elist):
    result = []
    for e in elist:
        key = tuple(sorted([e['from'], e['to']]))
        if key not in seen:
            seen.add(key)
            result.append(e)
    return result

fw = dedup(fw)
rv = dedup(rv)
ch = dedup(ch)
un = dedup(un)

for e in fw:
    print(f\"  ✓ 正向 {e['from']} ⇄ {e['to']}\")
for e in rv:
    runner = e.get('tunnel_runner', '?')
    tun_on = e.get('tunnel_on', '?')
    print(f\"  → 反向 {e['from']} → {e['to']} | 维持者={runner} 在 {tun_on} 上开 ssh -R\")
for e in ch:
    print(f\"  🔗 链式 {e['from']} → {e['to']} | 桥={e.get('bridge','?')}\")
for e in un:
    print(f\"  ✗ 不可达 {e['from']} → {e['to']}\")
")

    echo "$analysis"

    read -p "  是否基于推荐创建边？[y/N]: " CHOICE
    if [ "$CHOICE" != "y" ] && [ "$CHOICE" != "Y" ]; then
        echo "  已跳过"
        return
    fi

    local created=0
    while IFS= read -r edge_json; do
        [ -z "$edge_json" ] && continue
        local etype efrom eto
        etype=$(echo "$edge_json" | python3 -c "import json,sys;print(json.load(sys.stdin)['type'])")
        efrom=$(echo "$edge_json" | python3 -c "import json,sys;print(json.load(sys.stdin)['from'])")
        eto=$(echo "$edge_json" | python3 -c "import json,sys;print(json.load(sys.stdin)['to'])")

        # 跳过已存在的边
        if echo "$CONFIG" | python3 -c "
import json,sys
edges=json.load(sys.stdin).get('edges',[])
for e in edges:
    if e.get('from')=='$efrom' and e.get('to')=='$eto':
        sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
            echo "  ⏭ 跳过（已存在）: $efrom → $eto"
            continue
        fi

        case "$etype" in
            forward)
                echo ""
                echo "  创建正向直连: $efrom → $eto"
                if ! server_exists "$eto"; then
                    local eto_ip eto_port
                    eto_ip=$(echo "$json_input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('nodes',{}).get('$eto',{}).get('ip','?'))")
                    eto_port=$(echo "$json_input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('nodes',{}).get('$eto',{}).get('port',22))")
                    read -p "  输入 $eto 的 IP [$eto_ip]: " INPUT_IP; INPUT_IP=${INPUT_IP:-$eto_ip}
                    read -p "  输入 $eto 的用户名 [root]: " INPUT_USER; INPUT_USER=${INPUT_USER:-root}
                    server_add "$eto" "$INPUT_IP" "${eto_port:-22}" "$INPUT_USER" "" ""
                fi

                if [ "$efrom" = "$HOSTNAME" ]; then
                    local s_ip s_port s_user
                    s_info=$(config_get "servers.$eto" 2>/dev/null)
                    s_ip=$(echo "$s_info" | python3 -c "import json,sys;print(json.load(sys.stdin).get('ip','?'))" 2>/dev/null)
                    s_port=$(echo "$s_info" | python3 -c "import json,sys;print(json.load(sys.stdin).get('port',22))" 2>/dev/null)
                    s_user=$(echo "$s_info" | python3 -c "import json,sys;print(json.load(sys.stdin).get('user','root'))" 2>/dev/null)
                    mkdir -p ~/.ssh
                    if ! grep -q "Host $eto" ~/.ssh/config 2>/dev/null; then
                        cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $eto (直连)
Host $eto
    HostName $s_ip
    Port ${s_port:-22}
    User ${s_user:-root}
    StrictHostKeyChecking no
EOF
                        chmod 600 ~/.ssh/config
                    fi
                fi
                edge_add "$efrom" "$eto" "forward" "0" "" ""
                created=$((created + 1))
                echo "  ✓ 正向边已创建"
                ;;
            reverse)
                local erunner etunnel_on
                erunner=$(echo "$edge_json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('tunnel_runner','?'))")
                etunnel_on=$(echo "$edge_json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('tunnel_on','?'))")
                local rport
                rport=$(port_allocate)
                echo ""
                echo "  创建反向隧道: $efrom → $eto"
                echo "  维持者: $erunner (运行 ssh -R $rport:localhost:22 $etunnel_on)"
                echo "  本机将通过 localhost:$rport 访问 $eto"

                mkdir -p ~/.ssh
                if ! grep -q "Host $eto" ~/.ssh/config 2>/dev/null; then
                    cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $eto (反向隧道 :$rport)
Host $eto
    HostName localhost
    Port $rport
    User root
    StrictHostKeyChecking no
    HostKeyAlias $eto
EOF
                    chmod 600 ~/.ssh/config
                fi
                edge_add "$efrom" "$eto" "reverse" "$rport" "ssh -R $rport:localhost:22 $etunnel_on" "$erunner"
                created=$((created + 1))
                echo "  ✓ 反向边已创建"
                echo "  ⚠ $erunner 需要运行: ssh -R $rport:localhost:22 $etunnel_on"
                ;;
            chained)
                local ebridge
                ebridge=$(echo "$edge_json" | python3 -c "import json,sys;print(json.load(sys.stdin).get('bridge','?'))")
                echo ""
                echo "  🔗 链式边: $efrom → $eto (桥: $ebridge)"
                echo "  链式边需要多跳，建议使用递归建边（Phase 2 [2]）"
                read -p "  是否现在创建（仅记录逻辑边）？[y/N]: " CHAIN_CHOICE
                if [ "$CHAIN_CHOICE" = "y" ] || [ "$CHAIN_CHOICE" = "Y" ]; then
                    edge_add "$efrom" "$eto" "chained" "0" "" ""
                    created=$((created + 1))
                    echo "  ✓ 链式边已记录（物理链路需手动配置）"
                fi
                ;;
            *)
                echo "  ⏭ 跳过: $efrom → $eto (类型=$etype)"
                ;;
        esac
    done < <(echo "$json_input" | python3 -c "
import json,sys
d=json.load(sys.stdin)
edges=d.get('edges',[])
seen=set()
for e in edges:
    key=tuple(sorted([e['from'],e['to']]))
    if key not in seen:
        seen.add(key)
        print(json.dumps(e))
")

    echo ""
    echo "──────────────────────────────────────"
    echo "  共创建 $created 条边"
}
