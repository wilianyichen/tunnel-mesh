#!/bin/bash
# phase1-key.sh - 密钥阶段：生成/导出/部署
set -o pipefail

do_key_menu() {
    while true; do
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║  密钥管理 — Phase 1                    ║"
        echo "╠════════════════════════════════════════╣"
        echo "║  [1] 生成密钥 + 导出身份卡             ║"
        echo "║  [2] 部署公钥（粘贴别人的身份卡）      ║"
        echo "║  [3] 批量导入身份卡                    ║"
        echo "║  [4] 查看已部署的密钥                  ║"
        echo "║  [B] 返回主菜单                        ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        read -p "选择: " C
        case $C in
            1) do_key_generate ;;
            2) do_key_deploy ;;
            3) do_key_batch_import ;;
            4) do_key_list ;;
            b|B) return ;;
        esac
        read -p "按回车继续..."
    done
}

do_key_generate() {
    # 无密钥时自动生成
    if [ -z "$PUBKEY" ]; then
        echo ""
        echo "  未检测到 SSH 密钥，正在生成..."
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "${HOSTNAME}@tunnel" || { echo "❌ 密钥生成失败"; return 1; }
        PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
        FINGERPRINT=$(echo "$PUBKEY" | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
        echo "  ✓ 密钥已生成: ~/.ssh/id_ed25519"
    fi
    show_identity
    echo ""
    echo "════════════════════════════════════════"
    echo "  身份卡（复制到其他服务器部署）"
    echo "════════════════════════════════════════"
    echo ""
    # 生成校验和
    local raw="NAME=$HOSTNAME\nIP=$IP\nPORT=$PORT\nUSER=$USER\nPUBKEY=$PUBKEY\nFINGERPRINT=${FINGERPRINT:-unknown}"
    local checksum
    checksum=$(echo -e "$raw" | sha256sum | awk '{print $1}')
    echo "===IDENTITY v1==="
    echo -e "$raw"
    [ -n "$PUBLIC_IP" ] && [ "$PUBLIC_IP" != "$IP" ] && echo "PUBLIC_IP=$PUBLIC_IP"
    echo "CHECKSUM=sha256:$checksum"
    echo "===END==="
    echo ""
    echo "📋 复制上面的身份卡"
    echo "   在其他服务器上: bash tunnel-mesh.sh key → [2]部署公钥"

    # 保存自身到图
    server_add "$HOSTNAME" "$IP" "$PORT" "$USER" "${FINGERPRINT:-}" "$PUBKEY"
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

    if ! parse_identity_card; then return; fi

    echo ""
    echo "  部署 $_ID_NAME ($_ID_IP) 的公钥..."

    if [ -n "$_ID_PUBKEY" ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if grep -qF "$_ID_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
            echo "  ✓ 已存在"
        else
            echo "$_ID_PUBKEY" >> ~/.ssh/authorized_keys
            chmod 600 ~/.ssh/authorized_keys
            echo "  ✓ 已部署 — $_ID_NAME 可以免密登录本机"
        fi
    fi

    # 保存到图
    server_add "$_ID_NAME" "$_ID_IP" "${_ID_PORT:-22}" "${_ID_USER:-root}" "" "${_ID_PUBKEY:-}"
}

# 批量导入：一次粘贴多张身份卡（===IDENTITY v1=== 分隔）
do_key_batch_import() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  批量导入身份卡                       ║"
    echo "║  粘贴所有身份卡（Ctrl+D 结束）         ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # 读取全部 stdin
    local all_cards
    all_cards=$(cat)

    # 按 ===IDENTITY v1=== 分割
    local count=0
    local card
    local IFS_saved="$IFS"
    # 用 awk 按分隔符切分身份卡
    while IFS= read -r card; do
        [ -z "$(echo "$card" | tr -d '[:space:]')" ] && continue
        # 提取 NAME= 行判断是否有效
        local card_name
        card_name=$(echo "$card" | grep "^NAME=" | head -1 | cut -d= -f2)
        [ -z "$card_name" ] && continue

        # 跳过本机自身
        if [ "$card_name" = "$HOSTNAME" ]; then
            echo "  跳过本机: $card_name"
            continue
        fi

        echo "  部署 $card_name ..."
        if echo "$card" | parse_identity_card; then
            if [ -n "$_ID_PUBKEY" ]; then
                mkdir -p ~/.ssh && chmod 700 ~/.ssh
                if ! grep -qF "$_ID_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null; then
                    echo "$_ID_PUBKEY" >> ~/.ssh/authorized_keys
                    chmod 600 ~/.ssh/authorized_keys
                fi
            fi
            server_add "$_ID_NAME" "$_ID_IP" "${_ID_PORT:-22}" "${_ID_USER:-root}" "" "${_ID_PUBKEY:-}"
            count=$((count + 1))
            echo "  ✓ $card_name 已导入"
        else
            echo "  ❌ $card_name 导入失败"
        fi
        echo ""
    done < <(echo "$all_cards" | awk '
        /^===IDENTITY v1===$/ { card=""; next }
        /^===END===$/ { print card; next }
        { card = card $0 "\n" }
    ')

    echo "──────────────────────────────────────"
    echo "  共导入 $count 台服务器"
}

do_key_batch_import_stdin() {
    # --cmd import 专用：直接从 stdin 读取，无交互提示
    local all_cards count=0 card card_name
    all_cards=$(cat)
    while IFS= read -r card; do
        [ -z "$(echo "$card" | tr -d '[:space:]')" ] && continue
        card_name=$(echo "$card" | grep "^NAME=" | head -1 | cut -d= -f2)
        [ -z "$card_name" ] && continue
        if echo "$card" | parse_identity_card 2>/dev/null; then
            if [ -n "$_ID_PUBKEY" ]; then
                mkdir -p ~/.ssh && chmod 700 ~/.ssh
                grep -qF "$_ID_PUBKEY" ~/.ssh/authorized_keys 2>/dev/null || \
                    echo "$_ID_PUBKEY" >> ~/.ssh/authorized_keys
                chmod 600 ~/.ssh/authorized_keys 2>/dev/null
            fi
            server_add "$_ID_NAME" "$_ID_IP" "${_ID_PORT:-22}" "${_ID_USER:-root}" "" "${_ID_PUBKEY:-}" 2>/dev/null
            count=$((count + 1))
        fi
    done < <(echo "$all_cards" | awk '
        /^===IDENTITY v1===$/ { card=""; next }
        /^===END===$/ { print card; next }
        { card = card $0 "\n" }
    ')
    echo "✓ 导入完成: $count 台服务器"
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
