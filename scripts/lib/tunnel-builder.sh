#!/bin/bash
# ========================================
set -o pipefail
# 隧道命令构建库 - ssh -L / ssh -R 命令生成 + 配置输出
# 统一端口 P，结果都是：上一跳的 localhost:P → 下一跳:22
# 所有函数支持显式 IP/port/user 覆写（中间节点不在 config.json 时使用）
# ========================================

# 从 config.json 提取服务器的可连 IP（优先公网）
server_reachable_ip() {
    local name=$1
    local info pub_ip ip
    info=$(config_get "servers.$name" 2>/dev/null)
    ip=$(echo "$info" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('ip',''))" 2>/dev/null)
    pub_ip=$(echo "$info" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('public_ip',''))" 2>/dev/null)
    if [ -n "$pub_ip" ] && [ "$pub_ip" != "None" ] && [ "$pub_ip" != "$ip" ]; then
        echo "$pub_ip"
    else
        echo "$ip"
    fi
}

server_field() {
    local name=$1 field=$2 default=${3:-}
    local info val
    info=$(config_get "servers.$name" 2>/dev/null)
    val=$(echo "$info" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('$field',''))" 2>/dev/null)
    echo "${val:-$default}"
}

# forward_tunnel: 上一跳运行 ssh -L P:下一跳_ip:22 user@下一跳_ip
# 效果：上一跳 localhost:P → 下一跳:22
# 可选覆写: next_ip next_port next_user（中间节点不在 config.json 时使用）
gen_forward_tunnel_cmd() {
    local prev=$1 next=$2 port=$3
    local next_ip=${4:-} next_port=${5:-} next_user=${6:-}
    [ -z "$next_ip" ] && next_ip=$(server_reachable_ip "$next")
    [ -z "$next_port" ] && next_port=$(server_field "$next" "port" "22")
    [ -z "$next_user" ] && next_user=$(server_field "$next" "user" "root")
    echo "ssh -L ${port}:${next_ip}:${next_port} ${next_user}@${next_ip} -p ${next_port}"
}

# reverse_tunnel: 下一跳运行 ssh -R P:localhost:22 user@上一跳_ip -p 上一跳_port
# 效果：上一跳 localhost:P → 下一跳:22
# 可选覆写: prev_ip prev_port prev_user（中间节点不在 config.json 时使用）
gen_reverse_tunnel_cmd() {
    local prev=$1 next=$2 port=$3
    local prev_ip=${4:-} prev_port=${5:-} prev_user=${6:-}
    [ -z "$prev_ip" ] && prev_ip=$(server_reachable_ip "$prev")
    [ -z "$prev_port" ] && prev_port=$(server_field "$prev" "port" "22")
    [ -z "$prev_user" ] && prev_user=$(server_field "$prev" "user" "root")
    echo "ssh -R ${port}:localhost:22 ${prev_user}@${prev_ip} -p ${prev_port}"
}

# ---- 链路健康检查 ----

# 全链路健康扫描（使用 CHAIN_*_IP/_PORT 显式数组，不查 config.json）
health_check_chain() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  链路健康检查"
    echo "════════════════════════════════════════"
    echo ""

    if [ "$CHAIN_COUNT" -eq 0 ]; then
        echo "  当前无链路数据。请先执行递归建边。"
        return 1
    fi

    local i all_ok=1
    for ((i=0; i<CHAIN_COUNT; i++)); do
        local from="${CHAIN_FROM[$i]}"
        local to="${CHAIN_TO[$i]}"
        local typ="${CHAIN_TYPE[$i]}"
        local cmd="${CHAIN_CMD[$i]}"
        local port="$CHAIN_PORT"
        local to_ip="${CHAIN_TO_IP[$i]}"
        local to_port="${CHAIN_TO_PORT[$i]}"

        printf "  [%d/%d] %s → %s (%s) ... " $((i+1)) $CHAIN_COUNT "$from" "$to" "$typ"

        if [ "$typ" = "forward_direct" ]; then
            [ -z "$to_ip" ] && to_ip=$(server_reachable_ip "$to")
            [ -z "$to_port" ] && to_port=$(server_field "$to" "port" "22")
            if timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
                -p "$to_port" root@"$to_ip" "echo OK" 2>/dev/null | grep -q OK; then
                echo "✓ 连通"
            else
                echo "✗ 失败 — $to_ip:$to_port 不可达"
                all_ok=0
            fi
        else
            if timeout 5 bash -c "echo >/dev/tcp/localhost/${port}" 2>/dev/null; then
                echo "✓ 端口 $port 在监听"
            else
                echo "✗ 失败 — localhost:$port 端口不通（隧道进程可能挂了）"
                all_ok=0
            fi
        fi
    done

    echo ""
    if [ "$all_ok" -eq 1 ]; then
        echo "  ✓ 全链路健康"
    else
        echo "  ✗ 存在断点，请检查对应跳的隧道进程"
        echo ""
        echo "  修复提示:"
        for ((i=0; i<CHAIN_COUNT; i++)); do
            local typ="${CHAIN_TYPE[$i]}"
            local cmd="${CHAIN_CMD[$i]}"
            if [ -n "$cmd" ]; then
                local runner
                case "$typ" in
                    forward_tunnel) runner="${CHAIN_FROM[$i]}" ;;
                    reverse_tunnel) runner="${CHAIN_TO[$i]}" ;;
                esac
                echo "  跳$((i+1)): 在 $runner 上运行: $cmd"
            fi
        done
    fi

    return $all_ok
}
