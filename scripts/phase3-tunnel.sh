#!/bin/bash
# phase3-tunnel.sh - 隧道管理 + 教程生成

do_tunnel_menu() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  隧道管理"
    echo "════════════════════════════════════════"
    echo ""
    edge_list
    echo ""
    echo "[C] 显示所有隧道命令（复制到 Windows）"
    echo "[T] 生成教程"
    read -p "选择: " C
    case $C in
        c|C) do_show_tunnel_cmds ;;
        t|T) do_generate_tutorial ;;
    esac
}

do_show_tunnel_cmds() {
    echo ""; echo "════════════════════════════════════════"
    echo "  隧道命令（复制到 Windows 导入）"
    echo "════════════════════════════════════════"; echo ""
    CONFIG=$(config_load)
    echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for e in d.get('edges',[]):
    if e.get('tunnel_cmd'):
        print(e['tunnel_cmd'])
        print()
" 2>/dev/null
}

do_generate_tutorial() {
    local OUTPUT="$HOME/tunnel-mesh-tutorial.md"
    CONFIG=$(config_load)
    {
        echo "# Tunnel Mesh 教程"
        echo ""
        echo "生成时间: $(date)"
        echo ""
        echo "## 拓扑图"
        echo ""
        echo "\`\`\`"
        echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for e in d.get('edges',[]):
    t=e.get('type','?')
    arrow='→'
    if t=='reverse': arrow='─隧道→'
    print(f\"  {e['from']} {arrow} {e['to']}  ({t})\")
"
        echo "\`\`\`"
        echo ""
        echo "## 操作步骤"
        echo ""

        local step=1
        echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for e in d.get('edges',[]):
    t=e.get('type','?')
    if t=='reverse':
        print(f\"STEP_{e['from']}_{e['to']}_{e.get('tunnel_cmd','')}_{e.get('tunnel_port','')}_{e.get('maintainer','')}\")
" | while IFS='_' read -r tag master servant cmd port maintainer; do
            [ "$tag" != "STEP" ] && continue
            echo "### Step $step: $master → $servant（反向隧道）"
            echo ""
            echo "在 **$master** 上 SSH config 已自动配置:"
            echo "\`\`\`"
            echo "Host $servant"
            echo "    HostName localhost"
            echo "    Port $port"
            echo "\`\`\`"
            echo ""
            if [ "$maintainer" = "2" ]; then
                echo "把以下命令发给 **维持者 (Windows)**:"
                echo "\`\`\`"
                echo "$cmd"
                echo "\`\`\`"
                echo ""
                echo "Windows: 双击 tunnel-mesh.bat → [1]导入 → 粘贴命令"
            else
                echo "在 **$servant** 上运行:"
                echo "\`\`\`"
                echo "$cmd"
                echo "\`\`\`"
            fi
            echo ""
            step=$((step+1))
        done

        echo "## 验证"
        echo ""
        echo "在 **$HOSTNAME** 上:"
        echo "\`\`\`bash"
        echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for e in d.get('edges',[]):
    print(f'ssh {e[\"to\"]} hostname')
"
        echo "\`\`\`"

    } > "$OUTPUT"

    echo ""; echo "✓ 教程已生成: $OUTPUT"
    echo "  可以翻页查看"; echo ""
}
