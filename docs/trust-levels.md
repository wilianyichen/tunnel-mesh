# 信任等级定义 (Trust Levels)

## 概述

信任等级定义了服务器间的权限关系，决定了可以执行的操作范围。

---

## 信任等级分类

### Level 1: full（完全信任）

**定义**：完全信任，可执行任意操作

**权限范围**：
- SSH 登录（root/admin 用户）
- 执行任意命令
- 文件读写（任意路径）
- 系统管理（重启、安装软件）
- Docker 管理
- 网络配置

**典型场景**：
- 个人服务器
- 主控节点
- 开发环境

**配置示例**：
```yaml
server:
  id: "aliyun"
  trust_level: "full"
  users:
    - name: "root"
      role: "admin"
```

---

### Level 2: admin（管理员）

**定义**：管理员权限，可执行管理操作但有限制

**权限范围**：
- SSH 登录（指定用户）
- 执行管理命令（sudo 范围内）
- 文件读写（指定路径）
- 服务管理（systemctl）
- Docker 使用
- 日志查看

**限制**：
- 不能修改系统配置
- 不能安装/卸载软件
- 不能修改防火墙规则

**典型场景**：
- 团队共享服务器
- 生产环境服务器
- 测试环境

**配置示例**：
```yaml
server:
  id: "team-server"
  trust_level: "admin"
  users:
    - name: "admin"
      role: "admin"
      sudo_allowed: ["systemctl", "docker", "nginx"]
```

---

### Level 3: user（普通用户）

**定义**：普通用户权限，只能执行日常操作

**权限范围**：
- SSH 登录（普通用户）
- 执行用户级命令
- 文件读写（用户目录）
- 查看日志（只读）
- 运行用户程序

**限制**：
- 不能使用 sudo
- 不能访问系统目录
- 不能修改服务配置

**典型场景**：
- 共享开发环境
- 协作项目服务器
- CI/CD runner

**配置示例**：
```yaml
server:
  id: "dev-server"
  trust_level: "user"
  users:
    - name: "developer"
      role: "user"
      home: "/home/developer"
```

---

### Level 4: guest（访客）

**定义**：访客权限，只能查看

**权限范围**：
- SSH 登录（受限用户）
- 查看文件（只读）
- 查看日志（只读）
- 查看状态信息

**限制**：
- 不能执行任何写操作
- 不能复制文件
- 只能访问指定目录

**典型场景**：
- 临时访问
- 审计检查
- 演示环境

**配置示例**：
```yaml
server:
  id: "demo-server"
  trust_level: "guest"
  users:
    - name: "guest"
      role: "guest"
      allowed_paths: ["/var/log", "/home/demo"]
```

---

## 权限矩阵

```
┌─────────────────────────────────────────────────────────────┐
│ 操作                    │ full │ admin │ user │ guest │      │
├─────────────────────────────────────────────────────────────┤
│ SSH 登录                │  ✓   │   ✓   │  ✓   │  ✓   │      │
│ 执行任意命令            │  ✓   │   ✗   │  ✗   │  ✗   │      │
│ sudo 命令               │  ✓   │   ✓   │  ✗   │  ✗   │      │
│ 文件读写（任意路径）    │  ✓   │   ✗   │  ✗   │  ✗   │      │
│ 文件读写（用户目录）    │  ✓   │   ✓   │  ✓   │  ✗   │      │
│ 文件只读                │  ✓   │   ✓   │  ✓   │  ✓   │      │
│ 系统重启                │  ✓   │   ✗   │  ✗   │  ✗   │      │
│ 安装软件                │  ✓   │   ✗   │  ✗   │  ✗   │      │
│ Docker 管理             │  ✓   │   ✓   │  ✗   │  ✗   │      │
│ 服务管理（systemctl）   │  ✓   │   ✓   │  ✗   │  ✗   │      │
│ 查看日志                │  ✓   │   ✓   │  ✓   │  ✓   │      │
│ 网络配置                │  ✓   │   ✗   │  ✗   │  ✗   │      │
└─────────────────────────────────────────────────────────────┘
```

---

## 信任等级配置

### 服务器端配置

```yaml
# ~/.hermes/topology/servers/node3.yaml

server:
  id: "node3"
  trust_level: "full"
  
  # 用户配置
  users:
    - name: "root"
      role: "admin"
      key_file: "id_node3_root"
      
    - name: "wuxiaoran"
      role: "admin"
      key_file: "id_node3"
      
    - name: "hermes"
      role: "agent"
      key_file: "id_hermes_agent"
      # agent 用户有特殊权限
      capabilities:
        - "read-cognitive-system"
        - "update-cognitive-system"
  
  # 权限边界
  boundaries:
    # admin 用户可执行的操作
    admin_allowed_commands:
      - "systemctl *"
      - "docker *"
      - "rsync *"
      - "scp *"
    
    # 禁止的操作
    forbidden_commands:
      - "rm -rf /"
      - "mkfs"
      - "dd *"
```

### 客户端配置

```yaml
# ~/.hermes/topology/servers/local.yaml

server:
  id: "local"
  
  # 对其他服务器的信任等级声明
  trust_declarations:
    aliyun:
      level: "full"
      reason: "个人主服务器"
      
    node3:
      level: "full"
      reason: "学校内网服务器，完全信任"
      
    windows:
      level: "admin"
      reason: "跳板机器，只用于隧道"
```

---

## 信任等级变更

### 提升信任等级

```bash
# 需要双方确认
topology trust --upgrade node3 --to admin --reason "项目需要"

# 输出确认信息
# 目标服务器 node3 收到请求后需要确认
```

### 降低信任等级

```bash
# 单方面降低
topology trust --downgrade node3 --to user --reason "项目结束"
```

### 临时信任

```bash
# 设置临时信任（有效期）
topology trust --temp node3 --level admin --duration 24h
```

---

## 安全考虑

### 最小权限原则

- 默认使用最低信任等级
- 只在必要时提升
- 定期审查信任等级

### 信任链验证

```
A 信任 B (level: full)
B 信任 C (level: admin)
问：A 对 C 的信任等级？

答案：取最小值 = admin
```

### 信任等级审计

```bash
# 查看所有信任关系
topology trust --audit

# 输出
# aliyun → node3: full (since 2026-05-01)
# local → aliyun: full (since 2026-05-01)
# local → node3: admin (since 2026-05-10)
```