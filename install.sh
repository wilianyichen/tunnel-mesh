#!/bin/bash
# Tunnel Mesh 安装脚本
# 用法:
#   本地安装:  bash install.sh
#   在线安装:  curl -fsSL <url>/install.sh | bash
#   指定版本:  TUNNEL_MESH_VERSION=3.0.0 bash install.sh
set -euo pipefail

TUNNEL_MESH_VERSION="${TUNNEL_MESH_VERSION:-3.0.0}"
INSTALL_DIR="${TUNNEL_MESH_HOME:-$HOME/.local/share/tunnel-mesh}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
REPO_URL="${REPO_URL:-https://github.com/wilianyichen/tunnel-mesh}"

# 颜色
_ok()  { echo "  ✓ $*"; }
_warn(){ echo "  ⚠ $*"; }
_err() { echo "❌ $*"; exit 1; }

echo ""
echo "════════════════════════════════════════"
echo "  Tunnel Mesh v$TUNNEL_MESH_VERSION 安装"
echo "════════════════════════════════════════"
echo ""

# ---- 依赖检查 ----
if ! command -v python3 &>/dev/null; then
    echo "需要 python3。尝试安装:"
    echo "  Ubuntu/Debian: sudo apt install python3"
    echo "  CentOS/RHEL:   sudo yum install python3"
    echo "  macOS:         brew install python3"
    _err "python3 未安装"
fi

if ! command -v ssh &>/dev/null; then
    _err "ssh 未安装，Tunnel Mesh 依赖 OpenSSH"
fi

echo "python3 ✓  $(python3 --version)"
echo "ssh      ✓  $(ssh -V 2>&1 | head -1)"

# ---- 安装 ----
if [ -d "$INSTALL_DIR" ]; then
    echo ""
    echo "安装目录 $INSTALL_DIR 已存在"
    read -p "覆盖安装？[y/N]: " yn
    if [ "$yn" != "y" ] && [ "$yn" != "Y" ]; then
        echo "已取消"
        exit 0
    fi
    # 备份旧配置
    ts=$(date +%Y%m%d-%H%M%S)
    if [ -f "$HOME/.tunnel-mesh/config.json" ]; then
        cp "$HOME/.tunnel-mesh/config.json" "$HOME/.tunnel-mesh/config.json.bak.before-reinstall-$ts"
        _ok "已备份 ~/.tunnel-mesh/config.json"
    fi
    if [ -f "$HOME/.tunnel-mesh/fabric.json" ]; then
        cp "$HOME/.tunnel-mesh/fabric.json" "$HOME/.tunnel-mesh/fabric.json.bak.before-reinstall-$ts"
        _ok "已备份 ~/.tunnel-mesh/fabric.json"
    fi
    rm -rf "$INSTALL_DIR"
fi

mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# 检测安装来源
if [ -f "$(dirname "$0")/tunnel-mesh.sh" ] && [ -d "$(dirname "$0")/scripts" ]; then
    # 本地安装：从脚本所在目录复制
    SRC="$(cd "$(dirname "$0")" && pwd)"
    echo "从本地目录安装: $SRC"
    cp -r "$SRC"/* "$INSTALL_DIR/"
else
    # 在线安装：git clone
    echo "从 GitHub 下载..."
    if command -v git &>/dev/null; then
        git clone --depth 1 --branch "v$TUNNEL_MESH_VERSION" "$REPO_URL" "$INSTALL_DIR" 2>/dev/null || \
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    else
        _err "需要 git 进行在线安装。或下载 tar.gz 后本地安装: bash install.sh"
    fi
fi

# 删除本脚本自身（不安装到目标目录）
rm -f "$INSTALL_DIR/install.sh"

# ---- 创建快捷命令 ----
# 主入口: 通过 ~/.local/bin/tunnel-mesh 软链接
ln -sf "$INSTALL_DIR/tunnel-mesh.sh" "$BIN_DIR/tunnel-mesh"
_ok "已创建: $BIN_DIR/tunnel-mesh"

# ---- PATH 检查 ----
if ! echo "$PATH" | tr ':' '\n' | grep -Fxq "$BIN_DIR"; then
    echo ""
    echo "⚠ $BIN_DIR 不在 PATH 中"
    echo ""
    read -p "  自动追加到 ~/.bashrc？[Y/n]: " addpath
    if [ "$addpath" != "n" ] && [ "$addpath" != "N" ]; then
        for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
            if [ -f "$rc" ] && ! grep -q '.local/bin' "$rc" 2>/dev/null; then
                echo "" >> "$rc"
                echo "# Added by Tunnel Mesh installer" >> "$rc"
                echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$rc"
                _ok "已追加到 $rc"
                break
            fi
        done
    else
        echo "  跳过。手动执行: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
fi

# ---- 验证 ----
echo ""
echo "════════════════════════════════════════"
echo "  安装完成！"
echo "════════════════════════════════════════"
echo ""
echo "  使用方法:"
echo "    tunnel-mesh         交互式菜单"
echo "    tunnel-mesh --help  查看帮助"
echo "    tunnel-mesh --version  查看版本"
echo ""
echo "  安装路径: $INSTALL_DIR"
echo "  数据目录: ~/.tunnel-mesh/"
echo ""
echo "  如果 tunnel-mesh 命令不可用，请执行:"
echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
echo ""
