#!/bin/bash
# ========================================
# shellcheck disable=SC2155
set -o pipefail
# 递归建边 - 从主出发沿网络可达方向递归直到触达仆
# 首跳正向直连IP，后续跳统一端口隧道(ssh -L 或 ssh -R)
# 输出: fabric.json（物理层）+ config.json（单条逻辑边 + fabric_id 引用）
# ========================================

MAX_CHAIN_DEPTH=5

# 递归建边被中断时不清除链路数据（保留到用户重试）
_RECURSIVE_INTERRUPTED=0
_chain_cleanup() {
    if [ "${_RECURSIVE_INTERRUPTED:-0}" -eq 0 ]; then
        _RECURSIVE_INTERRUPTED=1
        echo ""
        echo "⚠ 递归建边被中断！"
        echo "  已构建的跳: $CHAIN_COUNT"
        echo "  半成品数据在内存中（未写入磁盘），可重新运行。"
    fi
    trap - INT TERM
}
trap _chain_cleanup INT TERM

# ---- 链路跳数组 ----
CHAIN_FROM=()
CHAIN_TO=()
CHAIN_TYPE=()
CHAIN_CMD=()
CHAIN_MAINTAINER=()
CHAIN_TO_IP=()
CHAIN_TO_PORT=()
CHAIN_TO_USER=()
CHAIN_FROM_IP=()
CHAIN_FROM_PORT=()
CHAIN_COUNT=0
CHAIN_PORT=""

# ---- 中转节点追踪（不在 config.json servers 中） ----
TRANSIT_NAMES=()
TRANSIT_IPS=()
TRANSIT_PORTS=()
TRANSIT_USERS=()
TRANSIT_PUBKEYS=()
TRANSIT_COUNT=0

add_hop() {
    local from=$1 to=$2 type=$3 cmd=$4 maintainer=$5
    local from_ip=${6:-} from_port=${7:-}
    local to_ip=${8:-} to_port=${9:-} to_user=${10:-}
    CHAIN_FROM+=("$from")
    CHAIN_TO+=("$to")
    CHAIN_TYPE+=("$type")
    CHAIN_CMD+=("$cmd")
    CHAIN_MAINTAINER+=("${maintainer:-}")
    CHAIN_FROM_IP+=("${from_ip:-}")
    CHAIN_FROM_PORT+=("${from_port:-}")
    CHAIN_TO_IP+=("${to_ip:-}")
    CHAIN_TO_PORT+=("${to_port:-}")
    CHAIN_TO_USER+=("${to_user:-}")
    CHAIN_COUNT=$((CHAIN_COUNT + 1))
}

add_transit() {
    TRANSIT_NAMES+=("$1")
    TRANSIT_IPS+=("$2")
    TRANSIT_PORTS+=("$3")
    TRANSIT_USERS+=("$4")
    TRANSIT_PUBKEYS+=("$5")
    TRANSIT_COUNT=$((TRANSIT_COUNT + 1))
}

# 统一节点属性查询：先查 transit 数组，再查 config.json
_node_attr() {
    local name=$1 field=$2
    local i
    for ((i=0; i<TRANSIT_COUNT; i++)); do
        if [ "${TRANSIT_NAMES[$i]}" = "$name" ]; then
            case "$field" in
                ip) echo "${TRANSIT_IPS[$i]}" ;;
                port) echo "${TRANSIT_PORTS[$i]}" ;;
                user) echo "${TRANSIT_USERS[$i]}" ;;
                pubkey) echo "${TRANSIT_PUBKEYS[$i]}" ;;
            esac
            return
        fi
    done
    # fallback: config.json
    case "$field" in
        ip) server_reachable_ip "$name" ;;
        port) server_field "$name" "port" "22" ;;
        user) server_field "$name" "user" "root" ;;
        pubkey) server_field "$name" "pubkey" "" ;;
    esac
}

node_ip()   { _node_attr "$1" "ip"; }
node_port() { _node_attr "$1" "port"; }
node_user() { _node_attr "$1" "user"; }
node_pubkey() { _node_attr "$1" "pubkey"; }

# 判断节点是否已知（config.json 或 transit 数组）
node_known() {
    local name=$1
    server_exists "$name" && return 0
    local i
    for ((i=0; i<TRANSIT_COUNT; i++)); do
        [ "${TRANSIT_NAMES[$i]}" = "$name" ] && return 0
    done
    return 1
}

# 解析身份卡并添加到 config.json（登录目标用）
# 依赖 detect.sh 中的共享 parse_identity_card（设置 _ID_NAME 等全局变量）
parse_identity_to_server() {
    if ! parse_identity_card; then return 1; fi
    server_add "$_ID_NAME" "$_ID_IP" "${_ID_PORT:-22}" "${_ID_USER:-root}" "" "$_ID_PUBKEY"
    echo "  ✓ 已添加: $_ID_NAME ($_ID_IP:$_ID_PORT)"
    return 0
}

# 解析身份卡并注册到 transit 数组（中转节点、不放进 config.json）
parse_identity_to_transit() {
    if ! parse_identity_card; then return 1; fi
    add_transit "$_ID_NAME" "$_ID_IP" "${_ID_PORT:-22}" "${_ID_USER:-root}" "${_ID_PUBKEY:-}"
    echo "  ✓ 已注册中转节点: $_ID_NAME ($_ID_IP:$_ID_PORT)"
    return 0
}

# 主递归函数
# 参数: curr(当前节点) servant(目标) port(统一端口) depth(当前深度)
# 返回: 0=成功到达仆, 1=失败
build_edge_chain() {
    local curr=$1 servant=$2 port=$3 depth=$4

    if [ "$curr" = "$servant" ]; then
        echo "  ✓ 当前节点即为目标"
        return 0
    fi

    if [ "$depth" -ge "$MAX_CHAIN_DEPTH" ]; then
        echo "❌ 链路深度已达上限 ($MAX_CHAIN_DEPTH 跳)"
        return 1
    fi

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║  链路构建 — 深度 $depth                              ║"
    echo "║  从: $curr"
    echo "║  到: $servant"
    echo "║  端口: $port"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "  $curr → $servant 的网络方向？"
    echo "    [1] 正向 — $curr 能直接 SSH 到 $servant"
    echo "    [2] 反向 — $servant 能连到 $curr（反之不能）"
    echo "    [3] 都不能 — 引入中间服务器"
    read -p "  选择: " DIR

    case $DIR in
        1)  # 正向可达
            local target_ip target_port target_user
            target_ip=$(node_ip "$servant")
            target_port=$(node_port "$servant" "22")
            target_user=$(node_user "$servant" "root")
            if [ "$depth" -eq 0 ]; then
                echo ""
                echo "  ✓ 首跳正向直连: $curr → $servant ($target_ip:$target_port)"
                add_hop "$curr" "$servant" "forward_direct" "" "" \
                    "" "" "$target_ip" "$target_port" "$target_user"
            else
                local fwd_cmd
                fwd_cmd=$(gen_forward_tunnel_cmd "$curr" "$servant" "$port" \
                    "$target_ip" "$target_port" "$target_user")
                echo ""
                echo "  ✓ 隧道(ssh -L): $curr 运行 → $servant 可达"
                echo "  命令: $fwd_cmd"
                add_hop "$curr" "$servant" "forward_tunnel" "$fwd_cmd" "prev" \
                    "" "" "$target_ip" "$target_port" "$target_user"
            fi
            return 0
            ;;

        2)  # 反向可达
            # shellcheck disable=SC2155
            local curr_ip curr_port curr_user rev_cmd
            curr_ip=$(node_ip "$curr")
            curr_port=$(node_port "$curr" "22")
            curr_user=$(node_user "$curr" "root")
            rev_cmd=$(gen_reverse_tunnel_cmd "$curr" "$servant" "$port" \
                "$curr_ip" "$curr_port" "$curr_user")
            echo ""
            echo "  ✓ 隧道(ssh -R): $servant 运行 → $curr 可达"
            echo "  命令: $rev_cmd"
            local servant_ip servant_port servant_user
            servant_ip=$(node_ip "$servant")
            servant_port=$(node_port "$servant" "22")
            servant_user=$(node_user "$servant" "root")
            add_hop "$curr" "$servant" "reverse_tunnel" "$rev_cmd" "next" \
                "$curr_ip" "$curr_port" "$servant_ip" "$servant_port" "$servant_user"
            return 0
            ;;

        3)  # 引入中间服务器
            echo ""
            echo "  引入中间服务器。当前已知服务器:"
            server_list
            # 也列出 transit 节点
            local ti
            for ((ti=0; ti<TRANSIT_COUNT; ti++)); do
                echo "    [中转] ${TRANSIT_NAMES[$ti]}  ${TRANSIT_IPS[$ti]}:${TRANSIT_PORTS[$ti]}"
            done
            echo ""
            echo "  选择方式:"
            echo "    [1] 手动输入新服务器信息"
            echo "    [P] 粘贴身份卡"
            echo "    [K] 自动推荐（从已知服务器探测排序）"
            read -p "  选择: " MID_MODE

            local new_name new_ip new_port new_user new_pubkey is_new_node=0

            case $MID_MODE in
                P|p)
                    echo ""
                    echo "  粘贴身份卡（Ctrl+D 回车）:"
                    echo "  ──────────────────────────"
                    if ! parse_identity_card; then
                        return 1
                    fi
                    new_name="$_ID_NAME"
                    new_ip="$_ID_IP"
                    new_port="${_ID_PORT:-22}"
                    new_user="${_ID_USER:-root}"
                    new_pubkey="$_ID_PUBKEY"
                    # 身份卡来源的服务器：如果不在 config.json 中 → 作为 transit 追踪
                    if ! server_exists "$new_name"; then
                        is_new_node=1
                    fi
                    ;;

                K|k)
                    recommend_bridge "$curr" "$servant"
                    read -p "  输入服务器名称（或回车手动输入新服务器）: " BRIDGE_NAME
                    if [ -n "$BRIDGE_NAME" ]; then
                        if server_exists "$BRIDGE_NAME"; then
                            new_name="$BRIDGE_NAME"
                            echo "  ✓ 已选择: $new_name"
                        elif node_known "$BRIDGE_NAME"; then
                            new_name="$BRIDGE_NAME"
                            echo "  ✓ 已选择（中转节点）: $new_name"
                        else
                            echo "  ❌ $BRIDGE_NAME 不在已知列表中"; return 1
                        fi
                    else
                        read -p "  新服务器名称: " new_name
                        validate_node_name "$new_name" || { new_name=""; continue; }
                        read -p "  IP地址: " new_ip
                        while [ -z "$new_ip" ] || ! validate_ip "$new_ip" 2>/dev/null; do
                            read -p "  IP 无效或为空，请重新输入: " new_ip
                        done
                        read -p "  SSH端口 [22]: " new_port; new_port=${new_port:-22}
                        read -p "  用户名 [root]: " new_user; new_user=${new_user:-root}
                        is_new_node=1
                    fi
                    ;;

                *)
                    read -p "  服务器名称: " new_name
                    while [ -z "$new_name" ] || ! validate_node_name "$new_name" 2>/dev/null; do
                        read -p "  名称无效或为空，请重新输入: " new_name
                    done
                    if server_exists "$new_name"; then
                        echo "  ✓ 已知服务器: $new_name"
                    elif node_known "$new_name"; then
                        echo "  ✓ 已知中转节点: $new_name"
                    else
                        read -p "  IP地址: " new_ip
                        while [ -z "$new_ip" ] || ! validate_ip "$new_ip" 2>/dev/null; do
                            read -p "  IP 无效或为空，请重新输入: " new_ip
                        done
                        read -p "  SSH端口 [22]: " new_port; new_port=${new_port:-22}
                        read -p "  用户名 [root]: " new_user; new_user=${new_user:-root}
                        is_new_node=1
                    fi
                    ;;
            esac

            # 新中间节点：加入 transit 追踪（不入 config.json）
            if [ "$is_new_node" -eq 1 ] && ! server_exists "$new_name"; then
                add_transit "$new_name" "$new_ip" "$new_port" "$new_user" "$new_pubkey"
                echo "  ✓ 已记录中转节点: $new_name ($new_ip:$new_port)"
            fi

            # 确定 curr → new_server 的网络方向
            echo ""
            echo "  $curr → $new_name 的网络方向？"
            echo "    [1] 正向 — $curr 能直接连到 $new_name"
            echo "    [2] 反向 — $new_name 能连到 $curr"
            read -p "  选择: " MID_DIR

            local mid_type mid_cmd mid_ip mid_port mid_user
            mid_ip=$(node_ip "$new_name")
            mid_port=$(node_port "$new_name" "22")
            mid_user=$(node_user "$new_name" "root")

            case $MID_DIR in
                1)
                    if [ "$depth" -eq 0 ]; then
                        echo "  ✓ 首跳正向直连: $curr → $new_name ($mid_ip)"
                        mid_type="forward_direct"
                        mid_cmd=""
                        add_hop "$curr" "$new_name" "forward_direct" "" "" \
                            "" "" "$mid_ip" "$mid_port" "$mid_user"
                    else
                        mid_cmd=$(gen_forward_tunnel_cmd "$curr" "$new_name" "$port" \
                            "$mid_ip" "$mid_port" "$mid_user")
                        echo "  ✓ 隧道(ssh -L): $curr 运行"
                        echo "  命令: $mid_cmd"
                        mid_type="forward_tunnel"
                        add_hop "$curr" "$new_name" "forward_tunnel" "$mid_cmd" "prev" \
                            "" "" "$mid_ip" "$mid_port" "$mid_user"
                    fi
                    ;;
                2)
                    local curr_ip=$(node_ip "$curr")
                    local curr_port=$(node_port "$curr" "22")
                    local curr_user=$(node_user "$curr" "root")
                    mid_cmd=$(gen_reverse_tunnel_cmd "$curr" "$new_name" "$port" \
                        "$curr_ip" "$curr_port" "$curr_user")
                    echo "  ✓ 隧道(ssh -R): $new_name 运行"
                    echo "  命令: $mid_cmd"
                    mid_type="reverse_tunnel"
                    add_hop "$curr" "$new_name" "reverse_tunnel" "$mid_cmd" "next" \
                        "$curr_ip" "$curr_port" "$mid_ip" "$mid_port" "$mid_user"
                    ;;
                *)
                    echo "  ❌ 无效选择"
                    return 1
                    ;;
            esac

            # 递归
            build_edge_chain "$new_name" "$servant" "$port" $((depth + 1))
            return $?
            ;;

        *)
            echo "  ❌ 无效选择"
            return 1
            ;;
    esac
}

# 递归建边入口
do_edge_plan_recursive() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  递归建边 — 构建主→仆的完整链路                    ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    # 清空链路数据
    CHAIN_FROM=(); CHAIN_TO=(); CHAIN_TYPE=(); CHAIN_CMD=(); CHAIN_MAINTAINER=()
    CHAIN_TO_IP=(); CHAIN_TO_PORT=(); CHAIN_TO_USER=()
    CHAIN_FROM_IP=(); CHAIN_FROM_PORT=()
    CHAIN_COUNT=0
    TRANSIT_NAMES=(); TRANSIT_IPS=(); TRANSIT_PORTS=(); TRANSIT_USERS=(); TRANSIT_PUBKEYS=()
    TRANSIT_COUNT=0

    # Step 1: 确定主
    echo "【第1步】谁是「主」（发起连接的一方）？"
    echo "  当前本机: $HOSTNAME"
    echo "  [1] 本机 ($HOSTNAME)"
    echo "  [2] 其他服务器"
    read -p "  选择 [1]: " MC; MC=${MC:-1}
    if [ "$MC" = "1" ]; then
        MASTER="$HOSTNAME"
        MASTER_IP="$IP"; MASTER_PORT="$PORT"; MASTER_USER="$USER"
    else
        read -p "  主服务器名称: " MASTER
        [ -z "$MASTER" ] && { echo "  ❌ 名称不能为空"; return; }
        validate_node_name "$MASTER" || return
        server_exists "$MASTER" || { echo "  ❌ $MASTER 不在已知列表中"; return; }
        MASTER_IP=$(server_reachable_ip "$MASTER")
        MASTER_PORT=$(server_field "$MASTER" "port" "22")
        MASTER_USER=$(server_field "$MASTER" "user" "root")
    fi
    echo "  ✓ 主: $MASTER"

    # Step 2: 确定仆
    echo ""
    echo "【第2步】谁是「仆」（被连接的目标）？"
    echo "  已知服务器:"
    server_list
    echo ""
    read -p "  仆服务器名称: " SERVANT
    while [ -z "$SERVANT" ] || ! validate_node_name "$SERVANT" 2>/dev/null; do
        read -p "  名称无效或为空，请重新输入: " SERVANT
    done

    if server_exists "$SERVANT"; then
        echo "  ✓ 已知: $SERVANT"
    else
        echo "  未知服务器，请选择输入方式:"
        echo "    [1] 手动输入"
        echo "    [P] 粘贴身份卡"
        read -p "  选择 [1]: " SM; SM=${SM:-1}
        if [ "$SM" = "P" ] || [ "$SM" = "p" ]; then
            echo ""
            echo "  粘贴身份卡（Ctrl+D 回车）:"
            if ! parse_identity_to_server; then return; fi
            SERVANT="$_ID_NAME"
        else
            while true; do
                read -p "  IP地址: " SIP
                [ -z "$SIP" ] && { echo "  ❌ IP 不能为空"; continue; }
                validate_ip "$SIP" && break
            done
            read -p "  SSH端口 [22]: " SPORT; SPORT=${SPORT:-22}
            read -p "  用户名 [root]: " SUSER; SUSER=${SUSER:-root}
            server_add "$SERVANT" "$SIP" "${SPORT:-22}" "${SUSER:-root}" "" ""
        fi
        echo "  ✓ 已添加: $SERVANT"
    fi

    # Step 3: 分配统一端口
    CHAIN_PORT=$(port_allocate)
    echo ""
    echo "【第3步】分配统一端口: $CHAIN_PORT"
    echo "  整条链路共用此端口号"

    # Step 4: 递归构建
    echo ""
    echo "【第4步】递归探寻链路..."
    if build_edge_chain "$MASTER" "$SERVANT" "$CHAIN_PORT" 0; then
        # 双重确认：跳数大于 0 才写入
        if [ "$CHAIN_COUNT" -eq 0 ]; then
            echo ""
            echo "  ❌ 链路构建失败 — 未生成任何跳"
            return
        fi
        echo ""
        echo "╔══════════════════════════════════════════════════╗"
        echo "║  ✓ 链路构建完成！                                  ║"
        echo "╠══════════════════════════════════════════════════╣"
        echo "║  跳数: $CHAIN_COUNT                                          ║"
        echo "║  端口: $CHAIN_PORT                                          ║"
        print_chain_summary
        echo "╚══════════════════════════════════════════════════╝"

        # ---- 输出到 fabric.json + config.json ----
        echo ""
        echo "  正在写入 fabric.json + config.json..."

        fabric_init

        # 创建 fabric
        local FID
        FID=$(fabric_create "${MASTER}→${SERVANT}" "$CHAIN_PORT")
        echo "  ✓ Fabric ID: $FID"

        # 逐跳写入 fabric
        local i
        for ((i=0; i<CHAIN_COUNT; i++)); do
            local hop_from="${CHAIN_FROM[$i]}"
            local hop_to="${CHAIN_TO[$i]}"
            local hop_type="${CHAIN_TYPE[$i]}"
            local hop_cmd="${CHAIN_CMD[$i]}"

            local tip="${CHAIN_TO_IP[$i]}"
            local tport="${CHAIN_TO_PORT[$i]}"
            [ -z "$tip" ] && tip=$(node_ip "$hop_to")
            [ -z "$tport" ] && tport=$(node_port "$hop_to" "22")

            local runner=""
            case "$hop_type" in
                forward_tunnel) runner="$hop_from" ;;
                reverse_tunnel) runner="$hop_to" ;;
            esac

            fabric_add_hop "$FID" "$i" "$hop_from" "$hop_to" "$hop_type" \
                "$CHAIN_PORT" "$hop_cmd" "$runner" "$tip" "$tport"
        done

        # 写入中转节点
        local ti
        for ((ti=0; ti<TRANSIT_COUNT; ti++)); do
            fabric_add_transit "$FID" "${TRANSIT_NAMES[$ti]}" "${TRANSIT_IPS[$ti]}" \
                "${TRANSIT_PORTS[$ti]}" "${TRANSIT_USERS[$ti]}" "${TRANSIT_PUBKEYS[$ti]}"
        done

        # 写入维持者（每个有隧道的跳）
        for ((i=0; i<CHAIN_COUNT; i++)); do
            local cmd="${CHAIN_CMD[$i]}"
            [ -z "$cmd" ] && continue
            local typ="${CHAIN_TYPE[$i]}"
            local runner persist="manual"
            case "$typ" in
                forward_tunnel) runner="${CHAIN_FROM[$i]}" ;;
                reverse_tunnel) runner="${CHAIN_TO[$i]}" ;;
                *) continue ;;
            esac
            fabric_add_maintainer "$FID" "$runner" "runner" "$cmd" "$persist"
        done

        # 计算 weight：含隧道 → 1.5，纯直连 → 1.0
        local weight=1.0 edge_type="forward"
        for ((i=0; i<CHAIN_COUNT; i++)); do
            if [ "${CHAIN_TYPE[$i]}" != "forward_direct" ]; then
                weight=1.5
                edge_type="reverse"
                break
            fi
        done

        # 创建单条逻辑边（含 fabric_id 引用）
        edge_add "$MASTER" "$SERVANT" "$edge_type" "$CHAIN_PORT" "" "" "$FID" "$weight"
        echo "  ✓ 逻辑边: $MASTER → $SERVANT (fabric: $FID, weight: $weight)"

        echo ""
        echo "  ✓ fabric.json + config.json 写入完成"

        # 自动写本机 SSH config
        #   首跳直达: HostName <ip>, Port <port>
        #   隧道跳:   HostName localhost, Port <统一端口>
        #   非首跳隧道: ProxyCommand ssh -W %h:%p <上一跳>（目标在跳转主机上解析）
        echo ""
        echo "  正在应用 SSH config..."
        mkdir -p ~/.ssh
        local prev_jump=""
        for ((i=0; i<CHAIN_COUNT; i++)); do
            local to="${CHAIN_TO[$i]}"
            local typ="${CHAIN_TYPE[$i]}"

            # 如果已有同名 Host，先删旧条目
            ssh_config_remove_host "$to"

            {
                echo ""
                echo "# Tunnel Mesh - $to ($typ)"
                echo "Host $to"
                if [ "$typ" = "forward_direct" ] && [ "$i" -eq 0 ]; then
                    # 首跳直连: 直接用目标 IP
                    local tip tport
                    tip=$(node_ip "$to")
                    tport=$(node_port "$to" "22")
                    echo "    HostName $tip"
                    echo "    Port $tport"
                else
                    # 隧道跳: 都是 localhost:端口
                    if [ -n "$prev_jump" ]; then
                        # 非首跳: ProxyCommand 确保目标在跳转主机上解析
                        echo "    ProxyCommand ssh -W %h:%p $prev_jump"
                    fi
                    echo "    HostName localhost"
                    echo "    Port $CHAIN_PORT"
                fi
                echo "    StrictHostKeyChecking no"
                echo "    User $(node_user "$to" "root")"
            } >> ~/.ssh/config
            chmod 600 ~/.ssh/config 2>/dev/null
            prev_jump="$to"
        done
        echo "  ✓ SSH config 已更新"

        do_generate_deployment_guide "$FID"
    else
        echo ""
        echo "  ❌ 链路构建失败"
    fi
}

# 打印链路摘要
print_chain_summary() {
    local i
    for ((i=0; i<CHAIN_COUNT; i++)); do
        local arrow="→"
        case "${CHAIN_TYPE[$i]}" in
            forward_direct)  arrow="─直连→" ;;
            forward_tunnel)  arrow="─ssh-L→" ;;
            reverse_tunnel)  arrow="─ssh-R→" ;;
        esac
        echo "║  ${CHAIN_FROM[$i]} $arrow ${CHAIN_TO[$i]}"
    done
}

# 生成部署指南
do_generate_deployment_guide() {
    local FID=${1:-}
    echo ""
    echo "════════════════════════════════════════"
    echo "  部署指南"
    echo "════════════════════════════════════════"
    echo ""
    if [ -n "$FID" ]; then
        echo "  Fabric ID: $FID"
        echo ""
    fi

    # 1. 公钥部署指南
    echo "## 1. 公钥部署"
    echo ""
    local i
    for ((i=0; i<CHAIN_COUNT; i++)); do
        local from="${CHAIN_FROM[$i]}"
        local to="${CHAIN_TO[$i]}"
        local typ="${CHAIN_TYPE[$i]}"

        case "$typ" in
            forward_direct)
                echo "   $from → $to: $to 需要 $from 的公钥（直连）"
                ;;
            forward_tunnel)
                echo "   $from → $to: $to 需要 $from 的公钥（ssh -L）"
                ;;
            reverse_tunnel)
                echo "   $from ← $to: $from 需要 $to 的公钥（ssh -R）"
                ;;
        esac
    done

    # 2. 隧道命令（每跳）+ 前提条件检查
    echo ""
    echo "## 2. 前提条件"
    echo ""
    echo "  所有参与隧道的节点必须:"
    echo "  - 已安装 OpenSSH Server (sshd) 并运行"
    echo "  - 已生成 SSH key pair (~/.ssh/id_ed25519)"
    echo "  - Windows 节点: 需安装 OpenSSH Server (设置→应用→可选功能)"
    echo ""
    local has_transit=0
    local ti
    for ((ti=0; ti<TRANSIT_COUNT; ti++)); do
        has_transit=1
        echo "  [中转] ${TRANSIT_NAMES[$ti]}: 必须运行 SSH server (sshd)"
    done
    [ "$has_transit" -eq 1 ] && echo ""

    echo "## 3. 隧道命令"
    echo ""
    local has_tunnel=0
    local windows_hint=0
    for ((i=0; i<CHAIN_COUNT; i++)); do
        local typ="${CHAIN_TYPE[$i]}"
        local cmd="${CHAIN_CMD[$i]}"
        if [ -n "$cmd" ]; then
            has_tunnel=1
            local runner platform_hint=""
            case "$typ" in
                forward_tunnel) runner="${CHAIN_FROM[$i]}" ;;
                reverse_tunnel) runner="${CHAIN_TO[$i]}" ;;
            esac
            # 检测是否是 Windows 节点（名称含 win 或 IP 不可达本机等情况）
            local runner_lower; runner_lower=$(echo "$runner" | tr '[:upper:]' '[:lower:]')
            if echo "$runner_lower" | grep -qE "win|^w-|pc|desktop"; then
                platform_hint="windows"
                windows_hint=1
            else
                platform_hint="linux"
            fi
            echo "### 跳 $((i+1)): ${CHAIN_FROM[$i]} → ${CHAIN_TO[$i]} ($typ)"
            echo ""
            echo "在 **$runner** 上运行:"
            echo '```bash'
            echo "$cmd"
            echo '```'
            case "$platform_hint" in
                windows)
                    echo ""
                    echo "⚠ Windows 持久化建议:"
                    echo '  - Git Bash: while true; do <命令>; sleep 5; done'
                    echo "  - 或创建计划任务 (Task Scheduler) 开机自启"
                    ;;
                linux)
                    echo ""
                    echo "持久化建议:"
                    echo "  autossh: autossh -M 0 -o \"ServerAliveInterval 30\" -o \"ServerAliveCountMax 3\" -N <命令后半部分>"
                    echo "  systemd: 创建 /etc/systemd/system/tunnel-mesh-xxx.service"
                    ;;
            esac
            echo ""
        fi
    done

    [ "$windows_hint" -eq 1 ] && echo "⚠ 检测到 Windows 节点。Windows 端可用 Git Bash / WSL 运行上述命令。"
    [ "$has_tunnel" -eq 0 ] && echo "  无需隧道（纯直连）"
    echo ""

    # 4. 主服务器 SSH config
    echo "## 4. 主服务器 SSH config (~/.ssh/config)"
    echo ""
    echo '```'
    local first_type="${CHAIN_TYPE[0]}"
    local first_to="${CHAIN_TO[0]}"
    local first_ip="${CHAIN_TO_IP[0]}"
    local first_port="${CHAIN_TO_PORT[0]}"
    local first_user="${CHAIN_TO_USER[0]}"
    [ -z "$first_ip" ] && first_ip=$(node_ip "$first_to")
    [ -z "$first_port" ] && first_port=$(node_port "$first_to" "22")
    [ -z "$first_user" ] && first_user=$(node_user "$first_to" "root")

    if [ "$first_type" = "forward_direct" ]; then
        echo "Host $first_to"
        echo "    HostName $first_ip"
        echo "    Port $first_port"
    else
        echo "Host ${CHAIN_TO[0]}"
        echo "    HostName localhost"
        echo "    Port $CHAIN_PORT"
    fi
    echo "    StrictHostKeyChecking no"
    echo "    User $first_user"

    # 后续跳（ProxyCommand 链: ssh -W %h:%p <上一跳>）
    local j prev_jump=""
    for ((j=1; j<CHAIN_COUNT; j++)); do
        local to="${CHAIN_TO[$j]}"
        if [ "$j" -eq 1 ]; then
            prev_jump="${CHAIN_TO[0]}"
        else
            prev_jump="${CHAIN_TO[$((j-1))]}"
        fi
        local to_user="${CHAIN_TO_USER[$j]}"
        [ -z "$to_user" ] && to_user=$(node_user "$to" "root")
        echo ""
        echo "Host $to"
        echo "    ProxyCommand ssh -W %h:%p $prev_jump"
        echo "    HostName localhost"
        echo "    Port $CHAIN_PORT"
        echo "    StrictHostKeyChecking no"
        echo "    User $to_user"
    done
    echo '```'

    # 5. 验证命令
    echo ""
    echo "## 5. 验证"
    echo ""
    local final_target="${CHAIN_TO[$((CHAIN_COUNT-1))]}"
    echo "在主服务器上运行:"
    echo '```bash'
    echo "ssh $final_target hostname"
    echo '```'

    # 6. 链式 SSH 命令（嵌套模式，每节点只存邻居公钥）
    echo ""
    echo "## 6. 链式连接（嵌套 SSH 模式）"
    echo ""
    echo "每节点只需存邻居公钥，无需全链部署:"
    echo '```bash'
    # 从最内层往外包
    local k cmd="ssh $final_target"
    for ((k=CHAIN_COUNT-2; k>=0; k--)); do
        cmd="ssh -t ${CHAIN_TO[$k]} \"$cmd\""
    done
    echo "$cmd"
    echo '```'

    # 生成可保存的脚本
    local script_path="$HOME/tunnel-mesh-chain-${MASTER}-${SERVANT}.sh"
    {
        echo "#!/bin/bash"
        echo "# Tunnel Mesh 链路部署脚本"
        echo "# 链路: $MASTER → ... → $SERVANT"
        if [ -n "$FID" ]; then
            echo "# Fabric ID: $FID"
        fi
        echo "# 生成时间: $(date)"
        echo ""
        for ((i=0; i<CHAIN_COUNT; i++)); do
            local cmd="${CHAIN_CMD[$i]}"
            [ -n "$cmd" ] && echo "# 跳 $((i+1)): ${CHAIN_FROM[$i]} → ${CHAIN_TO[$i]}"
            [ -n "$cmd" ] && echo "# 运行: $cmd"
            [ -n "$cmd" ] && echo ""
        done
    } > "$script_path"
    chmod +x "$script_path"
    echo ""
    echo "部署脚本已保存: $script_path"

    # 建完边后自动健康检查
    echo ""
    read -p "是否立即进行健康检查？[Y/n]: " DO_CHECK; DO_CHECK=${DO_CHECK:-Y}
    if [ "$DO_CHECK" != "n" ] && [ "$DO_CHECK" != "N" ]; then
        health_check_chain
    fi
}
