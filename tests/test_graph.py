#!/usr/bin/env python3
"""Dijkstra + Graph 单元测试 — 纯内存数据结构，零 IO 依赖"""
import sys
import os
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
from graph import Graph, dijkstra


class TestGraphMethods(unittest.TestCase):

    def setUp(self):
        self.g = Graph()

    def test_add_node(self):
        self.g.add_node("a", {"ip": "1.2.3.4"})
        self.assertIn("a", self.g.nodes)
        self.assertEqual(self.g.nodes["a"]["ip"], "1.2.3.4")

    def test_add_edge(self):
        self.g.add_node("a")
        self.g.add_node("b")
        self.g.add_edge("a", "b", weight=1.5, edge_info={"type": "forward"})
        self.assertIn("b", self.g.edges["a"])
        self.assertEqual(self.g.edges["a"]["b"]["weight"], 1.5)
        self.assertEqual(self.g.edges["a"]["b"]["info"]["type"], "forward")

    def test_neighbors(self):
        self.g.add_node("a")
        self.g.add_node("b")
        self.g.add_node("c")
        self.g.add_edge("a", "b")
        self.g.add_edge("a", "c")
        neighbors = self.g.neighbors("a")
        self.assertCountEqual(neighbors, ["b", "c"])

    def test_no_neighbors(self):
        self.g.add_node("a")
        self.assertEqual(self.g.neighbors("a"), [])

    def test_get_edge_weight(self):
        self.g.add_node("a")
        self.g.add_node("b")
        self.g.add_edge("a", "b", weight=2.0)
        self.assertEqual(self.g.get_edge_weight("a", "b"), 2.0)

    def test_get_edge_weight_nonexistent(self):
        self.g.add_node("a")
        self.g.add_node("b")
        self.assertEqual(self.g.get_edge_weight("a", "b"), float("inf"))


class TestDijkstra(unittest.TestCase):

    def setUp(self):
        self.g = Graph()

    def _add_bidirectional(self, a, b, weight=1.0):
        self.g.add_edge(a, b, weight)
        self.g.add_edge(b, a, weight)

    def test_single_hop(self):
        self.g.add_node("a")
        self.g.add_node("b")
        self._add_bidirectional("a", "b")
        path, total = dijkstra(self.g, "a", "b")
        self.assertEqual(path, ["a", "b"])
        self.assertEqual(total, 1.0)

    def test_two_hop_shortest(self):
        """A→C→B (2.0) vs A→D→E→B (3.0) — Dijkstra 选短的"""
        for n in ["a", "b", "c", "d", "e"]:
            self.g.add_node(n)
        self._add_bidirectional("a", "c", 1.0)
        self._add_bidirectional("c", "b", 1.0)
        self._add_bidirectional("a", "d", 1.0)
        self._add_bidirectional("d", "e", 1.0)
        self._add_bidirectional("e", "b", 1.0)
        path, total = dijkstra(self.g, "a", "b")
        self.assertEqual(total, 2.0)
        self.assertEqual(path, ["a", "c", "b"])

    def test_unreachable(self):
        self.g.add_node("a")
        self.g.add_node("b")
        path, total = dijkstra(self.g, "a", "b")
        self.assertEqual(path, [])
        self.assertEqual(total, float("inf"))

    def test_nonexistent_node(self):
        self.g.add_node("a")
        path, total = dijkstra(self.g, "a", "x")
        self.assertEqual(path, [])

    def test_directed_edge(self):
        """A→B 有边，B→A 无边"""
        self.g.add_node("a")
        self.g.add_node("b")
        self.g.add_edge("a", "b", 1.0)
        path, total = dijkstra(self.g, "a", "b")
        self.assertEqual(path, ["a", "b"])
        path2, total2 = dijkstra(self.g, "b", "a")
        self.assertEqual(path2, [])
        self.assertEqual(total2, float("inf"))

    def test_weight_preference(self):
        """选三跳低权重 (3×0.3=0.9) 而非两跳高权重 (2×0.8=1.6)"""
        for n in ["a", "b", "c", "d", "e"]:
            self.g.add_node(n)
        # 两跳高权重路径: a→d→b = 1.6
        self._add_bidirectional("a", "d", 0.8)
        self._add_bidirectional("d", "b", 0.8)
        # 三跳低权重路径: a→c→e→b = 0.9
        self._add_bidirectional("a", "c", 0.3)
        self._add_bidirectional("c", "e", 0.3)
        self._add_bidirectional("e", "b", 0.3)
        path, total = dijkstra(self.g, "a", "b")
        self.assertAlmostEqual(total, 0.9)
        self.assertEqual(path, ["a", "c", "e", "b"])
    def test_start_equals_end(self):
        self.g.add_node("a")
        path, total = dijkstra(self.g, "a", "a")
        self.assertEqual(path, ["a"])
        self.assertEqual(total, 0)

    def test_cycle_no_infinite_loop(self):
        """循环图不导致死循环"""
        for n in ["a", "b", "c"]:
            self.g.add_node(n)
        self._add_bidirectional("a", "b")
        self._add_bidirectional("b", "c")
        self._add_bidirectional("c", "a")
        path, total = dijkstra(self.g, "a", "c")
        self.assertEqual(path, ["a", "c"])  # 直达边
        self.assertEqual(total, 1.0)

    def test_large_graph(self):
        """稍大图，验证算法效率"""
        nodes = [chr(ord("a") + i) for i in range(26)]  # a-z
        for n in nodes:
            self.g.add_node(n)
        for i in range(25):
            self._add_bidirectional(nodes[i], nodes[i + 1])
        path, total = dijkstra(self.g, "a", "z")
        self.assertEqual(len(path), 26)
        self.assertEqual(total, 25.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
