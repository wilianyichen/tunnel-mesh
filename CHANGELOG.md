# Changelog

## [3.0.0] — 2026-05-22

### 新增
- **双层架构**: config.json（逻辑图）+ fabric.json（物理连接层）完全解耦
- Fabric 管理系统：中转节点、维持者、外部维持者独立数据模型
- 双重拓扑可视化：逻辑拓扑（登录目标图）+ 物理拓扑（完整连接图）
- `--help` / `--version` CLI 参数支持
- 首次运行引导：空配置时自动显示欢迎页
- 旧数据自动检测并提示迁移
- 一键安装脚本 `install.sh`

### 修复
- **关键修复**: 多跳隧道中 `ProxyJump` 改为 `ProxyCommand ssh -W %h:%p`，解决目标地址在跳转主机上解析的问题
- `config_save` JSON 校验失败时自动从备份恢复
- CRLF 自动检测修复（Windows 编辑后 Linux 运行兼容）
- `config_json` 从过期变量读取的 bug

### 改进
- 全链路 `set -o pipefail` 确保管道错误传播
- Ctrl+C trap 处理器，优雅中断递归建边
- 递归建边空输入校验（节点名、IP 地址不可为空）
- 部署指南平台检测（Windows → Task Scheduler，Linux → systemd）
- shellcheck 静态分析清零
- 统一错误处理模式（所有 Python 调用点）
- README 重写（30秒快速开始 + 3 种典型场景）
- 新增 FILES.md（项目文件地图）+ docs/ARCHITECTURE.md

## [2.0.0] — 2026-05-21

### 新增
- 递归建边：自动寻找中间节点构建多跳链路
- 身份卡 v1 格式 + SHA256 校验
- 反向隧道支持（ssh -R）
- 5 阶段信任模型：加密信任 → 网络信任 → 维持信任 → 审视信任 → 撤销信任
- 统一端口模型：整条链路共享一个端口
- Dijkstra 最短路径搜索

### 平台支持
- Linux: Bash 脚本全套
- Windows: PowerShell 注册隧道 + .bat 启动器

## [1.0.0] — 2026-05-20

### 新增
- 初始版本：单跳 SSH 隧道连接
- 身份检测（自动识别本地/公网 IP）
- SSH 密钥生成与交换
- ~/.ssh/config 管理
- 端口池自动分配
- 图可视化（Graphviz DOT 输出）
