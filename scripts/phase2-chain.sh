#!/bin/bash
# phase2-chain.sh - 递归探路链

do_chain_discovery() {
    local MASTER=$1 SERVANT=$2

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  探路链：$MASTER → ... → $SERVANT                   ║"
    echo "║  递归构建连接链                                   ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    # 统一端口
    echo -n "统一端口 [4001]: "; read PORT; PORT=${PORT:-4001}

    # 清空链
    HOPS=()
    HOP_DIRS=()

    # 递归
    discover_hop "$MASTER" "$SERVANT" "$PORT" 1

    # ── 链完成，生成全部输出 ──
    generate_chain_output "$MASTER" "$SERVANT" "$PORT"
}

# 递归：从当前节点到目标
discover_hop() {
    local current=$1 target=$2 port=$3 depth=$4

    [ $depth -gt 10 ] && { echo "⚠ 太深"; return 1; }

    echo "════════════════════════════════════════"
    echo "  第${depth}步: $current → $target ?"
    echo "════════════════════════════════════════"

    # 检测可达性
    if [ "$current" = "$HOSTNAME" ]; then
        local t_ip=$(config_json "import json,sys;d=json.load(sys.stdin);s=d['servers'].get('$target',{});print(s.get('ip','?'))" 2>/dev/null)
        local t_port=$(config_json "import json,sys;d=json.load(sys.stdin);s=d['servers'].get('$target',{});print(s.get('port',22))" 2>/dev/null)
        tcp_reachable "$t_ip" "$t_port" && CAN=1 || CAN=0
    else
        echo "  不在本机，$current 能直连 $target 吗？"
        read -p "  [1]能 [2]不能: " CAN; CAN=${CAN:-2}
        [ "$CAN" = "1" ] && CAN=1 || CAN=0
    fi

    if [ $CAN -eq 1 ]; then
        echo "  ✓ 可达 → 正向"
        HOPS+=("$current→$target:forward:$port")
        HOP_DIRS+=("F")
        return 0
    fi

    # 不可达 → 加中继
    echo "  ✗ 不可达。加一个中继服务器。"
    echo "  已知服务器:"
    server_list
    echo "  [N] 新服务器"
    read -p "  中继名称: " RELAY
    [ -z "$RELAY" ] && { echo "取消"; return 1; }

    if [ "$RELAY" = "N" ] || [ "$RELAY" = "n" ]; then
        read -p "  名称: " RELAY
        read -p "  IP: " R_IP; read -p "  端口 [22]: " R_PORT; R_PORT=${R_PORT:-22}
        read -p "  用户 [root]: " R_USER; R_USER=${R_USER:-root}
        server_add "$RELAY" "$R_IP" "$R_PORT" "$R_USER" "" ""
    fi

    # 选方向
    echo ""
    echo "  $current 和 $RELAY 谁连谁？"
    echo "    [1] $current 连 $RELAY（正向）"
    echo "    [2] $RELAY 连 $current（反向隧道）"
    read -p "  选择: " DIR; DIR=${DIR:-1}

    if [ "$DIR" = "1" ]; then
        echo "  → 正向: $current → $RELAY"
        HOPS+=("$current→$RELAY:forward:$port")
        HOP_DIRS+=("F")
    else
        echo "  → 反向隧道: $RELAY → $current"
        HOPS+=("$current→$RELAY:reverse:$port")
        HOP_DIRS+=("R")
    fi

    # 递归下一跳
    discover_hop "$RELAY" "$target" "$port" $((depth+1))
}

# ── 从链生成全部输出 ──
generate_chain_output() {
    local master=$1 servant=$2 port=$3

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  链: $master → ... → $servant                     ║"
    echo "╠══════════════════════════════════════════════════╣"

    # 打印链
    local chain_display="$master"
    local prev="$master"
    local tunnels=()
    local keys="" configs="" services="" verify=""

    local i=0
    for hop in "${HOPS[@]}"; do
        IFS=':' read -r edge type hport <<< "$hop"
        IFS='→' read -r from to <<< "$edge"
        
        if [ "$type" = "reverse" ]; then symbol="←─R─"; else symbol="──F─→"; fi
        chain_display="$chain_display $symbol $to"
    done

    echo "║  $chain_display"
    echo "║  端口: $port"
    echo "╚══════════════════════════════════════════════════╝"

    # ── 生成各服务器配置 ──
    echo ""
    echo "════════════════════════════════════════"
    echo "  各服务器配置"
    echo "════════════════════════════════════════"

    local prev="$master"
    for hop in "${HOPS[@]}"; do
        IFS=':' read -r edge type hport <<< "$hop"
        IFS='→' read -r from to <<< "$edge"

        if [ "$type" = "reverse" ]; then
            # 反向：to 发起隧道到 from
            echo ""
            echo "── $to 上 ────────────────────────────"
            echo "隧道命令: ssh -R ${port}:localhost:${port} $(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$from',{}).get('user','root'))" 2>/dev/null)@$(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$from',{}).get('ip','?'))" 2>/dev/null) -N"
            echo "SSH config: Host $from → localhost:$port"
            echo "开机自启: 需要"
            tunnels+=("$to→$from:reverse:$port")
        else
            # 正向
            echo ""
            echo "── $from 上 ────────────────────────────"
            local to_ip=$(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$to',{}).get('ip','?'))" 2>/dev/null)
            local to_user=$(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$to',{}).get('user','root'))" 2>/dev/null)
            
            # 判断是否是最后一跳（到目标）
            local is_last=0
            local last_hop="${HOPS[${#HOPS[@]}-1]}"
            if [ "$hop" = "$last_hop" ]; then is_last=1; fi

            if [ $is_last -eq 1 ]; then
                echo "SSH config: Host $to → $to_ip:$port  (最后一跳，$port→目标22)"
                echo "隧道命令: ssh -L ${port}:localhost:22 ${to_user}@${to_ip} -N"
                echo "开机自启: 需要"
                tunnels+=("$from→$to:forward-last:$port")
            else
                echo "SSH config: Host $to → $(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$to',{}).get('ip','?'))" 2>/dev/null) (正向)"
                echo "隧道命令: ssh -L ${port}:localhost:${port} ${to_user}@${to_ip} -N"
                echo "开机自启: 需要"
                tunnels+=("$from→$to:forward-mid:$port")
            fi
        fi
        prev="$to"
    done

    # ── 密钥部署清单 ──
    echo ""
    echo "════════════════════════════════════════"
    echo "  密钥部署清单"
    echo "════════════════════════════════════════"
    echo ""
    
    for t in "${tunnels[@]}"; do
        IFS=':' read -r te type tp <<< "$t"
        IFS='→' read -r tfrom tto <<< "$te"
        if [ "$type" = "reverse" ]; then
            echo "  $tto 的公钥 → $tfrom  (隧道维持)"
        else
            echo "  $tfrom 的公钥 → $tto  (隧道维持)"
        fi
    done
    echo "  $master 的公钥 → $servant  (端到端认证)"

    # ── 主端点配置 ──
    echo ""
    echo "════════════════════════════════════════"
    echo "  $master 上（主·端点）"
    echo "════════════════════════════════════════"
    echo ""
    echo "SSH config:"
    echo "  Host $servant"
    echo "      HostName localhost"
    echo "      Port $port"
    local s_user=$(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$servant',{}).get('user','root'))" 2>/dev/null)
    echo "      User $s_user"
    echo ""
    echo "验证: ssh $servant hostname"

    # ── 一键配置卡片 ──
    echo ""
    echo "════════════════════════════════════════"
    echo "  一键配置卡片（复制到对应服务器执行）"
    echo "════════════════════════════════════════"
    echo ""
    echo "===CHAIN-CONFIG==="
    echo "SERVER=$master"
    echo "ROLE=master-endpoint"
    echo "SERVANT=$servant"
    echo "PORT=$port"
    echo "SERVANT_USER=$s_user"
    echo "SSH_NAME=$servant"
    echo "===END==="
    echo ""
    echo "# 在 $master 上粘贴以下命令即可完成配置:"
    echo "cat >> ~/.ssh/config << 'EOF'"
    echo "Host $servant"
    echo "    HostName localhost"
    echo "    Port $port"
    echo "    User $s_user"
    echo "EOF"
    echo "echo '✓ 配置完成。验证: ssh $servant hostname'"

    # ── 为每个中继节点生成开机自启服务 ──
    echo ""
    echo "════════════════════════════════════════"
    echo "  开机自启配置"
    echo "════════════════════════════════════════"
    echo ""
    
    local last_hop="${HOPS[${#HOPS[@]}-1]}"
    IFS=':' read -r le lt lp <<< "$last_hop"
    IFS='→' read -r lfrom lto <<< "$le"

    # 最后一跳：在 lfrom 上配
    local lto_ip=$(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$lto',{}).get('ip','?'))" 2>/dev/null)
    local lto_user=$(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$lto',{}).get('user','root'))" 2>/dev/null)
    
    echo "$lfrom (systemd service):"
    echo "  [Unit]"
    echo "  Description=Tunnel $lfrom→$lto"
    echo "  [Service]"
    echo "  ExecStart=ssh -L ${port}:localhost:22 ${lto_user}@${lto_ip} -N -o ServerAliveInterval=60"
    echo "  Restart=always"
    echo "  [Install]"
    echo "  WantedBy=multi-user.target"
    echo ""

    # 中间跳
    for ((i=0; i<${#HOPS[@]}-1; i++)); do
        local hop="${HOPS[$i]}"
        IFS=':' read -r he ht hp <<< "$hop"
        IFS='→' read -r hfrom hto <<< "$he"
        
        if [ "$ht" = "reverse" ]; then
            local hfrom_ip=$(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$hfrom',{}).get('ip','?'))" 2>/dev/null)
            local hfrom_user=$(config_json "import json,sys;d=json.load(sys.stdin);print(d['servers'].get('$hfrom',{}).get('user','root'))" 2>/dev/null)
            echo "$hto (systemd service):"
            echo "  ExecStart=ssh -R ${port}:localhost:${port} ${hfrom_user}@${hfrom_ip} -N -o ServerAliveInterval=60"
        fi
    done
}
