#!/usr/bin/env python3
"""冒烟测试 — 验证核心命令不崩溃，兼容旧格式 config"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts", "lib"))

# 用临时配置覆盖默认路径
os.environ["HOME"] = tempfile.mkdtemp()
os.makedirs(os.path.expanduser("~/.tunnel-mesh"), exist_ok=True)


def set_config(data):
    """写入临时 config.json"""
    path = os.path.expanduser("~/.tunnel-mesh/config.json")
    with open(path, "w") as f:
        json.dump(data, f)


class TestDataCompat(unittest.TestCase):
    """数据兼容性：旧格式、空文件、损坏文件"""

    def test_empty_config(self):
        set_config({})
        from _json_op import load
        d = load()
        self.assertIn("servers", d)
        self.assertIn("edges", d)

    def test_missing_name_field(self):
        """旧版 server_add 不写 name 字段"""
        set_config({"servers": {"s1": {"ip": "1.2.3.4", "port": 22}}, "edges": []})
        from _json_op import load
        d = load()
        self.assertEqual(d["servers"]["s1"]["name"], "s1")

    def test_corrupt_json(self):
        import tempfile
        cfg = os.path.expanduser("~/.tunnel-mesh/config.json")
        with open(cfg, "w") as f:
            f.write("{broken")
        from _json_op import load
        d = load()
        self.assertIn("servers", d)

    def test_missing_config_file(self):
        p = os.path.expanduser("~/.tunnel-mesh/config.json")
        if os.path.exists(p):
            os.remove(p)
        from _json_op import load
        d = load()
        self.assertIn("servers", d)

    def test_old_format_hosts_links(self):
        """aliyun 旧格式: hosts/links 键"""
        set_config({"hosts": {"a": {"HostName": "1.1.1.1", "Port": 22}}, "links": {}})
        from _json_op import load
        d = load()
        # 旧格式不匹配 → 重置为默认
        self.assertIn("servers", d)

    def test_edge_list_no_crash(self):
        set_config({"servers": {"s1": {"ip": "1.2.3.4", "port": 22}}, "edges": [], "ports": {"used": [], "next": 2201}})
        # 模拟 cmd_server_list 逻辑
        from _json_op import load
        d = load()
        for name, val in d.get("servers", {}).items():
            _ = val["name"]  # 不应 KeyError


class TestRegressionFixtures(unittest.TestCase):
    """回归测试：真实旧格式 config 兼容"""

    def setUp(self):
        self.fixtures_dir = os.path.join(os.path.dirname(__file__), "fixtures")

    def _load_fixture(self, name):
        with open(os.path.join(self.fixtures_dir, name)) as f:
            return json.load(f)

    def test_fixture_v1_missing_name(self):
        """旧格式 v1: servers 值缺 name 字段"""
        data = self._load_fixture("old_v1_missing_name.json")
        set_config(data)
        from _json_op import load
        d = load()
        for key, val in d.get("servers", {}).items():
            self.assertIn("name", val, f"server {key} missing name")
            self.assertEqual(val["name"], key)

    def test_fixture_v2_hosts_links(self):
        """旧格式 v2: hosts/links 键（兼容降级）"""
        data = self._load_fixture("old_v2_hosts_links.json")
        set_config(data)
        from _json_op import load
        d = load()
        self.assertIn("servers", d)  # 应为默认结构

    def test_fixture_v3_empty(self):
        """空 config → 默认结构"""
        data = self._load_fixture("old_v3_empty.json")
        set_config(data)
        from _json_op import load
        d = load()
        self.assertIn("servers", d)
        self.assertIn("edges", d)
        self.assertIn("ports", d)


class TestReachabilityMerge(unittest.TestCase):
    """可达矩阵合并"""

    def setUp(self):
        set_config({"servers": {"a": {"ip": "10.0.0.1", "port": 22}, "b": {"ip": "10.0.0.2", "port": 22}}, "edges": [], "ports": {"used": [], "next": 2201}})

    def test_merge_v1_format(self):
        from _reachability import merge_reports
        reports = [
            {"from": "a", "from_ip": "10.0.0.1", "results": [{"target": "b", "ip": "10.0.0.2", "port": 22, "reachable": True}]},
            {"from": "b", "from_ip": "10.0.0.2", "results": [{"target": "a", "ip": "10.0.0.1", "port": 22, "reachable": False}]},
        ]
        matrix, nodes, ips, ports, probed, _ = merge_reports(reports)
        self.assertIn(("a", "b"), matrix)
        self.assertTrue(matrix[("a", "b")].get("22"))

    def test_merge_v2_format(self):
        from _reachability import merge_reports
        reports = [
            {"from": "a", "from_ip": "10.0.0.1", "probed_ports": [22, 80],
             "results": [{"target": "b", "ip": "10.0.0.2", "default_port": 22,
                          "ports": {"22": {"reachable": False, "error": "timeout"},
                                    "80": {"reachable": True, "latency_ms": 5}}}]},
            {"from": "b", "from_ip": "10.0.0.2", "probed_ports": [22, 80],
             "results": [{"target": "a", "ip": "10.0.0.1", "default_port": 22,
                          "ports": {"22": {"reachable": True, "latency_ms": 3},
                                    "80": {"reachable": False, "error": "timeout"}}}]},
        ]
        matrix, nodes, ips, ports, probed, _ = merge_reports(reports)
        self.assertIn(80, probed)
        self.assertIn("80", matrix[("a", "b")])


class TestEdgeRecommend(unittest.TestCase):
    """边推荐逻辑"""

    def test_proxyjump_detection(self):
        from _reachability import recommend_edges_v2, find_proxyjump_candidates
        matrix = {
            ("a", "c"): {"22": True}, ("c", "a"): {"22": True},
            ("b", "c"): {"22": True}, ("c", "b"): {"22": True},
            ("a", "b"): {"22": False}, ("b", "a"): {"22": False},
        }
        ports = [22]
        proxies = find_proxyjump_candidates(matrix, "a", "b", ports)
        self.assertGreater(len(proxies), 0)
        # proxies[0] = (via_list, label), via_list may contain multiple hops
        self.assertIn("c", proxies[0][0])

    def test_port_switch_recommendation(self):
        from _reachability import find_port_switch_recommendation
        matrix = {("a", "b"): {"22": False, "80": True, "443": False}}
        ports, msg = find_port_switch_recommendation(matrix, "a", "b", [22, 80, 443])
        self.assertIn(80, ports)
        self.assertIn("ssh -p 80", msg)


class TestFabricEngine(unittest.TestCase):
    """Fabric 引擎冒烟测试"""

    def setUp(self):
        self.fabric_path = os.path.expanduser("~/.tunnel-mesh/fabric.json")
        os.makedirs(os.path.dirname(self.fabric_path), exist_ok=True)

    def tearDown(self):
        if os.path.exists(self.fabric_path):
            os.remove(self.fabric_path)

    def test_load_empty_fabric(self):
        """空 fabric.json → _load_fabric() 返回默认结构"""
        if os.path.exists(self.fabric_path):
            os.remove(self.fabric_path)
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
        from tunnel_mesh import _load_fabric
        fabric = _load_fabric()
        self.assertIn("fabrics", fabric)
        self.assertEqual(len(fabric["fabrics"]), 0)

    def test_load_valid_fabric(self):
        """有效 fabric.json → 正确解析"""
        data = {
            "fabrics": {
                "fab-0": {
                    "logical_edge": "a→b",
                    "port": 2224,
                    "hops": [{"seq": 0, "from": "a", "to": "b", "type": "forward_tunnel", "port": 2224,
                              "cmd": "ssh -L 0.0.0.0:2224:localhost:22 b"}],
                    "maintainers": [{"node": "a", "role": "runner", "cmd": "ssh -L ..."}],
                }
            }
        }
        with open(self.fabric_path, "w") as f:
            json.dump(data, f)
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
        from tunnel_mesh import _load_fabric
        fabric = _load_fabric()
        self.assertIn("fab-0", fabric["fabrics"])
        self.assertEqual(fabric["fabrics"]["fab-0"]["logical_edge"], "a→b")


class TestCLISmoke(unittest.TestCase):
    """CLI 命令冒烟测试：退出码 = 0"""

    @classmethod
    def setUpClass(cls):
        cls.scripts_dir = os.path.join(os.path.dirname(__file__), "..", "scripts")
        cls.tm_py = os.path.join(cls.scripts_dir, "tunnel_mesh.py")

    def _run(self, *args):
        import subprocess
        env = os.environ.copy()
        env["HOME"] = os.environ.get("HOME", tempfile.gettempdir())
        return subprocess.run(
            [sys.executable, self.tm_py] + list(args),
            capture_output=True, text=True, timeout=10, env=env
        )

    def test_help(self):
        r = self._run("--help")
        self.assertEqual(r.returncode, 0)

    def test_server_list_empty(self):
        r = self._run("server-list")
        self.assertEqual(r.returncode, 0)

    def test_edge_list_empty(self):
        r = self._run("edge-list")
        self.assertEqual(r.returncode, 0)

    def test_viz_empty(self):
        r = self._run("viz")
        self.assertEqual(r.returncode, 0)

    def test_fabric_list_empty(self):
        r = self._run("fabric-list")
        self.assertEqual(r.returncode, 0)

    def test_status_empty(self):
        r = self._run("status")
        self.assertEqual(r.returncode, 0)

    def test_path_usage(self):
        # path 无参数时显示用法（exit code 不为 0 是正确的）
        r = self._run("path")
        self.assertIn("用法", r.stderr)

    def test_identity(self):
        r = self._run("identity")
        self.assertEqual(r.returncode, 0)

    def test_tutorial(self):
        r = self._run("tutorial")
        self.assertEqual(r.returncode, 0)


class TestSystemdGeneration(unittest.TestCase):
    """systemd 服务生成测试"""

    def setUp(self):
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
        from tunnel_mesh import _generate_systemd_service
        self._gen = _generate_systemd_service

    def test_basic_service(self):
        result = self._gen("test-edge", "ssh -L 0.0.0.0:2224:localhost:22 target")
        self.assertIn("Tunnel Mesh: test-edge", result)
        self.assertIn("ExecStart=ssh -L 0.0.0.0:2224:localhost:22 target", result)

    def test_restart_policy(self):
        result = self._gen("any", "echo hi")
        self.assertIn("Restart=always", result)
        self.assertIn("WantedBy=default.target", result)

    def test_special_chars_in_name(self):
        result = self._gen("fab-0/node3", "ssh -R 2225:localhost:22 -p 2224 user@host")
        self.assertIn("fab-0/node3", result)
        self.assertIn("-p 2224", result)


class TestConfigCorruptionRecovery(unittest.TestCase):
    """配置损坏恢复测试"""

    def setUp(self):
        cfg_dir = os.path.expanduser("~/.tunnel-mesh")
        os.makedirs(cfg_dir, exist_ok=True)
        self.config_path = os.path.join(cfg_dir, "config.json")

    def _write_config(self, content):
        with open(self.config_path, "w") as f:
            f.write(content)

    def test_truncated_json(self):
        """截断 JSON -> load() 不崩溃，返回默认值"""
        self._write_config('{"servers": {"a": {"ip": "1.2.3.4"')
        from _json_op import load
        d = load()
        self.assertIn("servers", d)

    def test_empty_file(self):
        """空文件 -> 默认结构"""
        self._write_config("")
        from _json_op import load
        d = load()
        self.assertIn("servers", d)
        self.assertIn("edges", d)

    def test_fabric_corrupt_json(self):
        """损坏 fabric.json -> _load_fabric() 返回默认值不崩溃"""
        fabric_path = os.path.expanduser("~/.tunnel-mesh/fabric.json")
        with open(fabric_path, "w") as f:
            f.write("{broken-fabric")
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
        from tunnel_mesh import _load_fabric
        fabric = _load_fabric()
        self.assertEqual(fabric, {"fabrics": {}})
        os.remove(fabric_path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
