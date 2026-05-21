#!/bin/bash
# port-check.sh - 端口检测

do_port_check() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  端口检测"
    echo "════════════════════════════════════════"
    echo ""

    # 三层检查
    echo "【本机】$(hostname) ($(hostname -I | awk '{print $1}'))"
    echo ""

    # 1. 系统端口
    echo "── 系统占用端口 ──"
    ss -tlnp 2>/dev/null | awk 'NR>1{print "  "$4}' | grep -oP ':\d+' | sort -t: -k2 -n | uniq | head -20
    echo ""

    # 2. SSH config 端口
    echo "── SSH config 端口 ──"
    grep "^Port \|^    Port " ~/.ssh/config 2>/dev/null | awk '{print "  "$NF}' | sort -n | uniq
    echo ""

    # 3. config.json 已用端口
    echo "── Tunnel Mesh 已用端口 ──"
    config_json "import json,sys;d=json.load(sys.stdin);print(','.join(map(str,d['ports']['used'])))" 2>/dev/null | tr ',' '\n' | sed 's/^/  /'
    echo ""

    # 建议
    echo "── 建议端口 ──"
    local port=4001
    while port_is_free $port; do
        echo "  $port (可用)"
        break
    done
    port=$((port+1))
    [ $port -gt 4100 ] && port=4001

    echo ""
    echo "  Windows 检测: netstat -ano | findstr LISTENING"
    echo "  Linux   检测: ss -tlnp"
}

# 为链规划找可用端口
chain_find_port() {
    local port=4001
    while ! port_is_free $port 2>/dev/null; do
        port=$((port+1))
        [ $port -gt 4100 ] && { port=4001; break; }
    done
    echo $port
}
