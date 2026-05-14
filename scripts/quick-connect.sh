#!/bin/bash
# 快速连接脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPOLOGY_DIR="$HOME/.hermes/topology"

usage() {
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  init              初始化拓扑配置"
    echo "  add               添加服务器"
    echo "  list              列出服务器"
    echo "  matrix            显示连接矩阵"
    echo "  register          生成注册信息"
    echo "  connect <to>      连接到服务器"
    echo "  test <to>         测试连接"
    echo ""
    echo "示例:"
    echo "  $0 init"
    echo "  $0 add --alias node3 --ip 10.16.82.202 --port 5122"
    echo "  $0 connect node3"
}

# 初始化
init_topology() {
    mkdir -p "$TOPOLOGY_DIR"/{servers,connections,cache}
    
    if [ -f "$TOPOLOGY_DIR/topology.yaml" ]; then
        echo "拓扑配置已存在"
        return
    fi
    
    cat > "$TOPOLOGY_DIR/topology.yaml" << 'EOF'
name: my-servers
version: "1.0"
servers: []
connections: []
routing:
  default_via: null
  fallback_enabled: true
  auto_optimize: true
EOF
    
    echo "✓ 已创建拓扑配置: $TOPOLOGY_DIR/topology.yaml"
}

# 添加服务器
add_server() {
    local alias=""
    local ip=""
    local port=22
    local user="root"
    local trust="user"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --alias) alias="$2"; shift 2 ;;
            --ip) ip="$2"; shift 2 ;;
            --port) port="$2"; shift 2 ;;
            --user) user="$2"; shift 2 ;;
            --trust) trust="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    
    if [ -z "$alias" ] || [ -z "$ip" ]; then
        echo "错误: 必须指定 --alias 和 --ip"
        return 1
    fi
    
    local server_id=$(echo "$alias" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
    local server_file="$TOPOLOGY_DIR/servers/${server_id}.yaml"
    
    cat > "$server_file" << EOF
id: $server_id
alias: $alias
ip_private: $ip
port: $port
user_default: $user
trust_level: $trust
EOF
    
    echo "✓ 已添加服务器: $alias"
    echo "  配置文件: $server_file"
}

# 生成注册信息
register_local() {
    echo "服务器注册信息:"
    echo "================================"
    echo ""
    echo "ALIAS=$(hostname)"
    echo "IP=$(hostname -I | awk '{print $1}')"
    echo "PORT=22"
    echo "USER=$USER"
    echo "KEY=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub 2>/dev/null || echo '未找到公钥')"
    echo "TRUST=user"
    echo ""
    echo "================================"
    echo "复制以上信息到目标服务器执行:"
    echo "  topology accept --from <源服务器>"
}

# 连接服务器
connect_to() {
    local target="$1"
    
    if [ -z "$target" ]; then
        echo "错误: 必须指定目标服务器"
        return 1
    fi
    
    # 检查 SSH config
    if ssh -G "$target" &>/dev/null; then
        echo "连接到 $target..."
        ssh "$target"
    else
        echo "错误: 未找到服务器 '$target' 的配置"
        echo "请先添加服务器: $0 add --alias $target --ip <IP>"
        return 1
    fi
}

# 测试连接
test_connection() {
    local target="$1"
    
    if [ -z "$target" ]; then
        echo "错误: 必须指定目标服务器"
        return 1
    fi
    
    echo "测试连接到 $target..."
    
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "$target" "echo '连接成功'" 2>/dev/null; then
        echo "✓ 连接正常"
    else
        echo "✗ 连接失败"
        return 1
    fi
}

# 主逻辑
case "${1:-}" in
    init) init_topology ;;
    add) shift; add_server "$@" ;;
    list) python3 "$SCRIPT_DIR/topology-manager.py" list ;;
    matrix) python3 "$SCRIPT_DIR/topology-manager.py" matrix ;;
    register) register_local ;;
    connect) shift; connect_to "$1" ;;
    test) shift; test_connection "$1" ;;
    *) usage ;;
esac