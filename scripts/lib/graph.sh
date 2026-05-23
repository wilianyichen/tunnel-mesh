#!/bin/bash
# ========================================
set -o pipefail
# 图管理 - 路径搜索 + ProxyJump + 链式SSH
# ========================================

# 公共：从 graph.py 获取路径 JSON
_path_json() {
    python3 "$LIB_DIR/../graph.py" --from "$1" --to "$2" --json
}

# ProxyJump 模式 — 需要本地公钥部署到路径上所有节点
# 注意: 仅适用于纯直连路径。含隧道跳的链路应使用链式 SSH（选项 [2]）。
proxyjump_cmd() {
    local result ok hops path_str jumps
    result=$(_path_json "$1" "$2")
    ok=$(echo "$result" | python3 -c "import json,sys;print(json.load(sys.stdin).get('success',False))" 2>/dev/null)

    if [ "$ok" != "True" ]; then
        echo "不可达"
        return 1
    fi

    path_str=$(echo "$result" | python3 -c "import json,sys;print(' → '.join(json.load(sys.stdin)['path']))" 2>/dev/null)
    hops=$(echo "$result" | python3 -c "import json,sys;print(json.load(sys.stdin)['hops'])" 2>/dev/null)

    if [ "$hops" -gt 1 ]; then
        jumps=$(echo "$result" | python3 -c "import json,sys;p=json.load(sys.stdin)['path'];print(','.join(p[1:-1]))" 2>/dev/null)
        echo "ssh -J $jumps $2"
        echo "  路径: $path_str ($hops 跳)"
        echo "  ⚠ ProxyJump 需要本地公钥部署到所有中间节点"
    else
        echo "ssh $2"
        echo "  路径: $path_str (直达)"
    fi
}

# 嵌套 SSH 模式 — 每节点只存邻居公钥
chain_ssh_cmd() {
    local nested_cmd
    nested_cmd=$(echo "$(_path_json "$1" "$2")" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not data.get('success'):
    print('不可达')
    sys.exit(1)
path = data['path']
print(' → '.join(path) + f' ({len(path)-1} 跳)')
if len(path) == 1:
    print(f'ssh {path[0]}')
else:
    cmd = f'ssh {path[-1]}'
    for node in reversed(path[1:-1]):
        cmd = f'ssh -t {node} \"{cmd}\"'
    print(cmd)
    print('(嵌套 SSH 模式 — 每节点只存邻居公钥)')
" 2>/dev/null)
    if [ -z "$nested_cmd" ]; then
        echo "不可达"
        return 1
    fi
    echo "$nested_cmd"
}

# 双层拓扑可视化（Phase 4 使用）
do_topology_menu() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  拓扑图                                ║"
    echo "╠════════════════════════════════════════╣"
    echo "║  [1] 逻辑拓扑 — 登录目标可达关系       ║"
    echo "║  [2] 物理拓扑 — 完整连接层（含中转）   ║"
    echo "║  [B] 返回                              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    read -p "选择: " C
    case $C in
        1)
            echo ""; echo "════════════════════════════════════════"
            echo "  逻辑拓扑"; echo "════════════════════════════════════════"
            echo ""
            graph_viz
            read -p "按回车继续..."
            ;;
        2)
            echo ""; echo "════════════════════════════════════════"
            echo "  物理拓扑"; echo "════════════════════════════════════════"
            echo ""
            fabric_viz
            read -p "按回车继续..."
            ;;
    esac
}

# 双模式路径探寻（Phase 4 使用）
do_path_find() {
    read -p "目标服务器: " TARGET
    [ -z "$TARGET" ] && return

    echo ""
    echo "════════════════════════════════════════"
    echo "  选择连接模式"
    echo "════════════════════════════════════════"
    echo ""
    local result
    result=$(_path_json "$HOSTNAME" "$TARGET")
    local ok
    ok=$(echo "$result" | python3 -c "import json,sys;print(json.load(sys.stdin).get('success',False))" 2>/dev/null)

    if [ "$ok" != "True" ]; then
        echo "  当前节点 ($HOSTNAME) 到 $TARGET 不可达"
        return 1
    fi

    local path_str hops
    path_str=$(echo "$result" | python3 -c "import json,sys;print(' → '.join(json.load(sys.stdin)['path']))" 2>/dev/null)
    hops=$(echo "$result" | python3 -c "import json,sys;print(json.load(sys.stdin)['hops'])" 2>/dev/null)
    echo "  路径: $path_str ($hops 跳)"
    echo ""
    echo "  [1] ProxyJump 模式 — 一行命令，需本机公钥在全部节点"
    echo "  [2] 嵌套 SSH 模式 — 每节点只存邻居公钥"
    read -p "  选择 [1]: " MODE; MODE=${MODE:-1}

    case $MODE in
        1) proxyjump_cmd "$HOSTNAME" "$TARGET" ;;
        2) chain_ssh_cmd "$HOSTNAME" "$TARGET" ;;
    esac
}
