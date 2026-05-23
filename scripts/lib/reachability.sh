#!/bin/bash
# ========================================
set -o pipefail
# 网络可达探测 — 从本机向所有已知服务器发起 TCP 探测
# 输出 JSON 报告供 --cmd reachability 使用
# ========================================

# 生成 reachability 报告 JSON
do_reachability() {
    local from_name="${HOSTNAME:-$(hostname)}"
    local from_ip
    from_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

    # 读取所有服务器
    local servers_json
    servers_json=$(python3 -c "
import json,sys
d=json.load(sys.stdin)
for name, info in d.get('servers',{}).items():
    print(json.dumps({'name':name,'ip':info.get('ip','?'),'port':info.get('port',22)}))
" < "$CONFIG_FILE" 2>/dev/null)

    echo "{"
    echo "  \"from\": \"$from_name\","
    echo "  \"from_ip\": \"$from_ip\","
    echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\","
    echo "  \"results\": ["

    local first=1
    while IFS= read -r server; do
        [ -z "$server" ] && continue
        local name ip port
        name=$(echo "$server" | python3 -c "import json,sys;print(json.load(sys.stdin)['name'])")
        ip=$(echo "$server" | python3 -c "import json,sys;print(json.load(sys.stdin)['ip'])")
        port=$(echo "$server" | python3 -c "import json,sys;print(json.load(sys.stdin)['port'])")

        # 跳过自己
        [ "$name" = "$from_name" ] && continue

        # TCP 探测 + 延迟测量
        local reachable=false error="" latency_ms=0
        if [ "$ip" != "?" ] && [ -n "$ip" ]; then
            local start_ns end_ns
            start_ns=$(date +%s%N 2>/dev/null || echo 0)
            if _timeout 3 bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null; then
                reachable=true
                end_ns=$(date +%s%N 2>/dev/null || echo 0)
                if [ "$start_ns" != "0" ] && [ "$end_ns" != "0" ]; then
                    latency_ms=$(( (end_ns - start_ns) / 1000000 ))
                fi
            else
                error="timeout or connection refused"
            fi
        else
            error="unknown IP"
        fi

        [ $first -eq 0 ] && echo ","
        first=0

        local comma=""
        echo -n "    {\"target\": \"$name\", \"ip\": \"$ip\", \"port\": $port, \"reachable\": $reachable, \"latency_ms\": $latency_ms"
        if [ -n "$error" ]; then
            echo -n ", \"error\": \"$error\""
        fi
        echo -n "}"
    done <<< "$servers_json"

    echo ""
    echo "  ]"
    echo "}"
}

# 部署指南：读取合并报告，生成每台机器的部署指令
do_deploy_guide() {
    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # --cmd 模式：直接传文件参数
    if [ $# -ge 1 ]; then
        python3 "$lib_dir/_reachability.py" deploy-guide "$@"
        return $?
    fi
    # 交互模式：粘贴合并报告 JSON
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  按机器聚合部署指南                               ║"
    echo "║  粘贴 --cmd reachability-merge 的 JSON 输出       ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "──────────────────────────────────────"
    echo "  粘贴合并报告 JSON（Ctrl+D 回车）"
    echo "──────────────────────────────────────"

    local json_input
    json_input=$(cat)

    if ! echo "$json_input" | python3 -c "import json,sys;d=json.load(sys.stdin);d['edges']" 2>/dev/null; then
        echo "  ❌ 无效的合并报告"
        return 1
    fi

    echo "$json_input" | python3 "$lib_dir/_reachability.py" deploy-guide
}
