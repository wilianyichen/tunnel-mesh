#!/bin/bash
# ========================================
# 配置管理 - config.json 读写 + 备份 + 端口
# ========================================

CONFIG_DIR="$HOME/.tunnel-mesh"
CONFIG_FILE="$CONFIG_DIR/config.json"

config_load() {
    mkdir -p "$CONFIG_DIR"
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        echo '{"servers":{},"edges":[],"ports":{"used":[],"next":2201}}'
    fi
}

config_save() {
    mkdir -p "$CONFIG_DIR"
    [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$CONFIG_DIR/config.json.bak.$(date +%Y%m%d-%H%M%S)"
    ls -t "$CONFIG_DIR"/config.json.bak.* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null
    echo "$1" > "$CONFIG_FILE"
}

config_json() {
    echo "$CONFIG" | python3 -c "$1" 2>/dev/null
}

port_is_free() {
    local port=$1
    config_json "import json,sys;d=json.load(sys.stdin);print(port not in d['ports']['used'])" 2>/dev/null | grep -q True || return 1
    grep -q "Port $port" ~/.ssh/config 2>/dev/null && return 1
    ss -tlnp 2>/dev/null | grep -q ":$port " && return 1
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

# 服务器管理
server_exists() {
    config_json "import json,sys;d=json.load(sys.stdin);print('$1' in d.get('servers',{}))" 2>/dev/null | grep -q True
}

server_add() {
    local name=$1 ip=$2 port=$3 user=$4 fp=$5 pubkey=$6
    CONFIG=$(config_json "
import json,sys;d=json.load(sys.stdin)
d['servers']['$name']={'name':'$name','ip':'$ip','port':${port:-22},'user':'${user:-root},'fingerprint':'${fp:-}','pubkey':'${pubkey:-}','added':'$(date -Iseconds)'}
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"
}

server_list() {
    config_json "import json,sys;d=json.load(sys.stdin);[print(f\"  {s['name']:<15} {s['ip']}:{s['port']}\") for s in d.get('servers',{}).values()]"
}

# 边管理
edge_add() {
    local from=$1 to=$2 type=$3 port=$4 cmd=$5 maintainer=$6
    local id="${from}→${to}"
    CONFIG=$(config_json "
import json,sys;d=json.load(sys.stdin)
d['edges'].append({'id':'$id','from':'$from','to':'$to','type':'$type','tunnel_port':${port:-0},'tunnel_cmd':'${cmd:-}','maintainer':'${maintainer:-}','status':'active','created':'$(date -Iseconds)'})
if ${port:-0} > 0: d['ports']['used'].append($port)
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"
}

edge_list() {
    config_json "import json,sys;d=json.load(sys.stdin);[print(f\"  {e['id']:<25} {e.get('type','?'):<10} {'端口:'+str(e['tunnel_port']) if e.get('tunnel_port') else ''}\") for e in d.get('edges',[])]"
}

edge_remove() {
    local id=$1
    CONFIG=$(config_json "
import json,sys;d=json.load(sys.stdin)
d['edges']=[e for e in d.get('edges',[]) if e.get('id')!='$id']
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"
}
