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
        matrix, nodes, ips, ports, probed = merge_reports(reports)
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
        matrix, nodes, ips, ports, probed = merge_reports(reports)
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
        self.assertEqual(proxies[0][0], "c")

    def test_port_switch_recommendation(self):
        from _reachability import find_port_switch_recommendation
        matrix = {("a", "b"): {"22": False, "80": True, "443": False}}
        ports, msg = find_port_switch_recommendation(matrix, "a", "b", [22, 80, 443])
        self.assertIn(80, ports)
        self.assertIn("ssh -p 80", msg)


if __name__ == "__main__":
    unittest.main(verbosity=2)
