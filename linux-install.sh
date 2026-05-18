#!/bin/bash
# ========================================
# Tunnel Mesh Linux 安装脚本
# ========================================

set -e

echo ""
echo "╔════════════════════════════════════════╗"
echo "║     Tunnel Mesh Linux 安装             ║"
echo "╚════════════════════════════════════════╝"
echo ""

INSTALL_DIR="$HOME/.tunnel-mesh"
BIN_DIR="$HOME/.local/bin"
REPO_URL="https://github.com/wilianyichen/tunnel-mesh.git"

# 创建目录
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"

# 检查依赖
echo "[1/3] 检查依赖..."

if ! command -v ssh &>/dev/null; then
    echo "  [错误] 需要 SSH 客户端"
    exit 1
fi
echo "  ✓ SSH 已安装"

if ! command -v python3 &>/dev/null; then
    echo "  [提示] Python 3 未安装（脚本功能需要）"
fi

# 下载脚本
echo ""
echo "[2/3] 下载脚本..."

FILES=(
    "linux-export-config.sh"
    "scripts/parse-contract.py"
    "scripts/key-manager.py"
)

for file in "${FILES[@]}"; do
    url="$REPO_URL/raw/main/$file"
    dest="$INSTALL_DIR/$file"
    
    if curl -sSL "$url" -o "$dest" 2>/dev/null; then
        echo "  ✓ $file"
    else
        echo "  [跳过] $file (下载失败)"
    fi
done

# 创建命令
echo ""
echo "[3/3] 创建命令..."

cat > "$BIN_DIR/tunnel-mesh" << 'SCRIPT'
#!/bin/bash
bash "$HOME/.tunnel-mesh/linux-export-config.sh" "$@"
SCRIPT

chmod +x "$BIN_DIR/tunnel-mesh"

# 添加到 PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "  [提示] 已添加 ~/.local/bin 到 PATH，运行: source ~/.bashrc"
fi

echo ""
echo "════════════════════════════════════════"
echo "  安装完成！"
echo "════════════════════════════════════════"
echo ""
echo "  运行: tunnel-mesh"
echo ""
echo "  如果命令找不到，运行: source ~/.bashrc"
echo ""
