#!/bin/bash
# ========================================
set -o pipefail
# shellcheck disable=SC2034
# 网络检测 - TCP可达性 + 中间节点推荐
# ========================================

# 跨平台 timeout 封装（macOS 不内置 timeout 命令）
_timeout() {
    local sec=$1; shift
    if command -v timeout &>/dev/null; then
        timeout "$sec" "$@"
    elif command -v perl &>/dev/null; then
        perl -e 'alarm shift; exec @ARGV' "$sec" "$@"
    else
        # 最后手段：无超时直接执行
        "$@"
    fi
}

# TCP 检测：本机能连到 target_ip:port 吗？
tcp_reachable() {
    local ip=$1 port=${2:-22}
    _timeout 3 bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null && return 0
    return 1
}

# 两个节点之间的连通性判定
check_connectivity() {
    local a_ip=$1 a_port=$2 b_ip=$3 b_port=$4
    local a_to_b=0 b_to_a=0
    tcp_reachable "$b_ip" "$b_port" && a_to_b=1
    tcp_reachable "$a_ip" "$a_port" && b_to_a=1
    if [ $a_to_b -eq 1 ] && [ $b_to_a -eq 1 ]; then echo "both"
    elif [ $a_to_b -eq 1 ]; then echo "forward"
    elif [ $b_to_a -eq 1 ]; then echo "reverse"
    else echo "neither"
    fi
}

# 增强的中间节点推荐
# 参数: curr(当前节点名) servant(目标节点名)
# 从已知 servers 中找候选，TCP 探测后排序推荐
recommend_bridge() {
    local curr=$1 servant=$2
    local curr_ip curr_port servant_ip servant_port

    curr_ip=$(server_reachable_ip "$curr")
    curr_port=$(server_field "$curr" "port" "22")
    servant_ip=$(server_reachable_ip "$servant")
    servant_port=$(server_field "$servant" "port" "22")

    echo ""
    echo "  扫描已知服务器中可用的中间节点..."
    echo ""

    local candidates=()
    local scores=()

    # 遍历所有已知服务器
    local all_servers
    all_servers=$(python3 < "$CONFIG_FILE" -c "
import json,sys
d=json.load(sys.stdin)
for name in d.get('servers',{}):
    print(name)
" 2>/dev/null)

    while IFS= read -r name; do
        [ -z "$name" ] && continue
        [ "$name" = "$curr" ] && continue
        [ "$name" = "$servant" ] && continue

        local score=0
        local c_ip c_port
        c_ip=$(server_reachable_ip "$name")
        c_port=$(server_field "$name" "port" "22")

        # 本机能连到候选吗？
        if tcp_reachable "$c_ip" "$c_port"; then
            score=$((score + 2))
            echo "  $name ($c_ip:$c_port) — 本机可达 ✓"
        else
            echo "  $name ($c_ip:$c_port) — 本机不可达"
        fi

        # 候选能连到仆吗？（尝试从候选测，但通常需要 SSH 进去才行）
        # 只能做本地探测：
        # - 如果候选有公网 IP 且我们已经部署过公钥，尝试 ssh 探测
        if [ -n "$servant_ip" ] && [ "$servant_ip" != "?" ]; then
            # 真实探测需要 SSH 到候选执行，这里标记为"未知"
            echo "    → $servant: 未知（需登录 $name 验证）"
        fi

        candidates+=("$name")
        scores+=("$score")
    done <<< "$all_servers"

    echo ""
    echo "  推荐排序（★ 越多越可能适合做中间节点）:"
    echo ""

    # 按分数降序排列（同时交换 candidates 和 scores）
    local n=${#candidates[@]}
    local i j
    for ((i=0; i<n; i++)); do
        for ((j=i+1; j<n; j++)); do
            if [ "${scores[$j]}" -gt "${scores[$i]}" ]; then
                local tmp_c="${candidates[$i]}"; candidates[$i]="${candidates[$j]}"; candidates[$j]="$tmp_c"
                local tmp_s="${scores[$i]}"; scores[$i]="${scores[$j]}"; scores[$j]="$tmp_s"
            fi
        done
    done

    for ((i=0; i<n; i++)); do
        local stars=""
        [ "${scores[$i]}" -ge 2 ] && stars="★★"
        [ "${scores[$i]}" -ge 1 ] && stars="★"
        echo "  [$((i+1))] ${candidates[$i]} $stars (分:${scores[$i]})"
    done

    echo ""
    echo "  [0] 手动输入其他服务器"
    echo ""
}

# DEPRECATED: 旧接口兼容，仅从本机测可达性，不能反映候选节点的真实连通性。
# 新代码请使用 recommend_bridge()。
find_bridge() {
    local a_ip=$1 a_port=$2 b_ip=$3 b_port=$4

    local candidates
    candidates=$(python3 < "$CONFIG_FILE" "$JSON_OP" find_bridge "$a_ip" "$a_port" "$b_ip" "$b_port" 2>/dev/null)

    while IFS=' ' read -r name ip port; do
        [ -z "$name" ] && continue
        local can_a=0 can_b=0
        tcp_reachable "$a_ip" "$a_port" && can_a=1
        tcp_reachable "$b_ip" "$b_port" && can_b=1
        if [ $can_a -eq 1 ] && [ $can_b -eq 1 ]; then
            echo "$name"
            return
        fi
    done <<< "$candidates"

    echo ""
}
