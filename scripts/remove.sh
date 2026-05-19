#!/bin/bash
# remove.sh - 废契
do_remove() {
    CONFIG=$(config_load)
    echo ""; echo "现有契约:"
    config_json_get "import json,sys;d=json.load(sys.stdin);[print(f\"  [{i}] {c['id']}\") for i,c in enumerate(d.get('contracts',[]))]"
    read -p "输入编号删除: " IDX
    [ -z "$IDX" ] && return
    CONFIG=$(config_json_get "
import json,sys;d=json.load(sys.stdin)
i=int('$IDX')
if 0<=i<len(d.get('contracts',[])):
    c=d['contracts'].pop(i)
    if c.get('tunnel_port') and c['tunnel_port'] in d['ports']['used']: d['ports']['used'].remove(c['tunnel_port'])
    print(f'✓ 已删除: {c[\"id\"]}')
    print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"
}
