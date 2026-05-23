# Tunnel Mesh 架构设计

## 问题

几台 Linux 服务器分散在不同网络中（有的有公网 IP，有的在 NAT 后面），需要让它们彼此能 SSH 连接。每台机器只知道自己能连到谁，全局拓扑未知。

## 核心思想: 双层图

逻辑图和物理连接分离：

```
┌──────────────────────────────────────────────────────┐
│                    逻辑层 (config.json)               │
│                                                      │
│  节点 = 登录目标服务器                                 │
│  边   = "可否到达" (含 Dijkstra 权重)                  │
│                                                      │
│  master ──1.0──→ servant                             │
│    │                                               │
│    └──1.5──→ note3 (经 2 跳隧道)                     │
│                                                      │
├──────────────────────────────────────────────────────┤
│                    物理层 (fabric.json)               │
│                                                      │
│  节点 = 所有参与机器（含中转 + 维持者）                 │
│  边   = ssh -L / ssh -R / 直连                       │
│                                                      │
│  master ←─ssh-R─ win-pc ──ssh-L──→ note3             │
│           (跳1)            (跳2)                      │
│                                                      │
│  transit_nodes: { win-pc: {ip, port, user}}          │
│  maintainers: [{node: win-pc, cmd: "ssh -R..."}]     │
└──────────────────────────────────────────────────────┘
```

## 为什么分两层

1. **图算法干净**: Dijkstra 只管"能不能到"，不管"怎么到"
2. **中转节点不污染图**: 中间跳转服务器只出现在物理层
3. **一对多**: 一条逻辑边可以分解为多条物理跳
4. **独立管理**: 物理连接可以独立启停、健康检查，不影响逻辑拓扑

## 数据模型

### config.json

```json
{
  "servers": {
    "master": {"ip": "10.0.0.1", "port": 22, "user": "root", "pubkey": "..."}
  },
  "edges": [{
    "id": "master→servant",
    "from": "master", "to": "servant",
    "type": "reverse",
    "fabric_id": "fab-20260522-001",
    "weight": 1.5
  }],
  "ports": {"used": [2201], "next": 2202}
}
```

### fabric.json

```json
{
  "fabrics": {
    "fab-20260522-001": {
      "id": "fab-20260522-001",
      "logical_edge": "master→servant",
      "port": 2201,
      "hops": [
        {"seq": 0, "from": "master", "to": "win-pc",
         "type": "reverse_tunnel", "cmd": "ssh -R 2201:...", "runner": "win-pc"},
        {"seq": 1, "from": "win-pc", "to": "servant",
         "type": "forward_tunnel", "cmd": "ssh -L 2201:...", "runner": "win-pc"}
      ],
      "transit_nodes": {
        "win-pc": {"ip": "192.168.1.100", "port": 22, "user": "admin"}
      },
      "maintainers": [
        {"node": "win-pc", "role": "runner", "cmd": "ssh -R ...", "persist": "manual"}
      ]
    }
  }
}
```

## 隧道模型: 统一端口

整条链路共用同一个端口号 P：

```
跳1: master 的 localhost:P ─→ I1:22
跳2: I1 的 localhost:P    ─→ I2:22
跳3: I2 的 localhost:P    ─→ servant:22
```

每台机器的 `localhost:P` 是独立的，所以同端口号不冲突。

### 隧道类型

| 类型 | 命令 | 运行者 | 效果 |
|------|------|--------|------|
| forward_direct | 无（直连） | — | 首跳直接 SSH |
| forward_tunnel | `ssh -L P:next_ip:22 user@next` | 上一跳 | prev 的 localhost:P → next:22 |
| reverse_tunnel | `ssh -R P:localhost:22 user@prev` | 下一跳 | prev 的 localhost:P → next:22 |

## SSH 连接方式

### ProxyCommand（推荐，自动）

```ssh-config
Host note3
    ProxyCommand ssh -W %h:%p Windows
    HostName localhost
    Port 2201
```

`ssh note3` 自动走完整个链。`ssh -W` 确保目标地址在跳转主机上解析。

### 嵌套 SSH（备选，只需邻居公钥）

```bash
ssh -t Windows "ssh note3"
```

每节点只需要存直接邻居的公钥。

## 递归建边流程

```
build_edge_chain(curr, servant, port, depth):
  1. 如果 curr == servant → 返回成功
  2. 如果 depth >= MAX → 返回失败
  3. 问: curr → servant 的方向？
     - 正向: add_hop(forward)
     - 反向: add_hop(reverse)
     - 都不能: 引入中间节点 → 递归
```

## 安全性

- 所有 Python 调用通过 argv 传参，永不拼入代码字符串
- 身份卡含 SHA256 校验和，防篡改
- SSH config 和 authorized_keys 自动设 chmod 600/700
- 配置文件仅本用户可读 (`~/.tunnel-mesh/`)

## 文件布局

```
tunnel-mesh.sh             主入口
scripts/
├── phase1-key.sh          密钥管理
├── phase2-edge.sh         经典建边
├── phase2-recursive.sh    递归建边
├── phase3-tunnel.sh       Fabric 管理中心
├── ssh-config.sh          SSH config 工具
├── graph.py               Dijkstra 引擎
├── migrate-v3.sh          数据迁移
└── lib/
    ├── config.sh          config.json 操作
    ├── detect.sh          身份检测
    ├── fabric.sh          fabric.json 操作
    ├── _fabric_op.py      fabric.json Python 引擎
    ├── graph.sh           路径探寻 + 拓扑
    ├── _json_op.py        config.json Python 引擎
    ├── network.sh         TCP 可达性
    └── tunnel-builder.sh  隧道命令生成
```
