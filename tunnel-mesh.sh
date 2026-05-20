#!/bin/bash
# Tunnel Mesh 2.0 — 主入口
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/scripts/lib/detect.sh"
source "$SCRIPT_DIR/scripts/lib/config.sh"
source "$SCRIPT_DIR/scripts/lib/network.sh"
source "$SCRIPT_DIR/scripts/lib/graph.sh"
source "$SCRIPT_DIR/scripts/phase1-key.sh"
source "$SCRIPT_DIR/scripts/phase2-edge.sh"
source "$SCRIPT_DIR/scripts/phase3-tunnel.sh"

detect_identity
CONFIG=$(config_load)
CONFIG_PORT_NEXT=$(config_json "import json,sys;print(json.load(sys.stdin)['ports']['next'])")

while true; do
    show_identity
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  🔑 [1] 密钥管理   — 生成/部署公钥 (Phase 1)     ║"
    echo "║  🔗 [2] 边规划     — 构建主→仆连接 (Phase 2)     ║"
    echo "║  🚇 [3] 隧道管理   — 查看/教程 (Phase 3)         ║"
    echo "║  📋 [4] 查看图     — 节点+边+路径                ║"
    echo "║  🗑  [5] 删除       — 删节点或边                  ║"
    echo "║  🔍 [6] 探寻路径   — 查看到目标的跳转            ║"
    echo "║  ⚙️  [7] SSH管理    — 管理 ~/.ssh/config          ║"
    echo "║  ❌ [Q] 退出                                     ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    read -p "选择: " C
    case $C in
        1) do_key_menu ;;
        2) do_edge_plan ;;
        3) do_tunnel_menu ;;
        4)
            echo ""; echo "════════════════════════════════════════"
            echo "  图状态"; echo "════════════════════════════════════════"
            echo ""; echo "节点:"; server_list
            echo ""; echo "边:"; edge_list
            read -p "按回车继续..."
            ;;
        5)
            echo ""; echo "边:"; edge_list
            read -p "输入要删除的边ID: " EID
            [ -n "$EID" ] && edge_remove "$EID" && echo "✓ 已删除"
            read -p "按回车继续..."
            ;;
        6)
            echo ""; read -p "目标服务器: " TARGET
            [ -n "$TARGET" ] && proxyjump_cmd "$HOSTNAME" "$TARGET"
            read -p "按回车继续..."
            ;;
        7)
            echo ""; echo "SSH Config 条目:"
            grep "^Host " ~/.ssh/config 2>/dev/null | grep -v "^#"
            read -p "按回车继续..."
            ;;
        q|Q) exit 0 ;;
    esac
done
