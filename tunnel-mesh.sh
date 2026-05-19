#!/bin/bash
# ========================================
# Tunnel Mesh - 主入口
# 用法: bash tunnel-mesh.sh [export|import|status|remove|wizard|path|logs|recover]
# ========================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 加载库
source "$SCRIPT_DIR/scripts/lib/detect.sh"
source "$SCRIPT_DIR/scripts/lib/config.sh"

# 初始化
detect_identity
CONFIG=$(config_load)
CONFIG_PORT_NEXT=$(config_json_get "import json,sys;print(json.load(sys.stdin)['ports']['next'])")

# 加载子脚本
source "$SCRIPT_DIR/scripts/export.sh"
source "$SCRIPT_DIR/scripts/import.sh"
source "$SCRIPT_DIR/scripts/status.sh"
source "$SCRIPT_DIR/scripts/remove.sh"
source "$SCRIPT_DIR/scripts/wizard.sh"
source "$SCRIPT_DIR/scripts/path.sh"
source "$SCRIPT_DIR/scripts/log.sh"
source "$SCRIPT_DIR/scripts/recover.sh"

# ── 直接调用模式 ──
case "${1:-menu}" in
    export)  do_export; exit 0 ;;
    import)  do_import; exit 0 ;;
    status)  do_status; exit 0 ;;
    remove)  do_remove; exit 0 ;;
    wizard)  do_wizard; exit 0 ;;
    path)    do_path; exit 0 ;;
    logs)    do_logs; exit 0 ;;
    recover) do_recover; exit 0 ;;
esac

# ── 交互菜单 ──
while true; do
    show_header
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║                                        ║"
    echo "║  [1] 导出身份卡（给别人）              ║"
    echo "║  [2] 导入身份卡（连接别人）            ║"
    echo "║  [3] 审视契约（查看所有连接）          ║"
    echo "║  [4] 废契（删除连接）                  ║"
    echo "║  [5] 配置向导                          ║"
    echo "║  [6] 探寻路径（多跳）                  ║"
    echo "║  [7] 恢复配置                          ║"
    echo "║  [8] 查看日志                          ║"
    echo "║  [Q] 退出                              ║"
    echo "║                                        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    read -p "选择: " C
    case $C in
        1) do_export ;;
        2) do_import ;;
        3) do_status ;;
        4) do_remove ;;
        5) do_wizard ;;
        6) do_path ;;
        7) do_recover ;;
        8) do_logs ;;
        q|Q) exit 0 ;;
    esac
    echo ""; read -p "按回车继续..."
done
