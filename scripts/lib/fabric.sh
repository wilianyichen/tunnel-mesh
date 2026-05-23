#!/bin/bash
# ========================================
set -o pipefail
# Fabric 管理 — 物理连接层的 shell 封装
# 所有命令管道式调用 _fabric_op.py
# ========================================

FABRIC_PATH="$HOME/.tunnel-mesh/fabric.json"

# LIB_DIR 必须在 source 本文件之前已定义（由 config.sh 设置）
if [ -z "${LIB_DIR:-}" ]; then
    echo "❌ fabric.sh: LIB_DIR 未定义，请确保 config.sh 先于 fabric.sh 被 source" >&2
    return 1 2>/dev/null || exit 1
fi
FABRIC_OP="$LIB_DIR/_fabric_op.py"

if [ ! -f "$FABRIC_OP" ]; then
    echo "❌ fabric.sh: 找不到 $FABRIC_OP" >&2
    return 1 2>/dev/null || exit 1
fi

fabric_init() {
    if [ ! -f "$FABRIC_PATH" ]; then
        mkdir -p "$(dirname "$FABRIC_PATH")"
        echo '{"fabrics":{}}' > "$FABRIC_PATH"
    fi
}

# fabric_create <logical_edge> <port> → 输出 fabric_id
fabric_create() {
    local edge=$1 port=${2:-0}
    local fid
    fid="fab-$(date +%Y%m%d%H%M%S)-$$"
    _NOW="$(date -Iseconds)"; export _NOW
    python3 "$FABRIC_OP" fabric_create "$fid" "$edge" "$port" > /dev/null || { echo "❌ fabric_create 失败" >&2; return 1; }
    echo "$fid"
}

# fabric_add_hop <fabric_id> <seq> <from> <to> <type> <port> <cmd> <runner> <target_ip> <target_port>
fabric_add_hop() {
    local fid=$1 seq=$2 from=$3 to=$4 typ=$5 port=$6 cmd=$7 runner=$8 tip=$9 tp=${10:-22}
    python3 "$FABRIC_OP" fabric_add_hop "$fid" "$seq" "$from" "$to" "$typ" "$port" "$cmd" "$runner" "$tip" "$tp" > /dev/null || { echo "❌ fabric_add_hop 失败" >&2; return 1; }
}

# fabric_add_transit <fabric_id> <name> <ip> <port> <user> <pubkey>
fabric_add_transit() {
    local fid=$1 name=$2 ip=$3 port=$4 user=$5 pubkey=$6
    python3 "$FABRIC_OP" fabric_add_transit "$fid" "$name" "$ip" "${port:-22}" "${user:-root}" "${pubkey:-}" > /dev/null || { echo "❌ fabric_add_transit 失败" >&2; return 1; }
}

# fabric_add_maintainer <fabric_id> <node> <role> <cmd> <persist>
fabric_add_maintainer() {
    local fid=$1 node=$2 role=$3 cmd=$4 persist=$5
    python3 "$FABRIC_OP" fabric_add_maintainer "$fid" "$node" "$role" "$cmd" "${persist:-manual}" > /dev/null || { echo "❌ fabric_add_maintainer 失败" >&2; return 1; }
}

# fabric_add_external <fabric_id> <name> <cmd> <platform>
fabric_add_external() {
    local fid=$1 name=$2 cmd=$3 platform=$4
    python3 "$FABRIC_OP" fabric_add_external "$fid" "$name" "$cmd" "${platform:-linux}" > /dev/null || { echo "❌ fabric_add_external 失败" >&2; return 1; }
}

fabric_get() {
    python3 "$FABRIC_OP" fabric_get "$1"
}

fabric_list() {
    python3 "$FABRIC_OP" fabric_list
}

fabric_remove() {
    python3 "$FABRIC_OP" fabric_remove "$1"
}

fabric_cmds() {
    python3 "$FABRIC_OP" fabric_cmds
}

fabric_health() {
    python3 "$FABRIC_OP" fabric_health "${1:-}"
}

fabric_viz() {
    python3 "$FABRIC_OP" fabric_viz
}
