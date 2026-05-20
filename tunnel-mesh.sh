#!/bin/bash
# ========================================
# Tunnel Mesh - 主入口
# 用法: bash tunnel-mesh.sh [export|import|status|remove|wizard|path|logs|recover]
# ========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/scripts/lib/detect.sh"
source "$SCRIPT_DIR/scripts/lib/config.sh"
detect_identity
CONFIG=$(config_load)
CONFIG_PORT_NEXT=$(config_json_get "import json,sys;print(json.load(sys.stdin)['ports']['next'])")
source "$SCRIPT_DIR/scripts/export.sh"
source "$SCRIPT_DIR/scripts/import.sh"
source "$SCRIPT_DIR/scripts/status.sh"
source "$SCRIPT_DIR/scripts/remove.sh"
source "$SCRIPT_DIR/scripts/wizard.sh"
source "$SCRIPT_DIR/scripts/path.sh"
source "$SCRIPT_DIR/scripts/recover.sh"
source "$SCRIPT_DIR/scripts/log.sh"
source "$SCRIPT_DIR/scripts/ssh-config.sh"

# 直接调用
case "${1:-menu}" in
    export)  do_export; exit 0 ;;
    import)  do_import; exit 0 ;;
    deploy) do_deploy_key; exit 0 ;;
    status)  do_status; exit 0 ;;
    remove)  do_remove; exit 0 ;;
    wizard)  do_wizard; exit 0 ;;
    path)    do_path; exit 0 ;;
    logs)    do_logs; exit 0 ;;
    ssh)     do_ssh_config; exit 0 ;;  # 新增
    recover) do_recover; exit 0 ;;
esac

# 交互菜单
while true; do
    show_header
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║                                                  ║"
    echo "║  📤 [1] 导出身份卡 — 把本机信息给对方            ║"
    echo "║  📥 [2] 导入身份卡 — 我是主，我要连对方          ║"
    echo "║  🔑 [3] 部署公钥   — 我是仆，让别人连我          ║"
    echo "║  📋 [4] 审视契约   — 查看已有连接                ║"
    echo "║  🗑  [5] 废契       — 删除某个连接                ║"
    echo "║  🧭 [6] 配置向导   — 告诉我怎么做                ║"
    echo "║  🔍 [7] 探寻路径   — 查看到目标的跳转路径        ║"
    echo "║  🔄 [8] 恢复配置   — 重建 SSH config              ║"
    echo "║  📜 [9] 查看日志   — 浏览隧道日志                ║"
    echo "║  ⚙️  [0] SSH管理    — 管理 ~/.ssh/config 连接     ║"
    echo "║  ❌ [Q] 退出                                     ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    read -p "选择: " C
    case $C in
        1) do_export ;;
        2) do_import ;;
        3) do_deploy_key ;;
        4) do_status ;;
        5) do_remove ;;
        6) do_wizard ;;
        7) do_path ;;
        8) do_recover ;;
        9) do_logs ;;
        0) do_ssh_config ;;
        q|Q) exit 0 ;;
    esac
    echo ""; read -p "按回车继续..."
done
