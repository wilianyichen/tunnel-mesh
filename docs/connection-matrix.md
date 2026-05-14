# 连接矩阵设计 (Connection Matrix)

## 概念

连接矩阵是拓扑的可视化表示，展示所有服务器间的连接关系。

---

## 矩阵结构

### 基本形式

```
        aliyun    node3    windows    local
aliyun    -       ✓→        ✓→         ✓→
node3    ✓←        -        ✓→         ✓→
windows  ✓←       ✓←         -         ✓→
local    ✓←       ✓←        ✓←          -
```

### 符号定义

| 符号 | 含义 |
|------|------|
| ✓→ | 可连接到 |
| ✓← | 可被连接 |
| ✓↔ | 双向连接 |
| ? | 未测试 |
| ✗ | 不可连接 |
| - | 自己（无意义） |

---

## 矩阵数据结构

```yaml
matrix:
  servers: [aliyun, node3, windows, local]
  
  cells:
    # [from][to] 格式
    aliyun:
      aliyun: {self: true}
      node3: {can_connect: true, type: tunnel, via: windows}
      windows: {can_connect: true, type: direct}
      local: {can_connect: true, type: direct}
    
    node3:
      aliyun: {can_connect: true, type: tunnel, via: windows}
      node3: {self: true}
      windows: {can_connect: true, type: direct}
      local: {can_connect: true, type: tunnel, via: aliyun}
    
    windows:
      aliyun: {can_connect: true, type: direct}
      node3: {can_connect: true, type: vpn}
      windows: {self: true}
      local: {can_connect: true, type: direct}
    
    local:
      aliyun: {can_connect: true, type: direct}
      node3: {can_connect: true, type: tunnel, via: aliyun}
      windows: {can_connect: true, type: direct}
      local: {self: true}
```

---

## 交互式矩阵 UI

### 布局设计

```
┌─────────────────────────────────────────────────────────────┐
│                    服务器网络拓扑矩阵                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   从 → 到    aliyun    node3    windows    local    phone   │
│   ┌─────────────────────────────────────────────────────┐  │
│   │ aliyun  │   -    │  ✓→    │   ✓→    │  ✓→    │  ✓→   │  │
│   │ node3   │  ✓←    │   -    │   ✓→    │  ✓→    │  ?    │  │
│   │ windows │  ✓←    │  ✓←    │    -    │  ✓→    │  ?    │  │
│   │ local   │  ✓←    │  ✓←    │   ✓←    │   -    │  ✓→   │  │
│   │ phone   │  ✓←    │   ?    │    ?    │  ✓←    │   -    │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐│
│ │ 选中：aliyun → node3                                     ││
│ │ 类型：tunnel (via windows)                               ││
│ │ 状态：active                                             ││
│ │ 延迟：50ms                                               ││
│ │                                                          ││
│ │ [测试连接] [重新配置] [删除连接] [查看详情]             ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ [保存拓扑] [导出配置] [测试全部] [添加服务器] [刷新状态]   │
└─────────────────────────────────────────────────────────────┘
```

### 交互操作

| 按键 | 操作 |
|------|------|
| ↑↓←→ | 移动选择 |
| Enter | 进入详情/配置 |
| Space | 切换连接状态 |
| d | 删除连接 |
| a | 添加新连接 |
| t | 测试连接 |
| s | 保存拓扑 |
| e | 导出配置 |
| r | 刷新状态 |
| q | 退出 |

---

## 矩阵计算

### 可达性计算

```python
def compute_reachability(matrix):
    """
    计算可达性矩阵（Warshall 算法）
    R[i][j] = True 表示 i 可到达 j
    """
    n = len(matrix)
    R = matrix.copy()
    
    for k in range(n):
        for i in range(n):
            for j in range(n):
                R[i][j] = R[i][j] or (R[i][k] and R[k][j])
    
    return R
```

### 连通性分析

```python
def analyze_connectivity(matrix):
    """
    分析网络连通性
    返回：强连通分量、孤立节点、桥接节点
    """
    # 强连通分量：互相可达的服务器组
    scc = find_strongly_connected_components(matrix)
    
    # 孤立节点：无法连接任何其他服务器
    isolated = find_isolated_nodes(matrix)
    
    # 桥接节点：断开会导致网络分裂
    bridges = find_bridge_nodes(matrix)
    
    return {
        "strongly_connected": scc,
        "isolated": isolated,
        "bridges": bridges
    }
```

---

## 矩阵视图模式

### 模式 1：连接状态视图

显示连接状态（active/inactive/error）

```
        aliyun    node3    windows    local
aliyun    -       🟢        🟢         🟢
node3    🟢        -        🟢         🟡
windows  🟢       🟢         -         🟢
local    🟢       🟡        🟢          -

🟢 active  🟡 inactive  🔴 error
```

### 模式 2：延迟视图

显示连接延迟

```
        aliyun    node3    windows    local
aliyun    -       50ms      10ms       20ms
node3    50ms      -        30ms       100ms
windows  10ms     30ms       -         15ms
local    20ms     100ms     15ms        -
```

### 模式 3：类型视图

显示连接类型

```
        aliyun    node3    windows    local
aliyun    -       tunnel    direct     direct
node3    tunnel    -        direct     tunnel
windows  direct   vpn        -         direct
local    direct   tunnel    direct      -
```

### 模式 4：信任等级视图

显示目标服务器的信任等级

```
        aliyun    node3    windows    local
aliyun    -       full      admin      guest
node3    full      -        admin      guest
windows  admin    admin      -         guest
local    guest    guest     guest       -
```

---

## 矩阵操作

### 批量测试

```bash
# 测试所有连接
topology matrix --test-all

# 测试指定行（从某服务器出发的所有连接）
topology matrix --test-from aliyun

# 测试指定列（到某服务器的所有连接）
topology matrix --test-to node3
```

### 批量配置

```bash
# 批量设置信任等级
topology matrix --set-trust node3 full

# 批量启用/禁用连接
topology matrix --disable-from local

# 批量设置跳板
topology matrix --set-via aliyun windows
```

### 导出

```bash
# 导出为 SSH config
topology matrix --export ssh-config

# 导出为 Ansible inventory
topology matrix --export ansible

# 导出为图片
topology matrix --export png
```