#!/bin/bash
# ssh-config.sh - 管理 ~/.ssh/config 中的服务器连接
set -o pipefail

do_ssh_config() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════════════╗"
        echo "║  SSH Config 管理                                 ║"
        echo "╠══════════════════════════════════════════════════╣"
        echo "║                                                  ║"
        echo "║  [1] 列出所有服务器                              ║"
        echo "║  [2] 添加新服务器                                ║"
        echo "║  [3] 删除服务器                                  ║"
        echo "║  [4] 测试连接                                    ║"
        echo "║  [B] 返回主菜单                                  ║"
        echo "║                                                  ║"
        echo "╚══════════════════════════════════════════════════╝"
        echo ""
        read -p "选择: " C
        case $C in
            1) ssh_list ;;
            2) ssh_add ;;
            3) ssh_remove ;;
            4) ssh_test ;;
            b|B) return ;;
        esac
    done
}

ssh_list() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  SSH Config 服务器列表"
    echo "════════════════════════════════════════"

    if [ ! -f ~/.ssh/config ]; then
        echo ""
        echo "  暂无 SSH config 文件"
        echo "  创建: touch ~/.ssh/config"
        return
    fi

    echo ""
    printf "  %-20s %-30s %s\n" "名称" "地址" "用户"
    echo "  ──────────────────────────────────────────────────"

    local host="" hostname="" port="" user=""
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//')
        case "$line" in
            "Host "*)
                [ -n "$host" ] && printf "  %-20s %-30s %s\n" "$host" "${hostname}:${port:-22}" "${user:-root}"
                host=$(echo "$line" | cut -d' ' -f2)
                hostname=""; port=""; user=""
                ;;
            "HostName "*) hostname=$(echo "$line" | awk '{print $2}') ;;
            "Port "*) port=$(echo "$line" | awk '{print $2}') ;;
            "User "*) user=$(echo "$line" | awk '{print $2}') ;;
        esac
    done < ~/.ssh/config
    [ -n "$host" ] && printf "  %-20s %-30s %s\n" "$host" "${hostname}:${port:-22}" "${user:-root}"

    echo ""
    echo "════════════════════════════════════════"
}

ssh_add() {
    echo ""
    echo "════════════════════════════════════════"
    echo "  添加新服务器"
    echo "════════════════════════════════════════"
    echo ""
    read -p "名称（如 my-server）: " NAME
    [ -z "$NAME" ] && return
    read -p "IP 地址: " IP
    [ -z "$IP" ] && return
    read -p "SSH 端口 [22]: " PORT; PORT=${PORT:-22}
    read -p "用户名 [root]: " USER; USER=${USER:-root}

    if grep -q "^Host $NAME\$" ~/.ssh/config 2>/dev/null; then
        echo "⚠ $NAME 已存在"
        read -p "覆盖？[y/N]: " OV
        [ "$OV" != "y" ] && [ "$OV" != "Y" ] && return
        ssh_config_remove_host "$NAME"
    fi

    {
        echo ""
        echo "Host $NAME"
        echo "    HostName $IP"
        echo "    Port $PORT"
        echo "    User $USER"
        echo "    StrictHostKeyChecking no"
    } >> ~/.ssh/config

    chmod 600 ~/.ssh/config 2>/dev/null
    echo ""
    echo "✓ 已添加: $NAME ($IP:$PORT)"
    echo "  ssh $NAME"
}

ssh_remove() {
    ssh_list
    echo ""
    read -p "输入要删除的名称: " NAME
    [ -z "$NAME" ] && return

    if ! grep -q "^Host $NAME\$" ~/.ssh/config 2>/dev/null; then
        echo "未找到: $NAME"
        return
    fi

    read -p "确认删除 $NAME？[y/N]: " CONFIRM
    [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && return

    cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d%H%M%S) 2>/dev/null

    awk -v host="$NAME" '
    BEGIN { skip = 0 }
    /^Host / {
        if ($2 == host) { skip = 1; next }
        else { skip = 0 }
    }
    !skip { print }
    ' ~/.ssh/config > ~/.ssh/config.tmp

    mv ~/.ssh/config.tmp ~/.ssh/config
    chmod 600 ~/.ssh/config 2>/dev/null
    echo "✓ 已删除: $NAME"
}

ssh_test() {
    ssh_list
    echo ""
    read -p "输入要测试的名称: " NAME
    [ -z "$NAME" ] && return

    echo ""
    echo "测试 $NAME ..."
    timeout 5 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$NAME" "echo ✓ 连通" 2>/dev/null && echo "✓ 连通" || echo "✗ 不可达"
}
