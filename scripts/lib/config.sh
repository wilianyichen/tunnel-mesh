# ========================================
# 配置管理库 - config.json 读写、备份、端口检查
# ========================================

CONFIG_DIR="$HOME/.tunnel-mesh"
CONFIG_FILE="$CONFIG_DIR/config.json"

config_load() {
    mkdir -p "$CONFIG_DIR"
    [ -f "$CONFIG_FILE" ] && cat "$CONFIG_FILE" || echo '{"servers":{},"contracts":[],"ports":{"used":[],"next":2201}}'
}

config_save() {
    mkdir -p "$CONFIG_DIR"
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_DIR/config.json.bak.$(date +%Y%m%d-%H%M%S)"
    ls -t "$CONFIG_DIR"/config.json.bak.* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
    echo "$1" > "$CONFIG_FILE"
}

port_is_free() {
    local port=$1
    echo "$CONFIG" | grep -q "\"$port\"" 2>/dev/null && return 1
    grep -q "Port $port" ~/.ssh/config 2>/dev/null && return 1
    ss -tlnp 2>/dev/null | grep -q ":$port " && return 1
    netstat -tlnp 2>/dev/null | grep -q ":$port " && return 1
    return 0
}

port_allocate() {
    local port=${CONFIG_PORT_NEXT:-2201}
    while ! port_is_free $port; do
        port=$((port + 1))
        [ $port -gt 2299 ] && { echo "2201"; return; }
    done
    echo $port
}

config_json_get() {
    echo "$CONFIG" | python3 -c "$1" 2>/dev/null
}
