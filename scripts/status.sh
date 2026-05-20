#!/bin/bash
# status.sh - 审视契约 + 显示隧道命令

do_status() {
    CONFIG=$(config_load)
    echo ""; echo "════════════════════════════════════════"
    echo "  契约大厅 — $HOSTNAME"
    echo "════════════════════════════════════════"; echo ""
    echo "已知服务器:"; config_json_get "import json,sys;d=json.load(sys.stdin);[print(f\"  {s['name']:<15} {s['ip']}:{s['port']}  {s.get('fingerprint','')[:12]}\") for s in d.get('servers',{}).values()]"
    echo ""; echo "契约列表 ($(config_json_get "import json,sys;print(len(json.load(sys.stdin).get('contracts',[])))")):"
    config_json_get "import json,sys;d=json.load(sys.stdin);[print(f\"  {c['id']:<25} {c.get('type','?'):<10} 端口:{c.get('tunnel_port','-')}\") for c in d.get('contracts',[])]"
    echo ""; echo "已用端口: $(config_json_get "import json,sys;print(','.join(map(str,json.load(sys.stdin)['ports']['used'])))")"
    echo ""
    echo "[C] 显示隧道命令（复制到 Windows 重新导入）"
    read -p "选择: " SC
    [ "$SC" = "C" ] || [ "$SC" = "c" ] && do_show_cmd
}

do_show_cmd() {
    CONFIG=$(config_load)
    echo ""; echo "════════════════════════════════════════"
    echo "  隧道命令（复制到 Windows 导入）"
    echo "════════════════════════════════════════"; echo ""
    config_json_get "import json,sys;d=json.load(sys.stdin)
for c in d.get('contracts',[]):
    if c.get('tunnel_cmd'):
        print(c['tunnel_cmd'])
        print()" 2>/dev/null
    if [ $? -ne 0 ]; then
        # fallback: grep from raw config
        grep -o '"tunnel_cmd": "[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4
    fi
}
