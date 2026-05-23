#!/bin/bash
# ========================================
set -o pipefail
# 配置管理 - config.json 读写 + 备份 + 端口
# 所有用户数据通过 argv 传入 Python，永不拼入代码字符串
# ========================================

CONFIG_DIR="$HOME/.tunnel-mesh"
CONFIG_FILE="$CONFIG_DIR/config.json"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_OP="$LIB_DIR/_json_op.py"

# ---- 输入校验 ----

# 节点名校验：不能含 / → " ' $ ` 空格，不能为空
validate_node_name() {
    local name="$1"
    [ -z "$name" ] && { echo "  ❌ 节点名不能为空" >&2; return 1; }
    if echo "$name" | grep -qE '[/→"'"'"'`$[:space:]]'; then
        echo "  ❌ 节点名不能包含 / → 空格 引号 \$ 等特殊字符" >&2
        return 1
    fi
    return 0
}

# IP 校验：空或合法 IPv4 格式
validate_ip() {
    local ip="$1"
    [ -z "$ip" ] && return 0  # 允许空（自动检测）
    if ! echo "$ip" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        echo "  ❌ IP 地址格式无效: $ip" >&2
        return 1
    fi
    return 0
}

config_load() {
    mkdir -p "$CONFIG_DIR"
    if [ -f "$CONFIG_FILE" ]; then cat "$CONFIG_FILE"; else echo '{"servers":{},"edges":[],"ports":{"used":[],"next":2201}}'; fi
}

config_save() {
    mkdir -p "$CONFIG_DIR"
    # 验证 JSON 合法性
    if ! echo "$1" | python3 -c "import json,sys;json.load(sys.stdin)" 2>/dev/null; then
        echo "❌ config.json 写入校验失败，尝试从备份恢复..."
        local latest_backup
        latest_backup=$(ls -t "$CONFIG_DIR"/config.json.bak.* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ] && [ -f "$latest_backup" ]; then
            cp "$latest_backup" "$CONFIG_FILE"
            echo "✓ 已从 $latest_backup 恢复"
        fi
        return 1
    fi
    # 获取文件锁（超时 10 秒，防并发写入损坏数据）
    exec 9>"${CONFIG_FILE}.lock"
    if ! flock -w 10 9 2>/dev/null; then
        echo "❌ 无法获取 config.json 锁（可能被其他进程占用）" >&2
        exec 9>&-
        return 1
    fi
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_DIR/config.json.bak.$(date +%Y%m%d-%H%M%S)"
    ls -t "$CONFIG_DIR"/config.json.bak.* 2>/dev/null | tail -n +6 | xargs -r rm -f 2>/dev/null
    echo "$1" > "$CONFIG_FILE"
    # 释放锁
    flock -u 9 2>/dev/null
    exec 9>&-
    CONFIG="$1"
    CONFIG_PORT_NEXT=$(echo "$1" | python3 "$JSON_OP" get ports.next 2>/dev/null || echo 2201)
}

# ---- 安全查询（无用户变量拼入代码） ----

config_get() {
    python3 "$JSON_OP" < "$CONFIG_FILE" get "$1"
}

# ---- 服务器操作 ----

server_exists() {
    python3 "$JSON_OP" < "$CONFIG_FILE" server_exists "$1" | grep -q True
}

server_add() {
    local name=$1 ip=$2 port=$3 user=$4 fp=$5 pubkey=$6
    _NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"; export _NOW
    CONFIG=$(python3 "$JSON_OP" < "$CONFIG_FILE" server_add "$name" "$ip" "${port:-22}" "${user:-root}" "${fp:-}" "${pubkey:-}") || { echo "❌ server_add 失败"; return 1; }
    config_save "$CONFIG"
}

server_list() {
    python3 "$JSON_OP" < "$CONFIG_FILE" server_list
}

# ---- 边操作 ----

edge_add() {
    local from=$1 to=$2 type=$3 port=$4 cmd=$5 maintainer=$6 fabric_id=$7 weight=$8
    local id="${from}→${to}"
    _NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"; export _NOW
    CONFIG=$(python3 "$JSON_OP" < "$CONFIG_FILE" edge_add "$id" "$from" "$to" "$type" "${port:-0}" "${cmd:-}" "${maintainer:-}" "${fabric_id:-}" "${weight:-}") || { echo "❌ edge_add 失败"; return 1; }
    config_save "$CONFIG"
}

edge_list() {
    python3 "$JSON_OP" < "$CONFIG_FILE" edge_list
}

# 从 ~/.ssh/config 中安全删除 Host 条目（用 awk 替代有缺陷的 sed）
ssh_config_remove_host() {
    local host=$1
    [ -z "$host" ] && return
    [ ! -f ~/.ssh/config ] && return

    if ! grep -q "^Host $host\$" ~/.ssh/config 2>/dev/null; then
        return
    fi

    cp ~/.ssh/config "$HOME/.ssh/config.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null

    awk -v host="$host" '
    BEGIN { skip = 0 }
    /^Host / {
        if ($2 == host) { skip = 1; next }
        else { skip = 0 }
    }
    !skip { print }
    ' ~/.ssh/config > ~/.ssh/config.tmp

    mv ~/.ssh/config.tmp ~/.ssh/config
    chmod 600 ~/.ssh/config 2>/dev/null
}

edge_remove() {
    local id=$1
    # 提取目标主机名（边 ID 格式: from→to）
    local host="${id#*→}"
    CONFIG=$(python3 "$JSON_OP" < "$CONFIG_FILE" edge_remove "$id") || { echo "❌ edge_remove 失败"; return 1; }
    config_save "$CONFIG"
    # 同步清理 SSH config
    ssh_config_remove_host "$host"
}

# ---- 端口操作 ----

port_is_free() {
    local port=$1
    if ! python3 "$JSON_OP" < "$CONFIG_FILE" port_is_free "$port" | grep -q True; then
        return 1
    fi
    grep -qE "^[[:space:]]*Port ${port}$" ~/.ssh/config 2>/dev/null && return 1
    ss -tlnp 2>/dev/null | grep -q ":$port " && return 1
    return 0
}

port_allocate() {
    # 原子分配：锁内扫描 + 立即预留
    exec 9>"${CONFIG_FILE}.lock"
    if ! flock -w 10 9 2>/dev/null; then
        echo "❌ 端口分配锁获取超时" >&2
        exec 9>&-
        return 1
    fi
    # 锁内重新读取最新 config（防 TOCTOU）
    local cfg port
    cfg=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{"servers":{},"edges":[],"ports":{"used":[],"next":2201}}')
    port=$(echo "$cfg" | python3 "$JSON_OP" get ports.next 2>/dev/null || echo 2201)
    while true; do
        # 检查 config.json ports.used（锁内最新数据）
        if ! echo "$cfg" | python3 "$JSON_OP" port_is_free "$port" | grep -q True; then
            port=$((port + 1))
            [ $port -gt 2299 ] && port=2201
            local tries=$((tries + 1))
            [ ${tries:-0} -gt 100 ] && { echo "❌ 端口池耗尽 (2201-2299)" >&2; flock -u 9 2>/dev/null; exec 9>&-; return 1; }
            continue
        fi
        # 检查 SSH config 和系统端口
        if grep -qE "^[[:space:]]*Port ${port}$" ~/.ssh/config 2>/dev/null; then
            port=$((port + 1)); [ $port -gt 2299 ] && port=2201; continue
        fi
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            port=$((port + 1)); [ $port -gt 2299 ] && port=2201; continue
        fi
        break
    done
    # 原子预留：立即写入 config.json
    cfg=$(echo "$cfg" | python3 -c "
import json,sys
d=json.load(sys.stdin)
d.setdefault('ports',{}).setdefault('used',[]).append($port)
d['ports']['next']=$((port+1))
print(json.dumps(d))
")
    echo "$cfg" > "$CONFIG_FILE"
    CONFIG="$cfg"
    CONFIG_PORT_NEXT=$((port + 1))
    flock -u 9 2>/dev/null
    exec 9>&-
    echo $port
}

# ---- 图操作 ----

graph_viz() {
    python3 "$JSON_OP" < "$CONFIG_FILE" viz
}

# ---- 隧道/教程 ----

tunnel_cmds() {
    python3 "$JSON_OP" < "$CONFIG_FILE" tunnel_cmds
}

generate_tutorial() {
    HOSTNAME="${HOSTNAME:-$(hostname)}"; export HOSTNAME
    _NOW="$(date)"; export _NOW
    python3 "$JSON_OP" < "$CONFIG_FILE" tutorial
}
