#!/bin/bash
# export.sh - 导出身份卡

do_export() {
    CONFIG=$(config_load)
    CONFIG_PORT_NEXT=$(config_json_get "import json,sys;d=json.load(sys.stdin);print(d['ports']['next'])")

    if config_json_get "import json,sys;print('$HOSTNAME' in json.load(sys.stdin).get('servers',{}))" | grep -q True; then
        echo ""; read -p "已导出过，重新导出？[y/N]: " RE
        [ "$RE" != "y" ] && [ "$RE" != "Y" ] && return
    fi

    CONFIG=$(config_json_get "
import json,sys;d=json.load(sys.stdin)
d['servers']['$HOSTNAME']={'name':'$HOSTNAME','ip':'$IP','port':$PORT,'user':'$USER','fingerprint':'${FINGERPRINT:-unknown}','exported_at':'$(date -Iseconds)'}
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  身份已保存                             ║"
    echo "╠════════════════════════════════════════╣"
    echo "║  主机名 : $HOSTNAME"
    echo "║  内网IP : $IP"
    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "║  公网IP : $PUBLIC_IP"
    echo "║  SSH端口: $PORT"
    echo "║  用户   : $USER"
    [ -n "$FINGERPRINT" ] && echo "║  公钥指纹: $FINGERPRINT"
    echo "╚════════════════════════════════════════╝"

    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "" && echo "  检测到公网IP: $PUBLIC_IP（隧道命令将使用此IP）"

    echo ""
    echo "════════════════════════════════════════"
    echo "  身份卡（复制给对方）"
    echo "════════════════════════════════════════"
    echo ""
    echo "===IDENTITY==="
    echo "NAME=$HOSTNAME"
    echo "IP=$IP"
    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "PUBLIC_IP=$PUBLIC_IP"
    echo "PORT=$PORT"
    echo "USER=$USER"
    echo "PUBKEY=$PUBKEY"
    echo "FINGERPRINT=${FINGERPRINT:-unknown}"
    echo "===END==="
    echo ""
}
