#!/bin/bash
# ========================================
set -o pipefail
# shellcheck disable=SC2034
# Phase 3 — Fabric 管理中心
# 查看、维护、健康检查所有物理连接
# ========================================

do_fabric_menu() {
    while true; do
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║  Fabric 管理中心                       ║"
        echo "╠════════════════════════════════════════╣"
        echo "║  [1] Fabric 列表  — 所有逻辑边+物理状态 ║"
        echo "║  [2] 维持命令    — 所有隧道维持命令    ║"
        echo "║  [3] 健康检查    — 逐 fabric 检测连通性 ║"
        echo "║  [4] 教程生成    — 基于 fabric 生成指南 ║"
        echo "║  [5] 配置备份    — 管理备份文件        ║"
        echo "║  [B] 返回主菜单                        ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        read -p "选择: " C
        case $C in
            1) do_fabric_list ;;
            2) do_fabric_cmds ;;
            3) do_fabric_health ;;
            4) do_fabric_tutorial ;;
            5) do_backup_menu ;;
            b|B) return ;;
        esac
    done
}

do_fabric_list() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  Fabric 列表"
    echo "════════════════════════════════════════"
    echo ""
    if [ ! -f "$FABRIC_PATH" ] || [ "$(python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d.get('fabrics',{})))" < "$FABRIC_PATH")" = "0" ]; then
        echo "  (无 Fabric)"
        echo ""
        echo "  提示: 通过「Phase 2 → 递归建边」创建 Fabric"
        return
    fi
    fabric_list
}

do_fabric_cmds() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  维持命令"
    echo "════════════════════════════════════════"
    echo ""
    if [ ! -f "$FABRIC_PATH" ] || [ "$(python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d.get('fabrics',{})))" < "$FABRIC_PATH")" = "0" ]; then
        echo "  (无 Fabric)"
        return
    fi
    fabric_cmds
    echo "提示: 维持者需持久化运行（推荐 autossh 或 systemd）"
}

do_fabric_health() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  健康检查"
    echo "════════════════════════════════════════"
    echo ""

    if [ ! -f "$FABRIC_PATH" ] || [ "$(python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d.get('fabrics',{})))" < "$FABRIC_PATH")" = "0" ]; then
        echo "  (无 Fabric)"
        return
    fi

    # 列出所有 fabric 供选择
    echo "现有 Fabric:"
    fabric_list
    echo ""
    echo "  [A] 检查全部"
    echo "  [回车] 返回"
    read -p "选择 Fabric ID 或 [A]: " FID

    if [ -z "$FID" ]; then
        return
    fi

    if [ "$FID" = "A" ] || [ "$FID" = "a" ]; then
        local all_fids
        all_fids=$(python3 -c "
import json,sys
d = json.load(sys.stdin)
for fid in d.get('fabrics', {}):
    print(fid)
" < "$FABRIC_PATH")
        for fid in $all_fids; do
            echo ""
            echo "── $fid ──"
            fabric_health "$fid"
        done
    else
        fabric_health "$FID"
    fi
}

do_fabric_tutorial() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  教程生成"
    echo "════════════════════════════════════════"
    echo ""

    if [ ! -f "$FABRIC_PATH" ] || [ "$(python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d.get('fabrics',{})))" < "$FABRIC_PATH")" = "0" ]; then
        echo "  (无 Fabric)"
        echo ""
        echo "  使用旧格式教程生成..."
        local OUTPUT="$HOME/tunnel-mesh-tutorial.md"
        generate_tutorial > "$OUTPUT"
        echo "  ✓ 教程已生成: $OUTPUT"
        return
    fi

    fabric_list
    echo ""
    echo "  [A] 生成全部 Fabric 教程"
    read -p "选择 Fabric ID 或 [A]: " FID

    local OUTPUT="$HOME/tunnel-mesh-tutorial.md"
    {
        echo "# Tunnel Mesh 教程"
        echo ""
        echo "生成时间: $(date)"
        echo ""

        if [ "$FID" = "A" ] || [ "$FID" = "a" ]; then
            local all_fids
            all_fids=$(python3 -c "
import json,sys
d = json.load(sys.stdin)
for fid in d.get('fabrics', {}):
    print(fid)
" < "$FABRIC_PATH")
            for fid in $all_fids; do
                echo "## Fabric: $fid"
                echo ""
                fabric_get "$fid" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if 'error' in d:
    print(f\"  ❌ {d['error']}\")
    sys.exit(0)
print(f\"逻辑边: {d.get('logical_edge','?')}\")
print(f\"端口: {d.get('port','?')}\")
print(f\"状态: {d.get('status','?')}\")
print()
print('### 物理跳')
for h in d.get('hops', []):
    print(f\"  {h['seq']}: {h['from']} → {h['to']} ({h['type']}) 端口:{h.get('port','?')}\")
    if h.get('cmd'):
        print(f\"  命令: {h['cmd']}\")
print()
print('### 维持者')
for m in d.get('maintainers', []):
    print(f\"  {m['node']} [{m.get('persist','?')}]: {m.get('cmd','?')}\")
print()
"
            done
        elif [ -n "$FID" ]; then
            echo "## Fabric: $FID"
            echo ""
            fabric_get "$FID" | python3 -c "
import json, sys
d = json.load(sys.stdin)
if 'error' in d:
    print(f\"  ❌ {d['error']}\")
    sys.exit(0)
print(f\"逻辑边: {d.get('logical_edge','?')}\")
print(f\"端口: {d.get('port','?')}\")
print(f\"状态: {d.get('status','?')}\")
print()
print('### 物理跳')
for h in d.get('hops', []):
    print(f\"  {h['seq']}: {h['from']} → {h['to']} ({h['type']}) 端口:{h.get('port','?')}\")
    if h.get('cmd'):
        print(f\"  命令: {h['cmd']}\")
print()
print('### 维持者')
for m in d.get('maintainers', []):
    print(f\"  {m['node']} [{m.get('persist','?')}]: {m.get('cmd','?')}\")
print()
"
        fi
    } > "$OUTPUT"

    echo ""
    echo "  ✓ 教程已生成: $OUTPUT"
}

do_backup_menu() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  配置备份"
    echo "════════════════════════════════════════"
    echo ""
    echo "config.json 备份:"
    ls -t "$CONFIG_DIR"/config.json.bak.* 2>/dev/null | head -10 | while read f; do
        echo "  $(basename "$f")  ($(wc -c < "$f" 2>/dev/null || echo '?') bytes)"
    done
    echo ""
    echo "fabric.json 备份:"
    ls -t "$CONFIG_DIR"/fabric.json.bak.* 2>/dev/null | head -10 | while read f; do
        echo "  $(basename "$f")  ($(wc -c < "$f" 2>/dev/null || echo '?') bytes)"
    done
    echo ""
    echo "  [R] 恢复 config.json"
    echo "  [回车] 返回"
    read -p "选择: " BC
    case $BC in
        r|R)
            read -p "输入要恢复的备份文件名: " BAKFILE
            if [ -n "$BAKFILE" ] && [ -f "$CONFIG_DIR/$BAKFILE" ]; then
                cp "$CONFIG_FILE" "$CONFIG_DIR/config.json.bak.before-recover-$(date +%Y%m%d-%H%M%S)"
                cp "$CONFIG_DIR/$BAKFILE" "$CONFIG_FILE"
                CONFIG=$(config_load)
                CONFIG_PORT_NEXT=$(config_get ports.next 2>/dev/null || echo 2201)
                echo "✓ 已恢复配置"
            elif [ -n "$BAKFILE" ]; then
                echo "❌ 文件不存在"
            fi
            ;;
    esac
}
