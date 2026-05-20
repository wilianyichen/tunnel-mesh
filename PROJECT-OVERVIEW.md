# Tunnel Mesh 项目全景梳理

---

## 一、目标

让任意数量、任意网络环境的服务器之间建立 SSH 连接。
**无论网络多复杂，最终效果就是 `ssh 对方名字` 能通。**

---

## 二、每台设备的工具能力

### Linux（tunnel-mesh.sh）

```
[1] 导出身份卡       — 自动检测本机信息，输出给别人
[2] 导入身份卡       — 我是主，粘贴别人信息 → 建立连接契约
[3] 部署公钥         — 我是仆，粘贴别人信息 → 加公钥免密
[4] 审视契约         — 查看已有连接 + 显示隧道命令
[5] 废契             — 删除连接
[6] 配置向导         — 交互式引导
[7] 探寻路径         — 多跳路径计算
[8] 恢复配置         — 从 config.json 重建 SSH config
[9] 查看日志
[0] SSH 管理         — 管理 ~/.ssh/config
```

### Windows（tunnel-mesh.bat → tunnel-mesh.ps1）

```
[1] 导入隧道命令     — 粘贴 ssh -R ... → 自动创建计划任务 + 开机自启
[2] 导出身份卡       — 输出公钥给 Linux 部署
[3] 查看隧道状态     — 列出所有隧道 + 状态
[4] 启动所有隧道
[5] 停止所有隧道
[6] 删除隧道
[7] 测试连接
```

---

## 三、设计规范

| 规范 | 说明 |
|------|------|
| 降秩思维 | 只保留生成器（主仆关系 + 触达方式），砍掉派生概念 |
| 小白友好 | 每步有解释，emojii 图标，问什么答什么 |
| 双平台一致 | Linux .sh + Windows .ps1，功能对称 |
| 信息持久 | config.json + 单独文件，重启不丢 |
| 自愈能力 | 隧道命令存两处（JSON + 文件），一处坏了另一处可用 |
| 零引号地狱 | Windows 端 PowerShell 原生处理，不嵌套转义 |

---

## 四、信息流

### 4.1 每台服务器自动检测的信息

```
主机名、内网IP、公网IP(curl)、SSH端口、当前用户、SSH公钥、指纹
```

### 4.2 导出（输出）

```
===IDENTITY===
NAME=xxx   IP=xxx   PUBLIC_IP=xxx   PORT=xxx   USER=xxx   PUBKEY=xxx   FINGERPRINT=xxx
===END===
```

### 4.3 导入正向后（输入→输出）

```
输入：对方身份卡
TCP检测 → 可达/不可达
用户选：正向/反向 + 维持者
输出：
  → 本机 SSH config 条目
  → 维持者的隧道命令（ssh -R ...）
  → config.json 持久化
  → 对方公钥 → authorized_keys
```

### 4.4 Windows 导入（输入→输出）

```
输入：ssh -R ... 命令
输出：
  → tunnel-N.ps1（隧道循环脚本）
  → run-N.bat（wrapper）
  → Windows 计划任务（开机自启）
```

### 4.5 信息持久化位置

```
Linux:
  ~/.tunnel-mesh/config.json       ← 全部契约
  ~/.tunnel-mesh/tunnel-cmds/      ← 隧道命令文件（计划新增）
  ~/.ssh/config                    ← SSH 连接条目
  ~/.ssh/authorized_keys           ← 对方公钥

Windows:
  C:\tunnel-mesh\scripts\tunnel-*.ps1   ← 隧道脚本
  C:\tunnel-mesh\scripts\run-*.bat      ← wrapper
  %USERPROFILE%\.tunnel-mesh\tunnel-*.cmd  ← 隧道命令备份
  Task Scheduler\Tunnel-*               ← 计划任务
```

---

## 五、前置依赖

| 服务器 | 依赖 |
|--------|------|
| 任意 Linux | ssh, ssh-keygen, curl, python3（JSON解析） |
| Windows | OpenSSH Client, PowerShell 5.1+ |
| 中转/桥 | OpenSSH Server（如接收 ProxyJump） |

---

## 六、已遇到的问题和教训

| 问题 | 原因 | 方案 |
|------|------|------|
| 隧道命令没存到 config.json | Python 字符串里特殊字符 + `2>/dev/null` 吞错误 | 单独存文件，不用 JSON 装命令 |
| Windows 计划任务从未创建 | bat → PowerShell 4层引号转义全烂 | 重写为 .ps1，`Register-ScheduledTask` 原生 |
| `set /p` 取值带 `\r` | CRLF 换行符污染 | `!VAR:\r=!` |
| 阿里云公网IP检测失败 | `hostname -I` 只取到内网 VPC IP | `curl ifconfig.me` 获取公网 IP |
| Windows 导出无 PUBKEY 标签 | 格式不统一 | 导入侧同时兼容 PUBKEY= 和裸 ssh- 行 |
| 契约方向记反 | 导入=主 不直观 | 拆成 [2]导入(我是主) + [3]部署公钥(我是仆) |
| Windows 终端导入后关闭 | `pause >nul` 隐藏提示 | 去掉 `>nul` |
| JSON `\t` `\s` 非法转义 | Windows 路径反斜杠在 JSON 里是转义符 | 改命令行参数传递 |

---

## 七、待解决的问题

1. **隧道命令存储不可靠** — Python inline 容易断，需要改存文件
2. **config.json 无校验** — 写入后没验证，可能写了空/坏数据
3. **端口冲突检测不完整** — 三层检查只做了本机，没跨服务器
4. **没有隧道健康监控** — 不知道隧道是否真的在跑
5. **Windows 重启后计划任务可能丢失** — 没有恢复机制
6. **Linux 端没有「显示我的隧道命令给 Windows」的快捷方式** — 已加 [C] 但可更明显
7. **多跳路径没自动配置 ProxyJump** — 已有但用户不一定知道
8. **没有 `tunnel-mesh update` 自更新** — 每次手动 git pull

---

## 八、我没想到、需要考虑的问题

1. **公钥过期/泄露怎么办？** 需要密钥轮换功能
2. **多用户共享一台服务器？** 同 IP 不同账户已支持，但契约名会冲突
3. **防火墙/安全组变化？** 隧道端口可能被云服务商安全组拦截
4. **Windows 更新后计划任务失效？** 需要检查和自动修复
5. **config.json 损坏怎么办？** 需要从备份自动恢复
6. **大量服务器时性能？** graph.py 的 Dijkstra 在 100+ 节点时是否还快
7. **国际化？** 目前只支持中文，英文用户需要英文界面
8. **安全性审计？** 谁在什么时候导入了什么，需要操作日志
