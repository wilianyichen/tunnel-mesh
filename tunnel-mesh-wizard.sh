#!/bin/bash
# ========================================
# Tunnel Mesh - 配置向导
# 全交互式，问清楚目标后逐步引导
# ========================================
set -e

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║            Tunnel Mesh  配置向导                  ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  告诉我你想连接哪些服务器，我帮你规划步骤。       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ═══════════════ Step 1: 目标 ═══════════════
echo "【第一步】你想做什么？"
echo ""
echo "  [1] A 访问 B（单向连接，两台服务器）"
echo "  [2] A ↔ B 互相访问（双向连接，两台服务器）"
echo "  [3] 多台服务器组网（3台或更多）"
echo "  [4] 查看当前网络"
echo ""
read -p "选择 [2]: " GOAL
GOAL=${GOAL:-2}

if [ "$GOAL" = "4" ]; then
    bash tunnel-mesh.sh status
    exit 0
fi

# ═══════════════ Step 2: 网络拓扑 ═══════════════
echo ""
echo "【第二步】你的网络情况？"
echo ""
echo "  服务器都在哪？"
echo "  [1] 都在内网（能互相直连）"
echo "  [2] 都在公网（都有公网IP）"
echo "  [3] 一台公网 + 一台内网（不能互连）"
echo "  [4] 一台公网 + 一台内网，还有一台 Windows 能同时连它们"
echo ""
read -p "选择: " TOPO
TOPO=${TOPO:-4}

# ═══════════════ Step 3: 规划步骤 ═══════════════
echo ""
echo "════════════════════════════════════════"
echo "  为你规划的配置步骤"
echo "════════════════════════════════════════"
echo ""

case $TOPO in
    1|2)
        # 网络互通 → 正向直连
        echo "两台服务器网络互通，直接 SSH 就行。"
        echo ""
        echo "步骤："
        echo "  ① 服务器A: bash tunnel-mesh.sh → [1] 导出身份卡"
        echo "  ② 服务器B: bash tunnel-mesh.sh → [2] 导入身份卡"
        echo "  ③ 完成！ssh 对方"
        ;;
    3)
        # 一台公网 + 一台内网
        echo "只有一台能发起连接。"
        echo ""
        echo "如果公网那台想连内网那台 → 需要反向隧道"
        echo "如果内网那台想连公网那台 → 公网那台导出身份，内网导入"
        echo ""
        echo "步骤："
        echo "  ① 公网服务器: bash tunnel-mesh.sh → [1] 导出身份卡"
        echo "  ② 复制身份卡到内网服务器"
        echo "  ③ 内网服务器: bash tunnel-mesh.sh → [2] 导入"
        echo "     → 选 [2] 反向隧道 → 选 [1] 自己维持"
        echo "     → 运行输出的隧道命令（保持运行）"
        echo "  ④ 完成！"
        ;;
    4)
        # 公网 + 内网 + Windows 桥 → 你的实际场景
        echo "你的情况：两台服务器不能互连，但 Windows 能同时连它们。"
        echo ""
        echo "需要建立两条反向隧道，都由 Windows 维持："
        echo ""
        echo "  ┌─────────┐                    ┌─────────┐"
        echo "  │ 服务器A │                    │ 服务器B │"
        echo "  │ (公网)  │                    │ (内网)  │"
        echo "  └────┬────┘                    └────┬────┘"
        echo "       │                              │"
        echo "       │     ┌──────────┐             │"
        echo "       └────→│ Windows  │←────────────┘"
        echo "       隧道1 │  (你的电脑)│  隧道2"
        echo "             └──────────┘"
        echo ""

        echo "操作步骤（4步）："
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " 第1步：在 服务器A 上"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " bash tunnel-mesh.sh"
        echo " → [1] 导出身份卡"
        echo " → 会输出类似这样的身份卡："
        echo "   ===IDENTITY==="
        echo "   NAME=aliyun"
        echo "   IP=1.2.3.4"
        echo "   PORT=22"
        echo "   USER=root"
        echo "   PUBKEY=ssh-rsa AAAA..."
        echo "   ===END==="
        echo " → 把身份卡复制下来，待会用"
        echo ""

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " 第2步：在 服务器B 上"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " bash tunnel-mesh.sh"
        echo " → 也运行 [1] 导出身份卡（复制下来）"
        echo " → 然后 [2] 导入身份卡 → 粘贴服务器A的身份卡"
        echo " → 问「能直连吗？」→ 选 [2] 不能"
        echo " → 问「谁维持？」→ 选 [2] 外部机器"
        echo " → 自动生成隧道命令。复制这个命令。"
        echo ""

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " 第3步：在 服务器A 上"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " bash tunnel-mesh.sh"
        echo " → [2] 导入身份卡 → 粘贴服务器B的身份卡"
        echo " → 问「能直连吗？」→ 选 [2] 不能"
        echo " → 问「谁维持？」→ 选 [2] 外部机器"
        echo " → 自动生成隧道命令。复制这个命令。"
        echo ""

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " 第4步：在 Windows 上"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo " 双击 windows-contract.bat"
        echo " → [1] 导入契约 → 粘贴第2步的隧道命令"
        echo " → [1] 导入契约 → 粘贴第3步的隧道命令"
        echo " → 自动创建两条隧道 + 开机自启"
        echo ""
        echo "完成！"
        ;;
esac

# ═══════════════ Step 4: 是否需要硬编码执行 ═══════════════
echo ""
echo "════════════════════════════════════════"
echo "需要我帮你执行这些步骤吗？"
echo ""
echo "  [1] 是，逐步引导我执行"
echo "  [2] 不用，我已经知道怎么做了"
read -p "选择 [2]: " EXEC
EXEC=${EXEC:-2}

if [ "$EXEC" = "1" ]; then
    echo ""
    echo "════════════════════════════════════════"
    echo "  开始逐步引导..."
    echo "════════════════════════════════════════"

    if [ "$TOPO" = "4" ]; then
        echo ""
        echo "── 你在哪台服务器上？──"
        echo "  [1] 服务器A（公网那台）"
        echo "  [2] 服务器B（内网那台）"
        echo "  [3] Windows"
        read -p "选择: " WHERE

        case $WHERE in
            1)
                echo ""
                echo "── 导出服务器A身份卡 ──"
                bash "$(dirname "$0")/tunnel-mesh.sh" export
                echo ""
                echo "── 把上面的身份卡复制到服务器B上 ──"
                echo "   登录服务器B后，运行: bash tunnel-mesh.sh import"
                echo "   然后粘贴身份卡。"
                echo ""
                echo "── 服务器B导入完成后，会生成一条隧道命令 ──"
                echo "   把隧道命令复制到 Windows，在 windows-contract.bat 里导入。"
                echo ""
                echo "── 同时，你需要在服务器A上导入服务器B的身份卡 ──"
                echo "   登录服务器B，运行: bash tunnel-mesh.sh export"
                echo "   复制身份卡回来，在这里运行: bash tunnel-mesh.sh import"
                ;;
            2)
                echo ""
                echo "── 导出服务器B身份卡 ──"
                bash "$(dirname "$0")/tunnel-mesh.sh" export
                echo ""
                echo "── 把上面的身份卡复制到服务器A上 ──"
                echo ""
                echo "── 同时，导入服务器A的身份卡 ──"
                echo "   bash tunnel-mesh.sh import"
                echo "   粘贴服务器A的身份卡"
                ;;
            3)
                echo "在 Windows 上："
                echo "  双击 windows-contract.bat → [1]导入"
                echo "  粘贴从服务器A和服务器B获取的隧道命令"
                ;;
        esac
    fi
fi

echo ""
echo "════════════════════════════════════════"
echo "  向导结束。祝你连接愉快！"
echo "════════════════════════════════════════"
