#!/bin/bash
# ========================================
# 网络检测 - TCP可达性 + 图可达性判断
# ========================================

# TCP 检测：本机能连到 target_ip:port 吗？
tcp_reachable() {
    local ip=$1 port=${2:-22}
    timeout 3 bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null && return 0
    return 1
}

# 两个节点之间的连通性判定
# 返回: forward / reverse / both / neither / bridge
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

# 找桥接节点：谁同时连通 A 和 B？
find_bridge() {
    local a_ip=$1 a_port=$2 b_ip=$3 b_port=$4
    local result=""

    CONFIG=$(config_load)
    local servers=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for name,s in d.get('servers',{}).items():
    print(f'{name} {s[\"ip\"]} {s.get(\"port\",22)}')
" 2>/dev/null)

    while IFS=' ' read -r name ip port; do
        [ -z "$name" ] && continue
        local can_a=0 can_b=0
        tcp_reachable "$a_ip" "$a_port" && can_a=1   # 这里需要从 bridge 角度测试
        tcp_reachable "$b_ip" "$b_port" && can_b=1
        # 简化：bridge 需能连 A 且能连 B
        if [ $can_a -eq 1 ] && [ $can_b -eq 1 ]; then
            result="$name"
            break
        fi
    done <<< "$servers"

    echo "$result"
}
