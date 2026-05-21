#!/bin/bash
# Tunnel Mesh 2.0 — 主入口
# 自动修复换行符，确保 git pull 后即用

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 自愈：检测 CRLF 并自动修复
if grep -q $'\r' "$0" 2>/dev/null; then
    echo "检测到 Windows 换行符，自动修复..."
    find "$SCRIPT_DIR" -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null
    exec bash "$0" "$@"
fi

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
    echo "║  ❓ [?] 帮助       — 各功能详解                   ║"
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
        "?")
            echo ""
            echo "════════════════════════════════════════"
            echo "  功能详解"
            echo "════════════════════════════════════════"
            echo ""
            echo "[1] 密钥管理 — Phase 1: 先配密钥"
            echo "    每台服务器生成密钥，互相部署公钥。"
            echo "    密钥就绪后，所有连接方式都简单。"
            echo ""
            echo "[2] 边规划 — Phase 2: 构建连接"
            echo "    选择主(发起方)和仆(目标)，工具检测网络"
            echo "    自动判定正向/反向/多跳，生成配置文件。"
            echo ""
            echo "[3] 隧道管理 — Phase 3: 查看和教程"
            echo "    查看已有隧道命令，生成操作教程。"
            echo ""
            echo "[4] 查看图 — 展示当前所有节点和边"
            echo "[5] 删除 — 删除节点或边"
            echo "[6] 探寻路径 — 查看到任意服务器的跳转路径"
            echo "[7] SSH管理 — 管理 ~/.ssh/config 条目"
            echo ""
            echo "完整流程: [1]密钥→[2]边规划→[3]教程"
            read -p "按回车继续..."
            ;;
        q|Q) exit 0 ;;
    esac
done
