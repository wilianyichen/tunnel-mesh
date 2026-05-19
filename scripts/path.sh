#!/bin/bash
# path.sh - 多跳路径查找
do_path() {
    CONFIG=$(config_load)
    echo ""; echo "可到达的服务器:"
    config_json_get "import json,sys;d=json.load(sys.stdin);[print(f'  {n}') for n in d.get('servers',{})]"
    read -p "目标服务器: " TARGET; [ -z "$TARGET" ] && return

    SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    RESULT=$(python3 -c "
import json,sys;sys.path.insert(0,'$SCRIPT_DIR/scripts')
from graph import Graph
c=json.load(open('$HOME/.tunnel-mesh/config.json'))
g=Graph()
for n in c.get('servers',{}):g.add_vertex(n)
for e in c.get('contracts',[]):
    if e['master'] in g.vertices and e['servant'] in g.vertices:
        g.add_edge(e['master'],e['servant'],1.5 if e.get('type')=='reverse' else 1.0)
p=g.shortest_path('$HOSTNAME','$TARGET')
print(json.dumps({'ok':True,'path':' → '.join(p),'hops':len(p)-1,'jumps':','.join(p[1:-1]) if len(p)>2 else ''}) if p else {'ok':False}))
" 2>/dev/null)

    [ -z "$RESULT" ] && { echo "计算失败"; return; }
    OK=$(echo "$RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('ok',False))")
    [ "$OK" != "True" ] && { echo "不可达"; return; }

    PATH_STR=$(echo "$RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin)['path'])")
    HOPS=$(echo "$RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin)['hops'])")
    JUMPS=$(echo "$RESULT" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('jumps',''))")
    echo "  路径: $PATH_STR  跳数: $HOPS"

    if [ "$HOPS" -gt 1 ] && [ -n "$JUMPS" ]; then
        echo "  ssh -J $JUMPS $TARGET"
        read -p "  保存为永久连接？[Y/n]: " S
        [ "$S" = "n" ] || [ "$S" = "N" ] && return
        mkdir -p ~/.ssh
        if ! grep -q "Host $TARGET" ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $TARGET（多跳: $PATH_STR）
Host $TARGET
    HostName $TARGET
    ProxyJump $JUMPS
    User root
    StrictHostKeyChecking no
EOF
            chmod 600 ~/.ssh/config; echo "✓ 已保存"
        fi
    fi
}
