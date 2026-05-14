# API 接口规范 (API Specification)

## 概述

全自动模式使用 REST API 进行服务器注册和管理。

---

## API 端点

### 基础 URL

```
http://master-server:8888/api
```

---

## 服务器注册

### POST /servers/register

注册新服务器到主控节点。

**请求**：
```json
{
  "alias": "node3",
  "ip_public": null,
  "ip_private": "YOUR_TARGET_IP",
  "ip_vpn": "YOUR_WINDOWS_IP",
  "port": 5122,
  "user_default": "wuxiaoran",
  "public_key": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...",
  "trust_level": "full",
  "capabilities": ["vpn-gateway", "tunnel-endpoint"],
  "metadata": {
    "provider": "school",
    "description": "学校内网服务器"
  }
}
```

**响应**：
```json
{
  "success": true,
  "server_id": "node3",
  "message": "服务器已注册",
  "config": {
    "ssh_config": "Host node3\n    HostName YOUR_TARGET_IP\n    Port 5122\n    User wuxiaoran\n    IdentityFile ~/.ssh/id_node3",
    "test_command": "ssh node3 'hostname'"
  }
}
```

---

## 服务器查询

### GET /servers

列出所有注册的服务器。

**响应**：
```json
{
  "servers": [
    {
      "id": "aliyun",
      "alias": "阿里云主服务器",
      "status": "online",
      "trust_level": "full"
    },
    {
      "id": "node3",
      "alias": "学校内网服务器",
      "status": "online",
      "trust_level": "full"
    }
  ]
}
```

### GET /servers/{id}

获取服务器详情。

**响应**：
```json
{
  "id": "node3",
  "alias": "学校内网服务器",
  "ip_private": "YOUR_TARGET_IP",
  "port": 5122,
  "user_default": "wuxiaoran",
  "trust_level": "full",
  "capabilities": ["vpn-gateway", "tunnel-endpoint"],
  "connections": [
    {"from": "aliyun", "type": "tunnel", "via": "windows"},
    {"from": "local", "type": "tunnel", "via": "aliyun"}
  ],
  "status": "online",
  "last_seen": "2026-05-14T12:00:00Z"
}
```

---

## 连接管理

### POST /connections

建立新连接。

**请求**：
```json
{
  "from": "aliyun",
  "to": "node3",
  "type": "tunnel",
  "via": "windows",
  "auth_method": "key",
  "auth_user": "wuxiaoran"
}
```

**响应**：
```json
{
  "success": true,
  "connection_id": "aliyun-node3",
  "message": "连接已配置",
  "tunnel_config": {
    "command": "ssh -R 2223:YOUR_TARGET_IP:22 -N root@YOUR_JUMP_SERVER_IP",
    "local_port": 2223
  }
}
```

### DELETE /connections/{from}/{to}

删除连接。

**响应**：
```json
{
  "success": true,
  "message": "连接已删除"
}
```

### GET /connections/test/{from}/{to}

测试连接。

**响应**：
```json
{
  "success": true,
  "latency_ms": 50,
  "path": ["aliyun", "windows", "node3"],
  "tested_at": "2026-05-14T12:00:00Z"
}
```

---

## 拓扑导出

### GET /topology/export

导出拓扑配置。

**参数**：
- `format`: yaml/json/ssh-config/ansible

**响应** (format=yaml):
```yaml
topology:
  name: "my-servers"
  servers:
    - id: "aliyun"
    - id: "node3"
  connections:
    - from: "aliyun"
      to: "node3"
      type: "tunnel"
```

---

## 信任管理

### POST /trust

设置信任等级。

**请求**：
```json
{
  "from": "local",
  "to": "node3",
  "level": "admin",
  "reason": "项目需要管理权限"
}
```

**响应**：
```json
{
  "success": true,
  "requires_confirmation": true,
  "message": "信任请求已发送，等待目标服务器确认"
}
```

### POST /trust/confirm

确认信任请求。

**请求**：
```json
{
  "request_id": "trust-123",
  "confirm": true
}
```

---

## 注册令牌

### POST /tokens/generate

生成注册令牌。

**请求**：
```json
{
  "duration_hours": 24,
  "max_uses": 5,
  "trust_level": "user"
}
```

**响应**：
```json
{
  "token": "abc123def456",
  "expires_at": "2026-05-15T12:00:00Z",
  "uses_remaining": 5,
  "join_url": "http://master:8888/api/join/abc123def456"
}
```

### POST /join/{token}

使用令牌加入网络。

**请求**：
```json
{
  "alias": "new-server",
  "ip": "192.168.1.100",
  "port": 22,
  "public_key": "ssh-ed25519 ..."
}
```

---

## 状态监控

### GET /status

获取整体状态。

**响应**：
```json
{
  "servers_online": 3,
  "servers_total": 4,
  "connections_active": 5,
  "connections_total": 6,
  "alerts": [
    {
      "type": "connection_error",
      "server": "node3",
      "message": "隧道断开"
    }
  ]
}
```

### GET /status/{server_id}

获取服务器状态。

**响应**：
```json
{
  "id": "node3",
  "status": "online",
  "cpu_percent": 25,
  "memory_percent": 60,
  "disk_percent": 40,
  "connections_in": 2,
  "connections_out": 1,
  "last_seen": "2026-05-14T12:00:00Z"
}
```

---

## 认证

### API Key 认证

```bash
# 请求头
Authorization: Bearer <api_key>

# 获取 API Key
POST /auth/login
{
  "user": "admin",
  "password": "..."
}
```

### 令牌认证

注册令牌用于新服务器加入，无需 API Key。

---

## 错误响应

```json
{
  "success": false,
  "error": {
    "code": "SERVER_NOT_FOUND",
    "message": "服务器 'unknown' 不存在"
  }
}
```

**错误码**：
- `SERVER_NOT_FOUND`: 服务器不存在
- `CONNECTION_FAILED`: 连接测试失败
- `TOKEN_EXPIRED`: 注册令牌已过期
- `TRUST_DENIED`: 信任请求被拒绝
- `AUTH_FAILED`: 认证失败