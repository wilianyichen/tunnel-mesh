#!/bin/bash
# wizard.sh - 配置向导
do_wizard() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           双向连接 配置向导                       ║"
    echo "╠══════════════════════════════════════════════════╣"
    echo "║  ① 两台服务器各自导出身份卡                      ║"
    echo "║  ② 各自导入对方的身份卡                          ║"
    echo "║  ③ Windows 粘贴隧道命令                          ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "[1] 导出本机身份卡  [2] 导入对方身份卡  [3] 查看教程"
    read -p "选择: " W
    case $W in
        1) do_export ;;
        2) do_import ;;
        3) echo ""; echo "① 服务器A: tunnel-mesh.sh → [1]导出 → 复制"
           echo "② 服务器B: tunnel-mesh.sh → [2]导入 → 粘贴 → 生成隧道"
           echo "③ 服务器B: [1]导出 → 复制 → 服务器A [2]导入"
           echo "④ Windows: tunnel-mesh.bat → [1]导入 ×2" ;;
    esac
}
