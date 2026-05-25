#!/usr/bin/env python3
"""集成测试 — CLI 管道端到端验证"""
import json
import os
import sys
import tempfile
import unittest
import subprocess

TM_PY = os.path.join(os.path.dirname(__file__), "..", "scripts", "tunnel_mesh.py")


class TestIntegration(unittest.TestCase):
    """完整 CLI 管道测试，使用临时 HOME"""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.env = {**os.environ, "HOME": self.tmpdir}
        os.makedirs(os.path.join(self.tmpdir, ".tunnel-mesh"), exist_ok=True)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, TM_PY] + list(args),
            capture_output=True, text=True, timeout=10, env=self.env
        )

    def test_server_crud(self):
        """server-add → server-list → server-remove 完整 CRUD"""
        # add
        r = self._run("server-add", "node-a", "10.0.0.1", "22", "root")
        self.assertEqual(r.returncode, 0, f"add failed: {r.stderr}")

        # list contains node
        r = self._run("server-list")
        self.assertEqual(r.returncode, 0)
        self.assertIn("node-a", r.stdout)

        # add second node
        r = self._run("server-add", "node-b", "10.0.0.2", "22", "root")
        self.assertEqual(r.returncode, 0)

        # list contains both
        r = self._run("server-list")
        self.assertIn("node-a", r.stdout)
        self.assertIn("node-b", r.stdout)

        # remove node-a
        r = self._run("server-remove", "node-a")
        self.assertEqual(r.returncode, 0)

        # node-a gone
        r = self._run("server-list")
        self.assertNotIn("node-a", r.stdout)

    def test_edge_lifecycle(self):
        """edge-add → edge-list → edge-remove 边生命周期"""
        # setup servers
        self._run("server-add", "a", "10.0.0.1", "22", "root")
        self._run("server-add", "b", "10.0.0.2", "22", "root")

        # add edge
        r = self._run("edge-add", "a", "b", "forward", "2224",
                       "ssh -L 0.0.0.0:2224:localhost:22 b")
        self.assertEqual(r.returncode, 0, f"edge-add failed: {r.stderr}")

        # list edges
        r = self._run("edge-list")
        self.assertEqual(r.returncode, 0)
        self.assertIn("2224", r.stdout)

        # remove edge (edges is a list of dicts with 'id')
        cfg_path = os.path.join(self.tmpdir, ".tunnel-mesh", "config.json")
        with open(cfg_path) as f:
            config = json.load(f)
        edge_ids = [e["id"] for e in config.get("edges", [])]
        if edge_ids:
            r = self._run("edge-remove", edge_ids[0])
            self.assertEqual(r.returncode, 0)

    def test_port_allocation(self):
        """port-allocate 分配不重复"""
        r1 = self._run("port-allocate", "--no-json")
        self.assertEqual(r1.returncode, 0)
        port1 = r1.stdout.strip()

        r2 = self._run("port-allocate", "--no-json")
        self.assertEqual(r2.returncode, 0)
        port2 = r2.stdout.strip()

        self.assertNotEqual(port1, port2)
        # both should be valid port numbers
        self.assertTrue(port1.isdigit())
        self.assertTrue(port2.isdigit())

    def test_identity(self):
        """identity 不崩溃"""
        r = self._run("identity")
        self.assertEqual(r.returncode, 0)

    def test_viz_empty(self):
        """viz 空配置不崩溃"""
        r = self._run("viz")
        self.assertEqual(r.returncode, 0)

    def test_status_empty(self):
        """status 空配置不崩溃"""
        r = self._run("status")
        self.assertEqual(r.returncode, 0)

    def test_tutorial_pipeline(self):
        """tutorial pipeline: servers + edges + fabric → tutorial 输出"""
        # setup servers
        self._run("server-add", "aliyun", "8.131.61.234", "22", "root")
        self._run("server-add", "biolab", "10.16.82.202", "5122", "root")

        # create fabric.json with a test fabric
        fabric_data = {
            "fabrics": {
                "fab-0": {
                    "logical_edge": "biolab→aliyun",
                    "port": 2225,
                    "hops": [{
                        "seq": 0, "from": "biolab", "to": "aliyun",
                        "type": "reverse_tunnel", "port": 2225,
                        "cmd": "ssh -R 2225:localhost:22 root@8.131.61.234 -p 22"
                    }],
                    "maintainers": [{
                        "node": "biolab", "role": "runner",
                        "cmd": "ssh -R 2225:localhost:22 root@8.131.61.234 -p 22"
                    }]
                }
            }
        }
        fabric_path = os.path.join(self.tmpdir, ".tunnel-mesh", "fabric.json")
        with open(fabric_path, "w") as f:
            json.dump(fabric_data, f)

        r = self._run("tutorial")
        self.assertEqual(r.returncode, 0)

        # should reference fabric
        output = r.stdout + r.stderr
        self.assertTrue("fab-0" in output or "biolab" in output)

    def test_fabric_list_empty(self):
        """fabric-list 空配置不崩溃"""
        r = self._run("fabric-list")
        self.assertEqual(r.returncode, 0)

    def test_path_usage(self):
        """path 无参数显示用法"""
        r = self._run("path")
        self.assertIn("用法", r.stderr)

    def test_help(self):
        """--help 正常输出"""
        r = self._run("--help")
        self.assertEqual(r.returncode, 0)
        self.assertIn("Tunnel Mesh", r.stdout)


class TestConfigCorruption(unittest.TestCase):
    """配置损坏恢复 — 集成级别"""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.env = {**os.environ, "HOME": self.tmpdir}
        os.makedirs(os.path.join(self.tmpdir, ".tunnel-mesh"), exist_ok=True)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, TM_PY] + list(args),
            capture_output=True, text=True, timeout=10, env=self.env
        )

    def test_truncated_json_no_crash(self):
        """截断 JSON: server-list 不崩溃"""
        cfg = os.path.join(self.tmpdir, ".tunnel-mesh", "config.json")
        with open(cfg, "w") as f:
            f.write('{"servers": {"a": {"ip": "1.2.3.4"')
        r = self._run("server-list")
        # should not crash (may return non-zero but no traceback)
        self.assertNotIn("Traceback", r.stderr)

    def test_corrupt_fabric_no_crash(self):
        """损坏 fabric.json: fabric-list 不崩溃"""
        fabric_path = os.path.join(self.tmpdir, ".tunnel-mesh", "fabric.json")
        with open(fabric_path, "w") as f:
            f.write("{broken-fabric")
        r = self._run("fabric-list")
        self.assertNotIn("Traceback", r.stderr)

    def test_empty_config_no_crash(self):
        """空 config: server-list 正常"""
        cfg = os.path.join(self.tmpdir, ".tunnel-mesh", "config.json")
        with open(cfg, "w") as f:
            f.write("")
        r = self._run("server-list")
        self.assertEqual(r.returncode, 0)

    def test_concurrent_writes(self):
        """两个 server-add 顺序执行不丢数据"""
        self._run("server-add", "s1", "10.0.0.1", "22", "root")
        self._run("server-add", "s2", "10.0.0.2", "22", "root")
        r = self._run("server-list")
        self.assertIn("s1", r.stdout)
        self.assertIn("s2", r.stdout)


class TestDeployWindows(unittest.TestCase):
    """deploy-windows 命令测试"""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.env = {**os.environ, "HOME": self.tmpdir}
        os.makedirs(os.path.join(self.tmpdir, ".tunnel-mesh"), exist_ok=True)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, TM_PY] + list(args),
            capture_output=True, text=True, timeout=10, env=self.env
        )

    def test_no_server(self):
        """server 不存在时错误退出"""
        r = self._run("deploy-windows", "nonexistent")
        self.assertNotEqual(r.returncode, 0)

    def test_no_args(self):
        """无参数时显示用法并错误退出"""
        r = self._run("deploy-windows")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("用法", r.stderr)

    def test_linux_target_rejected(self):
        """目标检测为非 Windows 时拒绝部署"""
        # 添加一个 Linux server（指向空 IP，OS 检测会超时返回 unknown）
        self._run("server-add", "test-linux", "127.0.0.2", "22", "root")
        r = self._run("deploy-windows", "test-linux")
        self.assertNotEqual(r.returncode, 0)
        # 应该提示"不是 Windows 机器"
        output = r.stdout + r.stderr
        self.assertTrue("不是 Windows" in output or "仅支持 Windows" in output)

    def test_help_shows_command(self):
        """--help 显示 deploy-windows 命令"""
        r = self._run("--help")
        self.assertEqual(r.returncode, 0)
        self.assertIn("deploy-windows", r.stdout)


class TestDetectTargetOS(unittest.TestCase):
    """_detect_target_os 单元测试"""

    def setUp(self):
        # 导入函数
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
        from tunnel_mesh import _detect_target_os
        self._detect = _detect_target_os

    def test_unknown_on_unreachable(self):
        """不可达 IP 返回 unknown"""
        result = self._detect("192.0.2.1", 22, "root")
        self.assertEqual(result, "unknown")

    def test_windows_detection_order(self):
        """Windows 检测优先于 Linux（cmd /c 在 Windows 上成功）"""
        # 此测试依赖实际网络，仅在 CI 或真实环境中有效
        # 本地运行时可跳过
        result = self._detect("10.16.96.0", 22, "wilia")
        # 可能是 windows 或 unknown（网络不通时）
        self.assertIn(result, ("windows", "unknown"))


class TestJsonOutput(unittest.TestCase):
    """--json 标志测试：所有命令输出有效 JSON {status, data/error}"""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.env = {**os.environ, "HOME": self.tmpdir}
        os.makedirs(os.path.join(self.tmpdir, ".tunnel-mesh"), exist_ok=True)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, TM_PY] + list(args),
            capture_output=True, text=True, timeout=10, env=self.env
        )

    def _json(self, *args):
        """运行命令并解析 JSON"""
        r = self._run(*args)
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return {"_parse_error": True, "_stdout": r.stdout, "_stderr": r.stderr, "_rc": r.returncode}

    # ---- 只读命令 ----

    def test_server_list_json(self):
        self._run("server-add", "s1", "10.0.0.1", "22", "root")
        j = self._json("server-list", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertIn("s1", j["data"]["servers"])

    def test_server_exists_json(self):
        self._run("server-add", "s1", "10.0.0.1", "22", "root")
        j = self._json("server-exists", "s1", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertTrue(j["data"]["exists"])

        j = self._json("server-exists", "nonexistent", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertFalse(j["data"]["exists"])

    def test_edge_list_json(self):
        self._run("server-add", "a", "10.0.0.1", "22", "root")
        self._run("server-add", "b", "10.0.0.2", "22", "root")
        self._run("edge-add", "a", "b", "forward", "2224", "ssh -L 2224:localhost:22 b")
        j = self._json("edge-list", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertIsInstance(j["data"]["edges"], list)
        self.assertGreaterEqual(len(j["data"]["edges"]), 1)

    def test_port_allocate_json(self):
        j = self._json("port-allocate", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertIn("port", j["data"])
        self.assertTrue(str(j["data"]["port"]).isdigit())

    def test_port_is_free_json(self):
        j = self._json("port-is-free", "29999", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertIn("free", j["data"])

    def test_status_json(self):
        j = self._json("status", "--json")
        self.assertEqual(j["status"], "ok")

    def test_health_json(self):
        j = self._json("health", "--json")
        self.assertEqual(j["status"], "ok")

    def test_identity_json(self):
        j = self._json("identity", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertIn("hostname", j["data"])

    def test_fabric_list_json(self):
        j = self._json("fabric-list", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertIn("fabrics", j["data"])

    def test_fabric_health_json(self):
        j = self._json("fabric-health", "--json")
        self.assertEqual(j["status"], "ok")

    def test_viz_json(self):
        """viz --json 输出结构化数据"""
        j = self._json("viz", "--json")
        self.assertEqual(j["status"], "ok")

    def test_unknown_command_json(self):
        r = self._run("nonexistent-cmd", "--json")
        self.assertNotEqual(r.returncode, 0)
        j = json.loads(r.stderr)
        self.assertEqual(j["status"], "error")

    # ---- 写命令 ----

    def test_server_add_json(self):
        j = self._json("server-add", "s1", "10.0.0.1", "22", "root", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertEqual(j["data"]["name"], "s1")

    def test_server_add_json_error(self):
        r = self._run("server-add", "--json")
        self.assertNotEqual(r.returncode, 0)
        j = json.loads(r.stderr)
        self.assertEqual(j["status"], "error")

    def test_server_remove_json(self):
        self._run("server-add", "s1", "10.0.0.1", "22", "root")
        j = self._json("server-remove", "s1", "--json")
        self.assertEqual(j["status"], "ok")

    def test_edge_add_remove_json(self):
        self._run("server-add", "a", "10.0.0.1", "22", "root")
        self._run("server-add", "b", "10.0.0.2", "22", "root")

        j = self._json("edge-add", "a", "b", "forward", "2224",
                       "ssh -L 2224:localhost:22 b", "--json")
        self.assertEqual(j["status"], "ok")

        # 查找 edge id 并删除
        j2 = self._json("edge-list", "--json")
        edge_ids = [e["id"] for e in j2["data"].get("edges", [])]
        if edge_ids:
            j3 = self._json("edge-remove", edge_ids[0], "--json")
            self.assertEqual(j3["status"], "ok")

    def test_key_deploy_json_no_key(self):
        """key-deploy 不带 --key 参数时的 JSON 错误"""
        self._run("server-add", "s1", "10.0.0.1", "22", "root")
        r = self._run("key-deploy", "s1", "--json")
        # key-deploy 需要 --key 或 id_ed25519.pub 存在
        self.assertIn("status", json.loads(r.stderr) if r.returncode != 0 else json.loads(r.stdout))

    def test_deploy_windows_json_error(self):
        """deploy-windows --json 错误输出"""
        r = self._run("deploy-windows", "--json")
        self.assertNotEqual(r.returncode, 0)
        j = json.loads(r.stderr)
        self.assertEqual(j["status"], "error")


class TestPhase2Commands(unittest.TestCase):
    """Phase 2: discover, quickstart, ensure 集成测试"""

    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.env = {**os.environ, "HOME": self.tmpdir}
        os.makedirs(os.path.join(self.tmpdir, ".tunnel-mesh"), exist_ok=True)

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def _run(self, *args):
        return subprocess.run(
            [sys.executable, TM_PY] + list(args),
            capture_output=True, text=True, timeout=10, env=self.env
        )

    def _json(self, *args):
        r = self._run(*args)
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            return {"_parse_error": True, "_stdout": r.stdout, "_stderr": r.stderr}

    # ---- discover ----

    def test_discover_empty(self):
        """discover 空配置不崩溃"""
        j = self._json("discover", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertIn("suggestions", j["data"])

    def test_discover_with_servers(self):
        """discover 2 个服务器生成建议"""
        self._run("server-add", "a", "10.0.0.1", "22", "root")
        self._run("server-add", "b", "10.0.0.2", "22", "root")
        j = self._json("discover", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertGreaterEqual(len(j["data"]["suggestions"]), 1)

    def test_discover_human_readable(self):
        """discover --no-json 输出人类可读文本"""
        self._run("server-add", "a", "10.0.0.1", "22", "root")
        self._run("server-add", "b", "10.0.0.2", "22", "root")
        r = self._run("discover", "--no-json")
        self.assertEqual(r.returncode, 0)
        self.assertIn("拓扑探测", r.stdout)

    # ---- quickstart ----

    def test_quickstart_json(self):
        """quickstart --non-interactive --json 输出步骤信息"""
        self._run("server-add", "a", "10.0.0.1", "22", "root")
        self._run("server-add", "b", "10.0.0.2", "22", "root")
        # quickstart 会 SSH 探测两个服务器（每个 ConnectTimeout=5s × 多次重试），需要更长超时
        r = subprocess.run(
            [sys.executable, TM_PY, "quickstart", "--non-interactive", "--json"],
            capture_output=True, text=True, timeout=60, env=self.env
        )
        j = json.loads(r.stdout)
        self.assertEqual(j["status"], "ok")
        self.assertIn("steps", j["data"])
        self.assertGreaterEqual(len(j["data"]["steps"]), 2)

    def test_quickstart_empty(self):
        """quickstart 空配置显示提示"""
        r = self._run("quickstart", "--non-interactive")
        self.assertEqual(r.returncode, 0)

    # ---- ensure ----

    def test_ensure_server_create(self):
        """ensure server 创建新服务器"""
        j = self._json("ensure", "server", "s1", "10.0.0.1", "22", "root", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertEqual(j["data"]["name"], "s1")
        self.assertEqual(j["data"]["action"], "created")

    def test_ensure_server_noop(self):
        """ensure server 已存在时幂等"""
        self._run("server-add", "s1", "10.0.0.1", "22", "root")
        j = self._json("ensure", "server", "s1", "10.0.0.1", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertEqual(j["data"]["action"], "noop")

    def test_ensure_edge_create(self):
        """ensure edge 创建新边"""
        self._run("server-add", "a", "10.0.0.1", "22", "root")
        self._run("server-add", "b", "10.0.0.2", "22", "root")
        j = self._json("ensure", "edge", "a", "b", "forward", "2224",
                       "ssh -L 2224:localhost:22 b", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertEqual(j["data"]["action"], "created")

    def test_ensure_edge_noop(self):
        """ensure edge 已存在时幂等"""
        self._run("server-add", "a", "10.0.0.1", "22", "root")
        self._run("server-add", "b", "10.0.0.2", "22", "root")
        self._run("ensure", "edge", "a", "b", "forward", "2224",
                  "ssh -L 2224:localhost:22 b")
        j = self._json("ensure", "edge", "a", "b", "forward", "2224",
                       "ssh -L 2224:localhost:22 b", "--json")
        self.assertEqual(j["status"], "ok")
        self.assertEqual(j["data"]["action"], "noop")

    def test_ensure_usage_error(self):
        """ensure 无参数时 JSON 错误"""
        r = self._run("ensure", "--json")
        self.assertNotEqual(r.returncode, 0)
        j = json.loads(r.stderr)
        self.assertEqual(j["status"], "error")

    def test_ensure_unknown_type(self):
        """ensure 未知资源类型"""
        r = self._run("ensure", "nonexistent", "x", "--json")
        self.assertNotEqual(r.returncode, 0)

    def test_ensure_key_no_pubkey(self):
        """ensure key 无公钥时不崩溃"""
        # 临时删除公钥文件来模拟
        self._run("server-add", "s1", "10.0.0.1", "22", "root")
        r = self._run("ensure", "key", "s1", "--json")
        # 可能成功（如果有公钥且网络可达）或失败（无公钥/不可达）
        # 至少不能是 traceback
        self.assertNotIn("Traceback", r.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
