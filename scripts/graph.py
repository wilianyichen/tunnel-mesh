#!/usr/bin/env python3
"""
图算法 - 路径规划 + 拓扑可视化
数据源: ~/.tunnel-mesh/config.json
"""
import heapq
import json
import sys
from pathlib import Path
from typing import Dict, List, Tuple, Optional


class Graph:
    """有向图"""

    def __init__(self):
        self.nodes: Dict[str, Dict] = {}
        self.edges: Dict[str, Dict[str, Dict]] = {}

    def add_node(self, node_id: str, info: Dict = None):
        self.nodes[node_id] = info or {}
        if node_id not in self.edges:
            self.edges[node_id] = {}

    def add_edge(self, from_id: str, to_id: str, weight: float = 1.0,
                 edge_info: Dict = None):
        if from_id not in self.edges:
            self.edges[from_id] = {}
        self.edges[from_id][to_id] = {
            "weight": weight,
            "info": edge_info or {}
        }

    def neighbors(self, node_id: str) -> List[str]:
        return list(self.edges.get(node_id, {}).keys())

    def get_edge_weight(self, from_id: str, to_id: str) -> float:
        return self.edges.get(from_id, {}).get(to_id, {}).get("weight", float("inf"))


def dijkstra(graph: Graph, start: str, end: str) -> Tuple[List[str], float]:
    """Dijkstra 最短路径算法。返回: (路径列表, 总权重)"""
    if start not in graph.nodes or end not in graph.nodes:
        return [], float("inf")

    distances = {node: float("inf") for node in graph.nodes}
    distances[start] = 0
    previous = {node: None for node in graph.nodes}
    pq = [(0, start)]
    visited = set()

    while pq:
        current_dist, current = heapq.heappop(pq)
        if current in visited:
            continue
        visited.add(current)
        if current == end:
            break
        for neighbor in graph.neighbors(current):
            if neighbor in visited:
                continue
            weight = graph.get_edge_weight(current, neighbor)
            new_dist = current_dist + weight
            if new_dist < distances[neighbor]:
                distances[neighbor] = new_dist
                previous[neighbor] = current
                heapq.heappush(pq, (new_dist, neighbor))

    if distances[end] == float("inf"):
        return [], float("inf")

    path = []
    current = end
    while current:
        path.append(current)
        current = previous[current]
    path.reverse()
    return path, distances[end]


def build_graph_from_config(config_path: str = None) -> Graph:
    """从 config.json 构建图"""
    if config_path is None:
        config_path = Path.home() / ".tunnel-mesh" / "config.json"
    else:
        config_path = Path(config_path)

    graph = Graph()
    if not config_path.exists():
        return graph

    with open(config_path) as f:
        config = json.load(f)

    for name, info in config.get("servers", {}).items():
        graph.add_node(name, info)

    for edge in config.get("edges", []):
        # 优先使用显式 weight，否则按 type 计算
        if "weight" in edge:
            weight = edge["weight"]
        else:
            weight = 1.5 if edge.get("type") == "reverse" else 1.0
        graph.add_edge(edge["from"], edge["to"], weight=weight, edge_info=edge)

    return graph


def find_path(from_id: str, to_id: str, config_path: str = None) -> Dict:
    """查找路径"""
    graph = build_graph_from_config(config_path)
    path, total_weight = dijkstra(graph, from_id, to_id)

    if not path:
        return {"success": False, "error": f"无法找到从 {from_id} 到 {to_id} 的路径"}

    return {
        "success": True,
        "path": path,
        "hops": len(path) - 1,
        "weight": total_weight,
        "formatted": " → ".join(path),
    }


def render_ascii(config_path: str = None) -> str:
    """ASCII 拓扑图"""
    graph = build_graph_from_config(config_path)
    lines = []

    if not graph.nodes:
        return "  (空图)"

    lines.append("节点:")
    for name, info in graph.nodes.items():
        ip = info.get("ip", "?")
        port = info.get("port", 22)
        extra = ""
        if info.get("public_ip") and info["public_ip"] != ip:
            extra = f" (公网:{info['public_ip']})"
        lines.append(f"  {name}  {ip}:{port}{extra}")

    if not graph.edges or all(not v for v in graph.edges.values()):
        lines.append("\n  (无边)")
        return "\n".join(lines)

    lines.append("\n边:")
    seen = set()
    for src, targets in graph.edges.items():
        for dst, data in targets.items():
            edge = data["info"]
            typ = edge.get("type", "?")
            label = typ
            if edge.get("tunnel_port"):
                label += f":{edge['tunnel_port']}"
            arrow = "─隧道→" if typ == "reverse" else "──→"
            lines.append(f"  {src} {arrow} {dst}  ({label})")
    return "\n".join(lines)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Tunnel Mesh 图引擎")
    parser.add_argument("--from", dest="from_id", help="起点")
    parser.add_argument("--to", dest="to_id", help="终点")
    parser.add_argument("--config", default=None, help="config.json 路径")
    parser.add_argument("--viz", action="store_true", help="拓扑可视化")
    parser.add_argument("--json", action="store_true", help="JSON 输出")

    args = parser.parse_args()

    if args.viz:
        print(render_ascii(args.config))
    elif args.from_id and args.to_id:
        result = find_path(args.from_id, args.to_id, args.config)
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        elif result["success"]:
            print(f"路径: {result['formatted']}")
            print(f"跳数: {result['hops']}")
        else:
            print(result["error"])
    else:
        parser.print_help()
