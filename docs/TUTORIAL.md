# Tunnel Mesh 使用教程

Tunnel Mesh 让你轻松管理所有服务器的 SSH 连接。

**简单说**：选菜单、回答问题、粘贴文书、完成。

---

## 我该看哪个教程？

| 你的系统 | 看这篇 |
|----------|--------|
| Linux | [Linux 使用教程](TUTORIAL-LINUX.md) |
| Windows | [Windows 使用教程](TUTORIAL-WINDOWS.md) |

---

## 核心概念（只需要知道两个）

### 主仆关系

```
主（Master）= 你想连别人的时候，你是主
仆（Servant）= 被人连的那台服务器

每一条连接就是一个主仆关系。
双向连接 = 两条方向相反的主仆关系。
```

### 触达方式

```
正向 = 你能直接连到仆 → 不需要其他服务器帮忙
反向 = 你不能直接连仆 → 需要中间服务器帮忙转发
```

---

## 四种典型场景

| 场景 | 你在哪 | 目标在哪 | 教程章节 |
|------|--------|----------|----------|
| 连接外网服务器 | Linux | 阿里云 | Linux教程·场景1 |
| 连接内网服务器 | Windows | 校园网node3 | Windows教程·场景2 |
| 多级跳转连接 | Linux | 3层后的服务器 | Linux教程·场景3 |
| 让别人连你(仆端) | Windows | - | Windows教程·场景4 |

---

## 文件清单

| 文件 | 给谁看 |
|------|--------|
| `docs/TUTORIAL-LINUX.md` | Linux 用户 |
| `docs/TUTORIAL-WINDOWS.md` | Windows 用户 |
| `DESIGN.md` | 开发者 / Agent |
| `SKILL.md` | Agent |
| `README.md` | 所有人 |
