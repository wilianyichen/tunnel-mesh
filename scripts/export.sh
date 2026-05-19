#!/bin/bash
# export.sh - 导出本机身份信息，给对方用于连接规划

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
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║   你现在是：$HOSTNAME                             ║"
    echo "║   你要把身份信息交给想要连接你的一方               ║"
    echo "║                                                  ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  主机名 : $HOSTNAME"
    echo "║  内网IP : $IP                              ║"
    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "║  公网IP : $PUBLIC_IP                        ║"
    echo "║  SSH端口: $PORT                                   ║"
    echo "║  登录用户: $USER"
    [ -n "$FINGERPRINT" ] && echo "║  密钥指纹: $FINGERPRINT"
    echo "╚══════════════════════════════════════════════════╝"

    if [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ]; then
        echo ""
        echo "  📌 你是云服务器，有独立公网IP：$PUBLIC_IP"
        echo "     生成的隧道命令会使用这个公网IP"
    else
        echo ""
        echo "  📌 你是内网服务器，只有内网IP：$IP"
    fi
    echo ""
    echo "  👉 下一步：把下面的「身份卡」复制给对方"
    echo "     对方拿到后可以知道你是谁，然后配置连接"
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
    echo "  📋 对方收到后，运行 bash tunnel-mesh.sh import"
    echo "     然后粘贴上面的身份卡即可"
    echo ""
}
