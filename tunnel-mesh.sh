#!/bin/bash
# ========================================
# Tunnel Mesh v2 - 统一配置脚本
# 用法: bash tunnel-mesh.sh
# ========================================
set -e

CONFIG_DIR="$HOME/.tunnel-mesh"
CONFIG_FILE="$CONFIG_DIR/config.json"

# ── 配置读写 ──
config_load() {
    mkdir -p "$CONFIG_DIR"
    [ -f "$CONFIG_FILE" ] && cat "$CONFIG_FILE" || echo '{"servers":{},"contracts":[],"ports":{"used":[],"next":2201}}'
}

config_save() {
    mkdir -p "$CONFIG_DIR"
    echo "$1" > "$CONFIG_FILE"
}

# ── 三层端口检查 ──
port_is_free() {
    local port=$1

    # 1. 工具自身配置
    echo "$CONFIG" | grep -q "\"$port\"" 2>/dev/null && return 1

    # 2. SSH config
    grep -q "Port $port" ~/.ssh/config 2>/dev/null && return 1

    # 3. 系统监听端口
    ss -tlnp 2>/dev/null | grep -q ":$port " && return 1
    netstat -tlnp 2>/dev/null | grep -q ":$port " && return 1

    return 0
}

port_allocate() {
    local port=${CONFIG_PORT_NEXT:-2201}
    while ! port_is_free $port; do
        port=$((port + 1))
        [ $port -gt 2299 ] && { echo "2201"; return; }
    done
    echo $port
}

# ── 身份检测 ──
detect_identity() {
    HOSTNAME=$(hostname)
    IP=$(hostname -I | awk '{print $1}')
    PORT=$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    [ -z "$PORT" ] && PORT=22
    USER=$(whoami)

    if [ -f ~/.ssh/id_ed25519.pub ]; then
        PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    elif [ -f ~/.ssh/id_rsa.pub ]; then
        PUBKEY=$(cat ~/.ssh/id_rsa.pub)
    else
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "${HOSTNAME}@tunnel" >/dev/null 2>&1
        PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
    fi
    FINGERPRINT=$(echo "$PUBKEY" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
}

# ── 全局状态 ──
CONFIG=$(config_load)
CONFIG_PORT_NEXT=$(echo "$CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ports']['next'])" 2>/dev/null || echo 2201)

detect_identity

# ══════════════════════════════════════════════════════════
# 导出身份卡
# ══════════════════════════════════════════════════════════
do_export() {
    # 检查是否已导出过
    if echo "$CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print('$HOSTNAME' in d['servers'])" 2>/dev/null | grep -q True; then
        echo ""
        echo "此服务器已导出过身份卡。"
        read -p "重新导出？[y/N]: " RE
        [ "$RE" != "y" ] && [ "$RE" != "Y" ] && return
    fi

    # 保存到配置
    CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
d['servers']['$HOSTNAME']={
    'name':'$HOSTNAME','ip':'$IP','port':$PORT,'user':'$USER',
    'fingerprint':'${FINGERPRINT:-unknown}',
    'exported_at':'$(date -Iseconds)'
}
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  身份已保存                             ║"
    echo "╠════════════════════════════════════════╣"
    echo "║  $HOSTNAME ($IP:$PORT)"
    [ -n "$FINGERPRINT" ] && echo "║  指纹: $FINGERPRINT"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "════════════════════════════════════════"
    echo "  身份卡（复制给对方）"
    echo "════════════════════════════════════════"
    echo ""
    echo "===IDENTITY==="
    echo "NAME=$HOSTNAME"
    echo "IP=$IP"
    echo "PORT=$PORT"
    echo "USER=$USER"
    echo "PUBKEY=$PUBKEY"
    echo "FINGERPRINT=${FINGERPRINT:-unknown}"
    echo "===END==="
    echo ""
}

# ══════════════════════════════════════════════════════════
# 导入身份卡
# ══════════════════════════════════════════════════════════
do_import() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  粘贴对方身份卡（含 === 行）            ║"
    echo "║  粘贴后 Ctrl+D 回车                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    IDENTITY=$(cat)

    PEER_NAME=$(echo "$IDENTITY" | grep "^NAME=" | cut -d= -f2)
    PEER_IP=$(echo "$IDENTITY" | grep "^IP=" | cut -d= -f2)
    PEER_PORT=$(echo "$IDENTITY" | grep "^PORT=" | cut -d= -f2)
    PEER_USER=$(echo "$IDENTITY" | grep "^USER=" | cut -d= -f2)
    PEER_PUBKEY=$(echo "$IDENTITY" | grep "^PUBKEY=" | cut -d= -f2-)
    PEER_FP=$(echo "$IDENTITY" | grep "^FINGERPRINT=" | cut -d= -f2)

    [ -z "$PEER_NAME" ] && { echo "❌ 无效身份卡"; return; }

    # ── 重复检测 ──
    if echo "$CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); cs=d.get('contracts',[]); matches=[c for c in cs if c.get('servant')=='$PEER_NAME']; print(len(matches))" 2>/dev/null | grep -qv "^0$"; then
        echo ""
        echo "⚠ $PEER_NAME 已有契约存在"
        read -p "  是否覆盖？[y/N]: " OV
        [ "$OV" != "y" ] && [ "$OV" != "Y" ] && { echo "已取消"; return; }
        # 删除旧契约
        CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
d['contracts']=[c for c in d.get('contracts',[]) if c.get('servant')!='$PEER_NAME']
print(json.dumps(d,indent=2))
")
    fi

    # ── 保存对方信息 ──
    CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
d['servers']['$PEER_NAME']={
    'name':'$PEER_NAME','ip':'$PEER_IP','port':${PEER_PORT:-22},'user':'${PEER_USER:-root}',
    'fingerprint':'${PEER_FP:-unknown}',
    'imported_at':'$(date -Iseconds)'
}
print(json.dumps(d,indent=2))
")
    config_save "$CONFIG"

    echo "对方: $PEER_NAME ($PEER_IP:$PEER_PORT)"

    # ── 公钥 ──
    if [ -n "$PEER_PUBKEY" ] && [ "$PEER_PUBKEY" != "PUBKEY=" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if ! grep -qF "$PEER_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "$PEER_PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "✓ 公钥已添加"
        fi
    fi

    # ── 可达性 ──
    echo ""
    echo "你能直接连到 $PEER_NAME ($PEER_IP:$PEER_PORT) 吗？"
    echo "  [1] 能 → 直接SSH"
    echo "  [2] 不能 → 需要反向隧道"
    read -p "选择: " REACH
    REACH=${REACH:-2}

    if [ "$REACH" = "1" ]; then
        mkdir -p ~/.ssh
        [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null

        if grep -q "Host $PEER_NAME" ~/.ssh/config 2>/dev/null; then
            echo "  SSH config 已存在 Host $PEER_NAME，跳过"
        else
            cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $PEER_NAME（直连）
Host $PEER_NAME
    HostName $PEER_IP
    Port ${PEER_PORT:-22}
    User ${PEER_USER:-root}
    StrictHostKeyChecking no
EOF
            chmod 600 ~/.ssh/config
            echo "✓ SSH config 已添加（直连）"
        fi

        # 保存契约
        CONTRACT_ID="${HOSTNAME}→${PEER_NAME}"
        CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
d['contracts'].append({
    'id':'$CONTRACT_ID','master':'$HOSTNAME','servant':'$PEER_NAME',
    'type':'direct','status':'active','created':'$(date -Iseconds)'
})
print(json.dumps(d,indent=2))
")
        config_save "$CONFIG"

        echo ""
        echo "✓ 契约已建立！ssh $PEER_NAME"

    else
        # ── 反向隧道 ──
        echo ""
        echo "反向隧道需要一台维持者持续运行 SSH。"

        # 检测自己能否连对方
        CAN_REACH=0
        timeout 3 bash -c "echo >/dev/tcp/${PEER_IP}/${PEER_PORT}" 2>/dev/null && CAN_REACH=1

        echo ""
        if [ $CAN_REACH -eq 1 ]; then
            echo "你能直连对方 ✓"
            echo "  [1] 我自己维持隧道"
        else
            echo "你不能直连对方 ✗（端口不可达）"
            echo "  [1] 我自己维持（不可行）"
        fi
        echo "  [2] 外部机器维持（如 Windows）"
        read -p "选择: " MAINTAINER
        MAINTAINER=${MAINTAINER:-2}

        [ "$MAINTAINER" = "1" ] && [ $CAN_REACH -eq 0 ] && { echo "⚠ 不可行，自动选 [2]"; MAINTAINER=2; }

        # 三层端口分配
        TUNNEL_PORT=$(port_allocate)
        read -p "隧道端口 [$TUNNEL_PORT]: " INPUT_PORT
        TUNNEL_PORT=${INPUT_PORT:-$TUNNEL_PORT}

        CONFIG_PORT_NEXT=$((TUNNEL_PORT + 1))
        CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
d['ports']['used'].append($TUNNEL_PORT)
d['ports']['next']=${CONFIG_PORT_NEXT}
print(json.dumps(d,indent=2))
")
        config_save "$CONFIG"

        if [ "$MAINTAINER" = "1" ]; then
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:localhost:${PORT} ${PEER_USER}@${PEER_IP} -p ${PEER_PORT}"
            echo ""
            echo "维持命令: $TUNNEL_CMD"
            echo "对方访问: ssh -p $TUNNEL_PORT $USER@$IP"
        else
            TUNNEL_CMD="ssh -R ${TUNNEL_PORT}:${PEER_IP}:${PEER_PORT} ${USER}@${IP} -p ${PORT}"

            # 本机 SSH config
            mkdir -p ~/.ssh
            [ -f ~/.ssh/config ] && cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null

            if ! grep -q "Host $PEER_NAME" ~/.ssh/config 2>/dev/null; then
                cat >> ~/.ssh/config << EOF

# Tunnel Mesh - $PEER_NAME（反向隧道:${TUNNEL_PORT}）
Host $PEER_NAME
    HostName localhost
    Port $TUNNEL_PORT
    User ${PEER_USER:-root}
    StrictHostKeyChecking no
    HostKeyAlias $PEER_NAME
EOF
                chmod 600 ~/.ssh/config
            fi

            echo ""
            echo "════════════════════════════════════════"
            echo "  契约建立完成！"
            echo "════════════════════════════════════════"
            echo ""
            echo "  ┌─────────┐       ┌──────────┐       ┌─────────┐"
            echo "  │$HOSTNAME│ ←─── │  维持者   │ ───→ │$PEER_NAME│"
            echo "  │ :$TUNNEL_PORT  │  隧道  │  (桥)    │       │ :$PEER_PORT │"
            echo "  └─────────┘       └──────────┘       └─────────┘"
            echo ""
            echo "  访问: ssh $PEER_NAME"
            echo "  隧道命令（发给维持者）:"
            echo "  $TUNNEL_CMD"
            echo ""
            echo "  维持者执行: windows-contract.bat → [1]导入"
            echo "════════════════════════════════════════"
        fi

        # 保存契约
        CONTRACT_ID="${HOSTNAME}→${PEER_NAME}"
        CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
d['contracts'].append({
    'id':'$CONTRACT_ID','master':'$HOSTNAME','servant':'$PEER_NAME',
    'type':'reverse','tunnel_port':$TUNNEL_PORT,
    'tunnel_cmd':'$TUNNEL_CMD','maintainer':'${MAINTAINER}',
    'status':'active','created':'$(date -Iseconds)'
})
print(json.dumps(d,indent=2))
")
        config_save "$CONFIG"
    fi
}

# ══════════════════════════════════════════════════════════
# 审视契约
# ══════════════════════════════════════════════════════════
do_status() {
    CONFIG=$(config_load)
    echo ""
    echo "════════════════════════════════════════"
    echo "  契约大厅 — $HOSTNAME"
    echo "════════════════════════════════════════"
    echo ""

    COUNT=$(echo "$CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('contracts',[])))" 2>/dev/null)
    echo "已知服务器:"

    echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for name, s in d.get('servers',{}).items():
    print(f\"  {s['name']:<15} {s['ip']}:{s['port']}   {s.get('fingerprint','')[:12]}\")
" 2>/dev/null

    echo ""
    echo "契约列表 ($COUNT):"

    echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for c in d.get('contracts',[]):
    t=c.get('type','?')
    port=c.get('tunnel_port','-')
    print(f\"  {c['id']:<25} {t:<10} 端口:{port}\")
" 2>/dev/null

    echo ""
    echo "已用端口: $(echo "$CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(map(str,d['ports']['used'])))" 2>/dev/null)"
}

# ══════════════════════════════════════════════════════════
# 废契
# ══════════════════════════════════════════════════════════
do_remove() {
    CONFIG=$(config_load)
    echo ""
    echo "现有契约:"
    echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for i,c in enumerate(d.get('contracts',[])):
    print(f\"  [{i}] {c['id']}\")
" 2>/dev/null

    read -p "输入编号删除: " IDX
    [ -z "$IDX" ] && return

    CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
idx=int('$IDX')
if 0<=idx<len(d.get('contracts',[])):
    c=d['contracts'].pop(idx)
    if c.get('tunnel_port'):
        if c['tunnel_port'] in d['ports']['used']:
            d['ports']['used'].remove(c['tunnel_port'])
    print(f\"✓ 已删除: {c['id']}\")
    print(json.dumps(d,indent=2))
" 2>/dev/null)
    config_save "$CONFIG"
    echo "✓ 已删除"
}

# ══════════════════════════════════════════════════════════
# 配置向导
# ══════════════════════════════════════════════════════════
do_wizard() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           双向连接配置向导                        ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║                                                  ║"
    echo "║  操作步骤:                                        ║"
    echo "║  ① 两台服务器各自导出身份卡                       ║"
    echo "║  ② 各自导入对方的身份卡                           ║"
    echo "║  ③ Windows 导入两条隧道命令                       ║"
    echo "║                                                  ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "你要做什么？"
    echo "  [1] 导出本机身份卡"
    echo "  [2] 导入对方身份卡"
    echo "  [3] 查看教程"
    read -p "选择: " W
    case $W in 1) do_export ;; 2) do_import ;; 3)
        echo ""
        echo "完整流程："
        echo "  ① 服务器A: bash tunnel-mesh.sh → [1]导出 → 复制身份卡"
        echo "  ② 服务器B: bash tunnel-mesh.sh → [2]导入 → 粘贴A的身份卡"
        echo "             → 选择触达方式 → 自动生成隧道命令"
        echo "             → [1]导出 → 复制B的身份卡"
        echo "  ③ 服务器A: bash tunnel-mesh.sh → [2]导入 → 粘贴B的身份卡"
        echo "  ④ Windows: windows-contract.bat → [1]导入 ×2"
    esac
}

# ══════════════════════════════════════════════════════════
# 配置恢复 - 从 config.json 重建 SSH config
# ══════════════════════════════════════════════════════════
do_recover() {
    CONFIG=$(config_load)
    echo ""
    echo "════════════════════════════════════════"
    echo "  重新生成 SSH config"
    echo "════════════════════════════════════════"
    echo ""
    echo "从配置中恢复所有连接..."
    echo ""

    echo "$CONFIG" | python3 -c "
import json,sys,os
d=json.load(sys.stdin)
for c in d.get('contracts',[]):
    name=c['servant']
    t=c.get('type','?')
    
    if t=='direct':
        s=d['servers'].get(name,{})
        print(f'Host {name}')
        print(f'    HostName {s.get(\"ip\",\"?\")}')
        print(f'    Port {s.get(\"port\",22)}')
        print(f'    User {s.get(\"user\",\"root\")}')
        print(f'    StrictHostKeyChecking no')
        print()
    elif t=='reverse':
        print(f'Host {name}')
        print(f'    HostName localhost')
        print(f'    Port {c[\"tunnel_port\"]}')
        s=d['servers'].get(name,{})
        print(f'    User {s.get(\"user\",\"root\")}')
        print(f'    StrictHostKeyChecking no')
        print(f'    HostKeyAlias {name}')
        print()
        if c.get('tunnel_cmd'):
            print(f'# 隧道命令: {c[\"tunnel_cmd\"]}')
            print()
" 2>/dev/null

    echo ""
    echo "将上述内容添加到 ~/.ssh/config 即可。"
    read -p "是否自动添加？[y/N]: " ADD
    [ "$ADD" = "y" ] || [ "$ADD" = "Y" ] || return

    CONFIG=$(config_load)
    cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null

    echo "$CONFIG" | python3 -c "
import json,sys,os
d=json.load(sys.stdin)
ssh=os.path.expanduser('~/.ssh/config')
with open(ssh,'a') as f:
    f.write('\n# Tunnel Mesh - 配置恢复\\n')
    for c in d.get('contracts',[]):
        name=c['servant']
        t=c.get('type','?')
        if t=='direct':
            s=d['servers'].get(name,{})
            f.write(f'Host {name}\\n    HostName {s.get(\"ip\",\"?\")}\\n    Port {s.get(\"port\",22)}\\n    User {s.get(\"user\",\"root\")}\\n    StrictHostKeyChecking no\\n')
        elif t=='reverse':
            f.write(f'Host {name}\\n    HostName localhost\\n    Port {c[\"tunnel_port\"]}\\n')
            s=d['servers'].get(name,{})
            f.write(f'    User {s.get(\"user\",\"root\")}\\n    StrictHostKeyChecking no\\n    HostKeyAlias {name}\\n')
" 2>/dev/null

    chmod 600 ~/.ssh/config 2>/dev/null
    echo "✓ SSH config 已恢复"
}

# ══════════════════════════════════════════════════════════
# 探寻路径 - 多跳路径查找
# ══════════════════════════════════════════════════════════
do_path() {
    CONFIG=$(config_load)
    echo ""
    echo "可到达的服务器:"
    echo "$CONFIG" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for name in d.get('servers',{}):
    print(f'  {name}')
" 2>/dev/null

    echo ""
    read -p "目标服务器: " TARGET
    [ -z "$TARGET" ] && return

    echo ""
    echo "计算路径: $HOSTNAME → $TARGET"

    # 调用 graph.py 计算最短路径
    python3 -c "
import json,sys
sys.path.insert(0,'$(dirname "$0")/scripts')
from graph import Graph

config=json.load(open('$HOME/.tunnel-mesh/config.json'))

g=Graph()
servers=config.get('servers',{})
for name in servers:
    g.add_vertex(name)

for c in config.get('contracts',[]):
    master=c['master']
    servant=c['servant']
    if master in servers and servant in servers:
        weight=1.5 if c.get('type')=='reverse' else 1.0
        g.add_edge(master,servant,weight)

path=g.shortest_path('$HOSTNAME','$TARGET')
if path:
    hops=len(path)-1
    weight=sum(g.edges[path[i]][path[i+1]] for i in range(hops) if path[i] in g.edges and path[i+1] in g.edges[path[i]])
    print(f'路径: {\" → \".join(path)}')
    print(f'跳数: {hops}')
    
    # 生成 ProxyJump 命令
    if hops>1:
        jumps=','.join(path[1:-1])
        print(f'连接: ssh -J {jumps} {path[-1]}')
    else:
        print(f'连接: ssh {path[-1]}')
else:
    print('不可达')
" 2>/dev/null || echo "  计算失败（graph.py 可能不兼容）"
}

# ══════════════════════════════════════════════════════════
# 主菜单
# ══════════════════════════════════════════════════════════
main_menu() {
    detect_identity
    CONFIG=$(config_load)
    CONFIG_PORT_NEXT=$(echo "$CONFIG" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['ports']['next'])" 2>/dev/null || echo 2201)

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     Tunnel Mesh  $HOSTNAME             ║"
    echo "╠════════════════════════════════════════╣"
    echo "║  $IP:$PORT                            ║"
    echo "╠════════════════════════════════════════╣"
    echo "║                                        ║"
    echo "║  [1] 导出身份卡（给别人）              ║"
    echo "║  [2] 导入身份卡（连接别人）            ║"
    echo "║  [3] 审视契约（查看所有连接）          ║"
    echo "║  [4] 废契（删除连接）                  ║"
    echo "║  [5] 配置向导                          ║"
    echo "║  [6] 探寻路径（多跳）                  ║"
    echo "║  [7] 恢复配置                          ║"
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
        q|Q) exit 0 ;;
    esac
}

# ── 入口 ──
case "${1:-menu}" in
    export) do_export ;;
    import) do_import ;;
    status) do_status ;;
    remove) do_remove ;;
    *) main_menu ;;
esac
