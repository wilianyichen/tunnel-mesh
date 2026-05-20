#!/bin/bash
# phase1-key.sh - 密钥阶段：生成/导出/部署

do_key_menu() {
    while true; do
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║  密钥管理 — Phase 1                    ║"
        echo "╠════════════════════════════════════════╣"
        echo "║  [1] 生成密钥 + 导出身份卡             ║"
        echo "║  [2] 部署公钥（粘贴别人的身份卡）      ║"
        echo "║  [3] 查看已部署的密钥                  ║"
        echo "║  [B] 返回主菜单                        ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        read -p "选择: " C
        case $C in
            1) do_key_generate ;;
            2) do_key_deploy ;;
            3) do_key_list ;;
            b|B) return ;;
        esac
        read -p "按回车继续..."
    done
}

do_key_generate() {
    show_identity
    echo ""
    echo "════════════════════════════════════════"
    echo "  身份卡（复制到其他服务器部署）"
    echo "════════════════════════════════════════"
    echo ""
    echo "===IDENTITY==="
    echo "NAME=$HOSTNAME"
    echo "IP=$IP"
    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "PUBLIC_IP=$PUBLIC_IP"
    echo "PORT=$PORT"
    echo "USER=$USER"
    echo "PUBKEY=$PUBKEY"
    echo "FINGERPRINT=${FINGERPRINT:-unknown}"
    echo "===END==="
    echo ""
    echo "📋 复制上面的身份卡"
    echo "   在其他服务器上: bash tunnel-mesh.sh key → [2]部署公钥"

    # 保存自身到图
    CONFIG=$(config_load)
    CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys;d=json.load(sys.stdin)
d['servers']['$HOSTNAME']={'name':'$HOSTNAME','ip':'$IP','port':$PORT,'user':'$USER','fingerprint':'${FINGERPRINT:-}','pubkey':'$PUBKEY','added':'$(date -Iseconds)'}
print(json.dumps(d,indent=2))
" 2>/dev/null)
    config_save "$CONFIG"
}

do_key_deploy() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  部署公钥                              ║"
    echo "║  粘贴别人的身份卡 → 公钥写入本机        ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "──────────────────────────────────────"
    echo "  粘贴身份卡（Ctrl+D 回车）"
    echo "──────────────────────────────────────"

    IDENTITY=$(cat)
    local name=$(echo "$IDENTITY" | grep "^NAME=" | cut -d= -f2)
    local ip=$(echo "$IDENTITY" | grep "^IP=" | cut -d= -f2)
    local port=$(echo "$IDENTITY" | grep "^PORT=" | cut -d= -f2)
    local user=$(echo "$IDENTITY" | grep "^USER=" | cut -d= -f2)
    local pubkey=$(echo "$IDENTITY" | grep "^PUBKEY=" | cut -d= -f2-)
    [ -z "$pubkey" ] || [ "$pubkey" = "PUBKEY=" ] && pubkey=$(echo "$IDENTITY" | grep -E "^ssh-")

    if [ -z "$name" ]; then echo "❌ 无效身份卡"; return; fi

    echo ""
    echo "  部署 $name ($ip) 的公钥..."

    if [ -n "$pubkey" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if grep -qF "$pubkey" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "  ✓ 已存在"
        else
            echo "$pubkey" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "  ✓ 已部署 — $name 可以免密登录本机"
        fi
    fi

    # 保存到图
    CONFIG=$(config_load)
    CONFIG=$(echo "$CONFIG" | python3 -c "
import json,sys;d=json.load(sys.stdin)
d['servers']['$name']={'name':'$name','ip':'${ip:-?}','port':${port:-22},'user':'${user:-root},'pubkey':'${pubkey:-}','added':'$(date -Iseconds)'}
print(json.dumps(d,indent=2))
" 2>/dev/null)
    config_save "$CONFIG"
}

do_key_list() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  已部署的密钥（本机 authorized_keys）"
    echo "════════════════════════════════════════"
    echo ""
    if [ -f ~/.ssh/authorized_keys ]; then
        while IFS= read -r line; do
            echo "  ${line:0:80}..."
        done < ~/.ssh/authorized_keys
    else
        echo "  暂无"
    fi
}
