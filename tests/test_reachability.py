#!/usr/bin/env python3
"""可达矩阵合并 + 边推荐逻辑单元测试 — 纯内存数据，零 IO 依赖"""
import sys
import os
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts", "lib"))
from _reachability import (
    merge_reports, is_pair_reachable, find_port_switch_recommendation,
    _build_reachability_graph, find_proxyjump_candidates, find_bridge_v2,
    recommend_edges_v2, format_matrix_v2,
)


class TestMergeReports(unittest.TestCase):

    def test_merge_v1_format(self):
        """两个 v1 报告 -> 正确合并为矩阵"""
        reports = [
            {"from": "a", "from_ip": "10.0.0.1",
             "results": [{"target": "b", "ip": "10.0.0.2", "port": 22, "reachable": True}]},
            {"from": "b", "from_ip": "10.0.0.2",
             "results": [{"target": "a", "ip": "10.0.0.1", "port": 22, "reachable": False}]},
        ]
        matrix, nodes, ips, ports, probed, ssh = merge_reports(reports)
        self.assertIn(("a", "b"), matrix)
        self.assertTrue(matrix[("a", "b")].get("22"))
        self.assertFalse(matrix[("b", "a")].get("22"))
        self.assertIn("a", nodes)
        self.assertIn("b", nodes)
        self.assertIn("a", ips)
        self.assertIn("b", ips)

    def test_merge_v2_format(self):
        """两个 v2 报告 -> 正确合并多端口数据"""
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
        matrix, nodes, ips, ports, probed, ssh = merge_reports(reports)
        self.assertIn(80, probed)
        self.assertIn("80", matrix[("a", "b")])
        self.assertTrue(matrix[("a", "b")]["80"])
        self.assertFalse(matrix[("a", "b")]["22"])

    def test_merge_empty(self):
        """空报告列表 -> 返回空结构不崩溃"""
        matrix, nodes, ips, ports, probed, ssh = merge_reports([])
        self.assertEqual(len(nodes), 0)
        self.assertEqual(len(probed), 0)

    def test_merge_single_report(self):
        """单报告 -> 矩阵只含从该节点出发的边"""
        reports = [
            {"from": "a", "from_ip": "10.0.0.1", "probed_ports": [22],
             "results": [{"target": "b", "ip": "10.0.0.2", "default_port": 22,
                          "ports": {"22": {"reachable": True, "latency_ms": 1}}}]},
        ]
        matrix, nodes, ips, ports, probed, ssh = merge_reports(reports)
        self.assertIn(("a", "b"), matrix)
        self.assertNotIn(("b", "a"), matrix)  # b 没有报告，所以反向不存在
        self.assertIn("a", nodes)
        self.assertIn("b", nodes)


class TestIsPairReachable(unittest.TestCase):

    def test_bidirectional(self):
        matrix = {("a", "b"): {"22": True}, ("b", "a"): {"22": True}}
        r, open_ports, blocked = is_pair_reachable(matrix, "a", "b", [22])
        self.assertTrue(r)
        self.assertIn(22, open_ports)
        r2, _, _ = is_pair_reachable(matrix, "b", "a", [22])
        self.assertTrue(r2)

    def test_one_way(self):
        matrix = {("a", "b"): {"22": True}, ("b", "a"): {"22": False}}
        r, _, _ = is_pair_reachable(matrix, "a", "b", [22])
        self.assertTrue(r)
        r2, _, _ = is_pair_reachable(matrix, "b", "a", [22])
        self.assertFalse(r2)

    def test_unreachable_pair(self):
        matrix = {("a", "b"): {"22": False}}
        r, _, _ = is_pair_reachable(matrix, "a", "b", [22])
        self.assertFalse(r)

    def test_different_port(self):
        """默认端口不通但 80 通"""
        matrix = {("a", "b"): {"22": False, "80": True}}
        r, open_ports, _ = is_pair_reachable(matrix, "a", "b", [22, 80])
        self.assertTrue(r)
        self.assertIn(80, open_ports)


class TestPortSwitchRecommendation(unittest.TestCase):

    def test_22_blocked_80_open(self):
        matrix = {("a", "b"): {"22": False, "80": True, "443": False}}
        ports, msg = find_port_switch_recommendation(matrix, "a", "b", [22, 80, 443])
        self.assertIn(80, ports)
        self.assertIn("ssh -p 80", msg)

    def test_all_ports_open(self):
        """默认 22 端口通 -> 无需端口切换，返回空"""
        matrix = {("a", "b"): {"22": True, "80": True}}
        ports, msg = find_port_switch_recommendation(matrix, "a", "b", [22, 80])
        self.assertEqual(len(ports), 0)  # 默认端口已通，不推荐切换

    def test_all_ports_blocked(self):
        """全端口不通 -> 无可推荐端口"""
        matrix = {("a", "b"): {"22": False, "80": False}}
        ports, msg = find_port_switch_recommendation(matrix, "a", "b", [22, 80])
        self.assertEqual(len(ports), 0)


class TestBuildReachabilityGraph(unittest.TestCase):

    def test_full_mesh(self):
        matrix = {("a", "b"): {"22": True}, ("b", "a"): {"22": True},
                  ("a", "c"): {"22": True}, ("c", "a"): {"22": True},
                  ("b", "c"): {"22": True}, ("c", "b"): {"22": True}}
        graph = _build_reachability_graph(matrix, [22], ["a", "b", "c"])
        self.assertEqual(len(graph["a"]), 2)  # a 可达 b, c

    def test_star_graph(self):
        """c 是中心节点，a 和 b 只能通过 c 互达"""
        matrix = {("a", "c"): {"22": True}, ("c", "a"): {"22": True},
                  ("b", "c"): {"22": True}, ("c", "b"): {"22": True},
                  ("a", "b"): {"22": False}, ("b", "a"): {"22": False}}
        graph = _build_reachability_graph(matrix, [22], ["a", "b", "c"])
        self.assertIn("c", graph["a"])
        self.assertNotIn("b", graph["a"])


class TestFindProxyjumpCandidates(unittest.TestCase):

    def test_single_proxy(self):
        """a→c 通，c→b 通，a 和 b 不互通"""
        matrix = {("a", "c"): {"22": True}, ("c", "a"): {"22": True},
                  ("b", "c"): {"22": True}, ("c", "b"): {"22": True},
                  ("a", "b"): {"22": False}, ("b", "a"): {"22": False}}
        proxies = find_proxyjump_candidates(matrix, "a", "b", [22],
                                            nodes=["a", "b", "c"])
        self.assertGreater(len(proxies), 0)
        self.assertIn("c", proxies[0][0])

    def test_no_proxy(self):
        """无公共中转节点"""
        matrix = {("a", "b"): {"22": False}, ("b", "a"): {"22": False},
                  ("a", "c"): {"22": True}, ("c", "a"): {"22": True},
                  ("b", "c"): {"22": False}}  # c 只连着 a，够不着 b
        proxies = find_proxyjump_candidates(matrix, "a", "b", [22],
                                            nodes=["a", "b", "c"])
        # c 能到 a 但 c 不能到 b，所以 c 不算有效中转
        self.assertEqual(len(proxies), 0)

    def test_direct_but_proxies_still_listed(self):
        """a→b 直达，但 BFS 仍列出经由 c 的中转路径（由调用方 recommend_edges_v2 过滤直达）"""
        matrix = {("a", "b"): {"22": True}, ("b", "a"): {"22": True},
                  ("a", "c"): {"22": True}, ("c", "a"): {"22": True},
                  ("b", "c"): {"22": True}, ("c", "b"): {"22": True}}
        proxies = find_proxyjump_candidates(matrix, "a", "b", [22],
                                            nodes=["a", "b", "c"])
        self.assertGreater(len(proxies), 0)  # BFS 仍发现经 c 的中转路径

    def test_label_includes_hop_count(self):
        matrix = {("a", "c"): {"22": True}, ("c", "a"): {"22": True},
                  ("b", "c"): {"22": True}, ("c", "b"): {"22": True},
                  ("a", "b"): {"22": False}, ("b", "a"): {"22": False}}
        proxies = find_proxyjump_candidates(matrix, "a", "b", [22],
                                            nodes=["a", "b", "c"])
        via_list, label = proxies[0]
        self.assertIn("ProxyJump", label)


class TestFindBridge(unittest.TestCase):

    def test_bridge_found(self):
        """c 能同时连到 a 和 b"""
        matrix = {("a", "c"): {"22": True}, ("a", "b"): {"22": False},
                  ("b", "c"): {"22": True}}
        bridge = find_bridge_v2(matrix, "a", "b", [22], ["a", "b", "c"])
        self.assertEqual(bridge, "c")

    def test_no_bridge(self):
        matrix = {("a", "b"): {"22": False}, ("a", "c"): {"22": False}}
        bridge = find_bridge_v2(matrix, "a", "b", [22], ["a", "b", "c"])
        self.assertIsNone(bridge)


class TestRecommendEdges(unittest.TestCase):

    def test_full_bidirectional(self):
        """a 和 b 双向直连 -> forward edge"""
        matrix = {("a", "b"): {"22": True}, ("b", "a"): {"22": True}}
        ips = {"a": "10.0.0.1", "b": "10.0.0.2"}
        recs = recommend_edges_v2(matrix, ["a", "b"], [22], ips)
        edge_types = [e["type"] for e in recs]
        self.assertIn("forward", edge_types)

    def test_needs_reverse(self):
        """a→b 通，b→a 不通 -> reverse edge"""
        matrix = {("a", "b"): {"22": True}, ("b", "a"): {"22": False}}
        ips = {"a": "10.0.0.1", "b": "10.0.0.2"}
        recs = recommend_edges_v2(matrix, ["a", "b"], [22], ips)
        edge_types = [e["type"] for e in recs]
        self.assertIn("reverse", edge_types)

    def test_needs_proxyjump(self):
        """a 和 b 互不通但都通 c -> proxyjump"""
        matrix = {("a", "c"): {"22": True}, ("c", "a"): {"22": True},
                  ("b", "c"): {"22": True}, ("c", "b"): {"22": True},
                  ("a", "b"): {"22": False}, ("b", "a"): {"22": False}}
        ips = {"a": "10.0.0.1", "b": "10.0.0.2", "c": "10.0.0.3"}
        recs = recommend_edges_v2(matrix, ["a", "b", "c"], [22], ips)
        edge_types = [e["type"] for e in recs]
        self.assertIn("proxyjump", edge_types)


class TestFormatMatrix(unittest.TestCase):

    def test_2x2_matrix(self):
        matrix = {("a", "b"): {"22": True}, ("b", "a"): {"22": False}}
        nodes = ["a", "b"]
        ports = [22]
        ips = {"a": "10.0.0.1", "b": "10.0.0.2"}
        result = format_matrix_v2(matrix, nodes, ports, ips)
        self.assertIn("a", result)
        self.assertIn("b", result)
        self.assertIn("✓", result)  # a→b 端口通
        self.assertIn("✗", result)  # b→a 端口不通

    def test_single_node_matrix(self):
        """单节点矩阵：不崩溃"""
        nodes = ["a"]
        result = format_matrix_v2({}, nodes, [], {"a": "10.0.0.1"})
        self.assertIn("a", result)


if __name__ == "__main__":
    unittest.main(verbosity=2)
