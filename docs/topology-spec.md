# 拓扑规范定义 (Topology Specification)

## 版本

- spec_version: "1.0"

---

## 服务器节点定义 (Server Node)

```yaml
server:
  # 必填字段
  id: "aliyun"                    # 全局唯一标识（建议使用 hostname 或自定义别名）
  alias: "aliyun-main"            # 显示别名
  port: 22                        # SSH 端口
  
  # 可选字段
  ip_public: "YOUR_JUMP_SERVER_IP"       # 公网 IP（可从外部直接访问）
  ip_private: "172.28.38.190"     # 内网 IP（VPN/内网环境）
  ip_vpn: "YOUR_WINDOWS_IP"          # VPN 网络 IP
  
  # 用户配置
  user_default: "root"            # 默认登录用户
  users:                          # 多用户支持
    - name: "root"
      role: "admin"               # admin/user/guest
      key_file: "id_aliyun"       # 密钥文件名（位于 ~/.ssh/）
    - name: "hermes"
      role: "agent"
      key_file: "id_hermes_agent"
  
  # 信任等级
  trust_level: "full"             # full/admin/user/guest
  
  # 能力标签
  capabilities:
    - "public-ip"                 # 有公网 IP
    - "always-online"             # 24小时在线
    - "master-node"               # 主控节点
    - "vpn-gateway"               # VPN 网关
    - "tunnel-endpoint"           # 隧道端点
  
  # 元数据
  metadata:
    provider: "aliyun"            # 云服务商
    region: "cn-hangzhou"         # 区域
    created_at: "2026-05-14"      # 创建时间
    description: "阿里云 ECS 主服务器"
```

---

## 连接边定义 (Connection Edge)

```yaml
connection:
  # 必填字段
  from: "aliyun"                  # 源服务器 ID
  to: "node3"                     # 目标服务器 ID
  
  # 连接类型
  type: "tunnel"                  # direct/tunnel/vpn/proxy/jump
  
  # 连接状态
  status: "active"                # active/inactive/error/testing
  
  # 可选字段
  via: "windows"                  # 路径（跳板服务器）
  via_path: ["windows", "vpn"]    # 完整路径（多跳板）
  
  # 性能指标
  latency_ms: 50                  # 延迟（毫秒）
  bandwidth_mbps: 100             # 带宽
  
  # 认证方式
  auth_method: "key"              # key/password/cert/agent
  auth_user: "wuxiaoran"          # 认证用户
  auth_key: "id_node3"            # 密钥文件
  
  # 隧道配置（type=tunnel 时）
  tunnel:
    local_port: 2223              # 本地监听端口
    remote_port: 22               # 远程目标端口
    direction: "reverse"          # forward/reverse/bidirectional
  
  # 时间戳
  established_at: "2026-05-14T10:00:00Z"
  last_test_at: "2026-05-14T12:00:00Z"
  last_success_at: "2026-05-14T12:00:00Z"
```

---

## 连接类型定义

| 类型 | 说明 | 示例 |
|------|------|------|
| direct | 直接 SSH 连接 | `ssh aliyun` |
| tunnel | SSH 隧道连接 | 反向隧道 `-R` |
| vpn | 通过 VPN 网络 | EasyConnect 后访问内网 |
| proxy | 通过代理服务器 | HTTP/SOCKS 代理 |
| jump | 多跳板连接 | `ProxyJump` |

---

## 拓扑图定义 (Topology Graph)

```yaml
topology:
  # 元信息
  name: "my-servers"              # 拓扑名称
  version: "1.0"                  # 版本
  created_at: "2026-05-14"
  updated_at: "2026-05-14"
  
  # 服务器列表
  servers:
    - id: "aliyun"
      alias: "阿里云主服务器"
    - id: "node3"
      alias: "学校内网服务器"
    - id: "windows"
      alias: "Windows 跳板"
    - id: "local"
      alias: "本地机器"
  
  # 连接列表
  connections:
    # 直连
    - from: "local"
      to: "aliyun"
      type: "direct"
      status: "active"
    
    # 隧道（通过 Windows）
    - from: "aliyun"
      to: "node3"
      type: "tunnel"
      via: "windows"
      status: "active"
    
    # VPN 网络
    - from: "windows"
      to: "node3"
      type: "vpn"
      status: "active"
    
    # 双向隧道
    - from: "node3"
      to: "aliyun"
      type: "tunnel"
      via: "windows"
      direction: "reverse"
      status: "active"
  
  # 默认路径策略
  routing:
    default_via: "aliyun"         # 默认跳板
    fallback_enabled: true        # 启用备选路径
    auto_optimize: true           # 自动优化路径
```

---

## 路径规划算法

### 最短路径计算

```
输入：from_server, to_server
输出：最优路径 [server1, server2, ..., target]

算法：
1. 构建连接图（有向图）
2. 使用 Dijkstra 计算最短路径
3. 考虑延迟、稳定性权重
4. 返回最优路径

示例：
local → node3 的路径：
  - 路径1: local → aliyun → windows → node3 (延迟: 100ms)
  - 路径2: local → vpn → node3 (延迟: 200ms, 需要 VPN)
  - 选择: 路径1（无需 VPN，延迟更低）
```

---

## 文件存储结构

```
~/.hermes/topology/
├── topology.yaml              # 主拓扑文件
├── servers/
│   ├── aliyun.yaml            # 服务器详细配置
│   ├── node3.yaml
│   ├── windows.yaml
│   └── local.yaml
├── connections/
│   ├── aliyun-node3.yaml      # 连接详细配置
│   ├── local-aliyun.yaml
│   └── windows-node3.yaml
├── cache/
│   ├── latency.json           # 延迟测试缓存
│   └── status.json            # 状态缓存
└── history/
│   └── changes.log            # 变更历史
```

---

## 验证规则

### 必填字段验证

- `server.id`: 必填，全局唯一
- `server.port`: 必填，有效端口 (1-65535)
- `connection.from`: 必填，必须存在于 servers
- `connection.to`: 必填，必须存在于 servers

### 类型验证

- `trust_level`: 只能为 full/admin/user/guest
- `connection.type`: 只能为 direct/tunnel/vpn/proxy/jump
- `connection.status`: 只能为 active/inactive/error/testing

### 逻辑验证

- 自环检测：`from != to`
- 路径验证：`via` 必须存在于 servers
- 端口冲突：同一服务器不能有重复监听端口