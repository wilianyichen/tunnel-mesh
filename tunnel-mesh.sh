#!/bin/bash
# Tunnel Mesh 3.0 — 主入口
# 双层架构: config.json (逻辑图) + fabric.json (物理连接层)
VERSION="3.0.0"
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- 非 TTY 自动降级（必须在参数解析之前） ----
if [ ! -t 0 ]; then
    if [ -z "${1:-}" ]; then
        echo "Tunnel Mesh v$VERSION"
        echo "用法: tunnel-mesh --cmd <命令> [参数...]"
        echo "详情: tunnel-mesh --help"
        exit 0
    elif [ "${1}" != "--cmd" ] && [ "${1}" != "--help" ] && [ "${1}" != "-h" ] && \
         [ "${1}" != "--version" ] && [ "${1}" != "-v" ]; then
        # 裸命令自动转为 --cmd 模式：ssh node3 'tunnel-mesh server-list' → --cmd server-list
        set -- --cmd "$@"
    fi
fi

# ---- CLI 模式 ----
case "${1:-}" in
    --help|-h)
        echo "Tunnel Mesh v$VERSION — 分布式 SSH 隧道网状连接工具"
        echo ""
        echo "用法:"
        echo "  bash tunnel-mesh.sh              交互式菜单（默认）"
        echo "  bash tunnel-mesh.sh --help       显示此帮助"
        echo "  bash tunnel-mesh.sh --version    显示版本号"
        echo "  bash tunnel-mesh.sh --cmd <cmd>  脚本模式（非交互）"
        echo ""
        echo "脚本模式命令:"
        echo "  server-list                      列出所有服务器"
        echo "  server-add <name> <ip> [port] [user]"
        echo "  server-exists <name>             检查服务器是否存在"
        echo "  server-remove <name>             删除服务器"
        echo "  edge-list                        列出所有边"
        echo "  edge-add <from> <to> <type> [port] [cmd] [maintainer]"
        echo "  edge-remove <id>                 删除边"
        echo "  fabric-list                      列出所有 Fabric"
        echo "  fabric-health [id]               健康检查"
        echo "  fabric-cmds                      列出维持命令"
        echo "  path <from> <to>                 JSON 路径查询"
        echo "  viz                              逻辑拓扑图"
        echo "  fabric-viz                       物理拓扑图"
        echo "  port-allocate                    分配端口"
        echo "  port-is-free <port>              检查端口是否可用"
        echo "  tutorial                         生成部署教程"
        echo "  identity                         显示当前节点名"
        echo "  identity-import [card_text]      导入身份卡"
        echo "  reachability                     生成网络可达报告"
        echo "  reachability-merge <r1.json>...  合并多机可达报告"
        echo "  import                           批量导入身份卡（stdin）"
        echo "  deploy-guide <r1.json>...         按机器聚合部署指南"
        echo "  apply [--dry-run|--yes]         部署隧道（冲突检测 + systemd）"
        echo "  key-deploy <server> [--key <path>] 部署公钥"
        echo "  deploy-windows <server>           部署到 Windows"
        echo "  discover [--ports ...]            自动拓扑探测，生成边建议"
        echo "  quickstart [--non-interactive] [--yes] 引导式一键配置"
        echo "  ensure <server|edge|key> ...      幂等操作，可安全重复执行"
        echo "  service <edge-id|--all> <start|stop|restart|status>  管控隧道 systemd service"
        echo "  repair                            自愈：健康检查 → 重启失败隧道 → 再检查"
        echo "  status                           查看所有隧道运行状态"
        echo "  health                           健康检查所有隧道"
        echo "  upgrade                           从 GitHub 拉取最新版本"
        echo ""
        echo "5 个 Phase:"
        echo "  [1] 建立加密信任 — 生成/交换 SSH 密钥"
        echo "  [2] 建立网络信任 — 递归建边（主→仆链路）"
        echo "  [3] 维持信任     — Fabric 管理 + 健康检查"
        echo "  [4] 审视信任     — 双层拓扑 + 路径探寻"
        echo "  [5] 撤销信任     — 删边 + 释放端口"
        echo ""
        echo "文档: https://github.com/wilianyichen/tunnel-mesh"
        echo "架构: docs/ARCHITECTURE.md"
        exit 0
        ;;
    --version|-v)
        echo "Tunnel Mesh v$VERSION"
        exit 0
        ;;
        --cmd)
            # 脚本模式：跳过交互，由后续 --cmd 块处理
            ;;
esac

# Ctrl+C / 异常退出时清理提示
_cleanup_int() {
    echo ""
    echo "⚠ 操作已中断 (Ctrl+C)。如正在递归建边，链路可能不完整。"
    echo "  建议检查: ~/.tunnel-mesh/config.json 和 fabric.json"
    trap - INT TERM
    exit 130
}
_cleanup_term() {
    echo ""
    echo "⚠ 收到终止信号 (SIGTERM)，正在退出..."
    trap - INT TERM
    exit 143
}
trap _cleanup_int INT
trap _cleanup_term TERM

# 前置检查
if ! command -v python3 &>/dev/null; then
    echo "❌ 需要 python3，请先安装"
    echo "   Ubuntu/Debian: sudo apt install python3"
    echo "   CentOS/RHEL:   sudo yum install python3"
    exit 1
fi

# 自愈：检测 CRLF 并自动修复
if grep -q $'\r' "$0" 2>/dev/null; then
    echo "检测到 Windows 换行符，自动修复..."
    find "$SCRIPT_DIR" -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null
    exec bash "$0" "$@"
fi

source "$SCRIPT_DIR/scripts/lib/detect.sh"
source "$SCRIPT_DIR/scripts/lib/config.sh"
source "$SCRIPT_DIR/scripts/lib/fabric.sh"
source "$SCRIPT_DIR/scripts/lib/network.sh"
source "$SCRIPT_DIR/scripts/lib/reachability.sh"
source "$SCRIPT_DIR/scripts/lib/graph.sh"
source "$SCRIPT_DIR/scripts/lib/tunnel-builder.sh"
source "$SCRIPT_DIR/scripts/phase1-key.sh"
source "$SCRIPT_DIR/scripts/phase2-edge.sh"
source "$SCRIPT_DIR/scripts/phase2-chain.sh"
source "$SCRIPT_DIR/scripts/phase2-recursive.sh"
source "$SCRIPT_DIR/scripts/port-check.sh"
source "$SCRIPT_DIR/scripts/phase3-tunnel.sh"

# --help/--version 不触发网络检测；--cmd 由子命令按需触发
if [ "${1:-}" != "--cmd" ]; then
    detect_identity
fi
CONFIG=$(config_load)
CONFIG_PORT_NEXT=$(config_get ports.next 2>/dev/null || echo 2201)

# 自动检测旧数据格式并提示迁移
_check_migration() {
    if echo "$CONFIG" | python3 -c "
import json, sys
edges = json.load(sys.stdin).get('edges', [])
needs = any('fabric_id' not in e for e in edges) if edges else False
sys.exit(0 if needs else 1)
" 2>/dev/null; then
        echo ""
        echo "⚠ 检测到旧格式 config.json（缺少 fabric_id）"
        echo "  兼容模式运行中，建议迁移到 v3 双层架构"
        echo ""
        read -p "  是否现在迁移？[Y/n]: " DO_MIG
        if [ "$DO_MIG" != "n" ] && [ "$DO_MIG" != "N" ]; then
            python3 "$SCRIPT_DIR/scripts/migrate-v3.sh"
            CONFIG=$(config_load)
            CONFIG_PORT_NEXT=$(config_get ports.next 2>/dev/null || echo 2201)
        fi
        echo ""
    fi
}
if [ "${1:-}" != "--cmd" ]; then
_check_migration

# 首次运行检测：空无配置 → 引导进入 Phase 1
_first_run_check() {
    local server_count edge_count
    server_count=$(echo "$CONFIG" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('servers',{})))" 2>/dev/null || echo 0)
    edge_count=$(echo "$CONFIG" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('edges',[])))" 2>/dev/null || echo 0)
    if [ "$server_count" = "0" ] && [ "$edge_count" = "0" ]; then
        echo ""
        echo "╔══════════════════════════════════════════════════╗"
        echo "║  🎉 欢迎使用 Tunnel Mesh v$VERSION！                 ║"
        echo "╠══════════════════════════════════════════════════╣"
        echo "║  看起来是首次运行，配置为空。                    ║"
        echo "║                                                  ║"
        echo "║  建议从 Phase 1 开始:                             ║"
        echo "║    1. 在本机生成密钥 → 导出\"身份卡\"               ║"
        echo "║    2. 把身份卡发给对方服务器                       ║"
        echo "║    3. 回到本机构建连接                             ║"
        echo "║                                                  ║"
        echo "║  文档: docs/SETUP-BEGINNER.md                     ║"
        echo "╚══════════════════════════════════════════════════╝"
        echo ""
        read -p "  按回车开始..."
    fi
}
_first_run_check
fi  # --cmd 模式跳过交互式检查

# ---- --cmd 命令分发 ----
TPY="$(command -v python3 || echo python3)"  # Python 解释器
TPY_ENTRY="$SCRIPT_DIR/scripts/tunnel_mesh.py"

_cmd_dispatch() {
    local cmd="${1:-}"; shift || true
    case "$cmd" in
        # -- 统一 Python 核心（纯数据操作） --
        server-list|server-exists|server-remove|edge-list|fabric-list|fabric-cmds|viz|fabric-viz|tutorial|identity|identity-import|port-is-free|fabric-health)
            $TPY "$TPY_ENTRY" "$cmd" "$@"
            ;;
        server-add)
            [ $# -lt 2 ] && { echo "用法: tunnel-mesh --cmd server-add <name> <ip> [port] [user]"; exit 1; }
            $TPY "$TPY_ENTRY" "$cmd" "$@"
            ;;
        edge-add)
            [ $# -lt 3 ] && { echo "用法: tunnel-mesh --cmd edge-add <from> <to> <type> [port] [cmd] [maintainer]"; exit 1; }
            $TPY "$TPY_ENTRY" "$cmd" "$@"
            ;;
        edge-remove)
            [ $# -lt 1 ] && { echo "用法: tunnel-mesh --cmd edge-remove <id>"; exit 1; }
            local host="${1#*→}"
            $TPY "$TPY_ENTRY" "$cmd" "$@"
            ssh_config_remove_host "$host"
            ;;
        path)
            [ $# -lt 2 ] && { echo "用法: tunnel-mesh --cmd path <from> <to>"; exit 1; }
            $TPY "$TPY_ENTRY" "$cmd" "$@"
            ;;
        port-allocate)
            $TPY "$TPY_ENTRY" "$cmd" "$@"
            ;;
        # -- 需要 bash 上下文（stdin / detect_identity） --
        reachability)
            detect_identity
            $TPY "$TPY_ENTRY" reachability
            ;;
        reachability-merge)
            [ $# -lt 1 ] && { echo "用法: tunnel-mesh --cmd reachability-merge <report1.json> [report2.json ...]"; exit 1; }
            $TPY "$TPY_ENTRY" reachability-merge "$@"
            ;;
        import)
            detect_identity
            do_key_batch_import_stdin
            ;;
        deploy-guide)
            detect_identity
            do_deploy_guide "$@"
            ;;
        # -- Phase 2/3 新命令（直接透传到 Python） --
        key-deploy|deploy-windows|discover|quickstart|ensure|upgrade|apply|status|health|service|repair)
            $TPY "$TPY_ENTRY" "$cmd" "$@"
            ;;
        help)
            echo "Tunnel Mesh v$VERSION — 命令参考"
            echo ""
            echo "服务器管理:"
            echo "  server-list                    列出所有服务器"
            echo "  server-add <name> <ip> [port]   添加服务器"
            echo "  server-exists <name>            检查服务器是否存在"
            echo "  server-remove <name>            删除服务器"
            echo "  identity                        显示当前节点名"
            echo "  identity-import [card_text]     导入身份卡"
            echo "  import                          从 stdin 批量导入身份卡"
            echo ""
            echo "边与拓扑:"
            echo "  edge-list                       列出所有边"
            echo "  edge-add <from> <to> <type> ... 添加边"
            echo "  edge-remove <id>                删除边"
            echo "  viz                             逻辑拓扑图"
            echo "  fabric-viz                      物理拓扑图"
            echo "  path <from> <to>                最短路径查询"
            echo "  discover [--ports ...]           自动拓扑探测"
            echo ""
            echo "网络可达:"
            echo "  reachability [--ports a,b,...]  多端口并行可达探测"
            echo "  reachability-merge <r.json>...  合并多机可达报告"
            echo "  deploy-guide <r.json>...        按机器生成部署指南"
            echo ""
            echo "部署与运维:"
            echo "  apply [--dry-run|--yes]         部署隧道（systemd + SSH config）"
            echo "  key-deploy <server> [--key]     部署公钥到目标"
            echo "  deploy-windows <server>          部署到 Windows"
            echo "  quickstart [--non-interactive]   引导式一键配置"
            echo "  ensure <server|edge|key> ...     幂等操作"
            echo "  service <edge-id|--all> ...      管控隧道 systemd service"
            echo "  repair                          自愈修复"
            echo "  status                          查看隧道运行状态"
            echo "  health                          健康检查"
            echo "  port-allocate                   分配可用端口"
            echo "  port-is-free <port>             检查端口是否可用"
            echo "  tutorial                        生成部署教程"
            echo "  fabric-list                     列出 Fabric"
            echo "  fabric-health [id]              Fabric 健康检查"
            echo "  fabric-cmds                     列出维持命令"
            echo "  upgrade                          更新到最新版本"
            exit 0
            ;;
        "")
            echo "Tunnel Mesh v$VERSION"
            echo "用法: tunnel-mesh --cmd <命令> [参数...]"
            echo ""
            echo "可用命令:"
            echo "  server-list, server-add, server-exists, server-remove"
            echo "  edge-list, edge-add, edge-remove"
            echo "  reachability, reachability-merge, deploy-guide"
            echo "  discover, quickstart, ensure"
            echo "  apply, key-deploy, deploy-windows, upgrade"
            echo "  status, health, service, repair"
            echo "  viz, path, port-allocate, port-is-free, tutorial"
            echo "  fabric-list, fabric-health, fabric-cmds, fabric-viz"
            echo "  identity, identity-import, import"
            echo ""
            echo "详情: tunnel-mesh --help"
            exit 0
            ;;
        *)
            echo "未知命令: $cmd"
            echo "可用: server-list|server-add|server-exists|server-remove|edge-list|edge-add|edge-remove|fabric-list|fabric-health|fabric-cmds|viz|fabric-viz|path|port-allocate|port-is-free|tutorial|identity|identity-import|reachability|reachability-merge|import|deploy-guide|apply|key-deploy|deploy-windows|discover|quickstart|ensure|service|repair|status|health|upgrade"
            exit 1
            ;;
    esac
}

# ---- --cmd 脚本模式 ----
if [ "${1:-}" = "--cmd" ]; then
    shift
    _cmd_dispatch "$@"
    exit $?
fi

# ---- 维持信任子菜单 ----
do_trust_maintain_menu() {
    while true; do
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║  维持信任                              ║"
        echo "╠════════════════════════════════════════╣"
        echo "║  [1] Fabric 管理 — 物理连接层管理中心   ║"
        echo "║  [2] 恢复配置   — 从备份恢复 config    ║"
        echo "║  [B] 返回主菜单                        ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        read -p "选择: " C
        case $C in
            1) do_fabric_menu ;;
            2)
                echo ""; echo "可用备份:"
                ls -t "$CONFIG_DIR"/config.json.bak.* 2>/dev/null | head -10 | while read f; do
                    echo "  $(basename "$f")  ($(wc -c < "$f" 2>/dev/null || echo '?') bytes)"
                done
                echo ""
                read -p "输入要恢复的备份文件名（回车取消）: " BAKFILE
                if [ -n "$BAKFILE" ] && [ -f "$CONFIG_DIR/$BAKFILE" ]; then
                    cp "$CONFIG_FILE" "$CONFIG_DIR/config.json.bak.before-recover-$(date +%Y%m%d-%H%M%S)"
                    cp "$CONFIG_DIR/$BAKFILE" "$CONFIG_FILE"
                    CONFIG=$(config_load)
                    CONFIG_PORT_NEXT=$(config_get ports.next 2>/dev/null || echo 2201)
                    echo "✓ 已恢复配置"
                elif [ -n "$BAKFILE" ]; then
                    echo "❌ 文件不存在"
                fi
                read -p "按回车继续..."
                ;;
            b|B) return ;;
        esac
    done
}

# ---- 审视信任子菜单 ----
do_trust_inspect_menu() {
    while true; do
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║  审视信任                              ║"
        echo "╠════════════════════════════════════════╣"
        echo "║  [1] 拓扑图     — 逻辑/物理双层拓扑    ║"
        echo "║  [2] 探寻路径   — 查看到目标的跳转     ║"
        echo "║  [3] SSH配置    — 管理 ~/.ssh/config   ║"
        echo "║  [B] 返回主菜单                        ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        read -p "选择: " C
        case $C in
            1) do_topology_menu ;;
            2)
                do_path_find
                read -p "按回车继续..."
                ;;
            3)
                echo ""; echo "SSH Config 条目:"
                grep "^Host " ~/.ssh/config 2>/dev/null | grep -v "^#"
                read -p "按回车继续..."
                ;;
            b|B) return ;;
        esac
    done
}

while true; do
    show_identity
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  🔑 [1] 建立加密信任 — 生成/交换密钥             ║"
    echo "║  🔗 [2] 建立网络信任 — 构建连接（正向/反向）     ║"
    echo "║  🚇 [3] 维持信任     — 隧道管理 + 恢复配置       ║"
    echo "║  📋 [4] 审视信任     — 拓扑图 + 路径 + SSH管理   ║"
    echo "║  🗑  [5] 撤销信任     — 删除节点/边              ║"
    echo "║  🔌 [8] 端口检测     — 查看可用端口              ║"
    echo "║  ❓ [?] 帮助         — 各功能详解                ║"
    echo "║  ❌ [Q] 退出                                     ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    read -p "选择: " C
    case $C in
        1) do_key_menu ;;
        2)
            echo ""
            echo "  选择建边模式:"
            echo "    [1] 经典单跳      — 主→仆直接判定（快速）"
            echo "    [2] 递归建边      — 引入中间节点构建链路"
            echo "    [3] 可达报告驱动  — 基于多机探测报告智能建边"
            read -p "  选择 [2]: " EDGE_MODE; EDGE_MODE=${EDGE_MODE:-2}
            case $EDGE_MODE in
                1) do_edge_plan ;;
                2) do_edge_plan_recursive ;;
                3) do_reachability_edge ;;
            esac
            ;;
        3) do_trust_maintain_menu ;;
        4) do_trust_inspect_menu ;;
        5)
            echo ""; echo "边:"; edge_list
            read -p "输入要删除的边ID: " EID
            if [ -z "$EID" ]; then
                echo "  输入不能为空"
                read -p "按回车继续..."
                continue
            fi
            del_host="${EID#*→}"
            echo ""
            echo "  将删除:"
            echo "    - 边: $EID"
            echo "    - SSH config Host: $del_host"
            echo "    - 关联的 fabric（如有）"
            read -p "  确认删除？[y/N]: " CONFIRM
            if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
                edge_remove "$EID" && echo "✓ 已删除"
            else
                echo "  已取消"
            fi
            read -p "按回车继续..."
            ;;
        8) do_port_check ;;
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
