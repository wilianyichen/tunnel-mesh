# Contributing to Tunnel Mesh

感谢你的参与。

## 报告问题

- 使用 [GitHub Issues](https://github.com/wilianyichen/tunnel-mesh/issues)
- 描述预期行为和实际行为
- 附上运行环境（`ssh -V`、`python3 --version`、OS 类型）
- 如涉及隧道失败，提供 `tunnel-mesh --cmd health` 输出和 config.json 结构（脱敏后）

## 提 Pull Request

1. Fork 本仓库
2. 创建 feature 分支：`git checkout -b feat/your-feature`
3. 修改代码
4. 确保测试通过：`python3 tests/test_smoke.py -v`
5. 确保 shellcheck 无报错：`shellcheck scripts/*.sh scripts/lib/*.sh tunnel-mesh.sh`
6. 提交并推送：`git push origin feat/your-feature`
7. 创建 Pull Request to `main`

## 代码风格

### Shell
- 所有脚本以 `set -o pipefail` 开头
- 用 `shellcheck` 检查（允许已知误报加 `# shellcheck disable=SC...`）
- 函数名用小写 + 下划线

### Python
- 目标版本：Python 3.8+
- 用 `_sp.run(..., check=True)` 而非静默忽略子进程失败
- 配置数据操作统一走 `json.load`/`json.dump`，不拼接 JSON 字符串
- `tunnel_mesh.py` 是 CLI 入口，`scripts/lib/_json_op.py` 是 shell 可调用的轻量数据层

## 测试

- 冒烟测试：`python3 tests/test_smoke.py -v`
- 所有 CLI 命令在空配置下不应崩溃（退出码 0）
- 新增 fabric 相关逻辑需覆盖 fabric 测试

## Commit 规范

- 首行 ≤ 72 字符，中文或英文均可
- 优先描述 why 而非 what
- 示例：`修复 _fabric_op 健康检查假阳性：未检查 subprocess 退出码`
