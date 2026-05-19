#!/bin/bash
# status.sh - 审视契约
do_status() {
    CONFIG=$(config_load)
    echo ""; echo "════════════════════════════════════════"; echo "  契约大厅 — $HOSTNAME"; echo "════════════════════════════════════════"; echo ""
    echo "已知服务器:"; config_json_get "import json,sys;d=json.load(sys.stdin);[print(f\"  {s['name']:<15} {s['ip']}:{s['port']}  {s.get('fingerprint','')[:12]}\") for s in d.get('servers',{}).values()]"
    echo ""; echo "契约列表 ($(config_json_get "import json,sys;print(len(json.load(sys.stdin).get('contracts',[])))")):"
    config_json_get "import json,sys;d=json.load(sys.stdin);[print(f\"  {c['id']:<25} {c.get('type','?'):<10} 端口:{c.get('tunnel_port','-')}\") for c in d.get('contracts',[])]"
    echo ""; echo "已用端口: $(config_json_get "import json,sys;print(','.join(map(str,json.load(sys.stdin)['ports']['used'])))")"
}
