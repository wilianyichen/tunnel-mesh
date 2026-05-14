#!/usr/bin/env python3
"""
图算法 - 路径规划
"""

import heapq
from typing import Dict, List, Tuple, Optional
from pathlib import Path
import yaml


class Graph:
    """有向图"""
    
    def __init__(self):
        self.nodes: Dict[str, Dict] = {}  # 节点信息
        self.edges: Dict[str, Dict[str, Dict]] = {}  # 邻接表
    
    def add_node(self, node_id: str, info: Dict = None):
        """添加节点"""
        self.nodes[node_id] = info or {}
        if node_id not in self.edges:
            self.edges[node_id] = {}
    
    def add_edge(self, from_id: str, to_id: str, weight: float = 1.0, 
                 edge_info: Dict = None):
        """添加边"""
        if from_id not in self.edges:
            self.edges[from_id] = {}
        
        self.edges[from_id][to_id] = {
            "weight": weight,
            "info": edge_info or {}
        }
    
    def neighbors(self, node_id: str) -> List[str]:
        """获取邻居节点"""
        return list(self.edges.get(node_id, {}).keys())
    
    def get_edge_weight(self, from_id: str, to_id: str) -> float:
        """获取边权重"""
        return self.edges.get(from_id, {}).get(to_id, {}).get("weight", float("inf"))


def dijkstra(graph: Graph, start: str, end: str) -> Tuple[List[str], float]:
    """
    Dijkstra 最短路径算法
    
    返回: (路径列表, 总权重)
    """
    if start not in graph.nodes or end not in graph.nodes:
        return [], float("inf")
    
    # 初始化
    distances = {node: float("inf") for node in graph.nodes}
    distances[start] = 0
    previous = {node: None for node in graph.nodes}
    pq = [(0, start)]  # (距离, 节点)
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
    
    # 重建路径
    if distances[end] == float("inf"):
        return [], float("inf")
    
    path = []
    current = end
    while current:
        path.append(current)
        current = previous[current]
    path.reverse()
    
    return path, distances[end]


def build_graph_from_topology(topology_dir: str = "~/.hermes/topology") -> Graph:
    """从拓扑配置构建图"""
    topology_dir = Path(topology_dir).expanduser()
    
    graph = Graph()
    
    # 加载服务器
    servers_dir = topology_dir / "servers"
    if servers_dir.exists():
        for server_file in servers_dir.glob("*.yaml"):
            with open(server_file) as f:
                server = yaml.safe_load(f)
            graph.add_node(server["id"], server)
    
    # 加载连接
    connections_dir = topology_dir / "connections"
    if connections_dir.exists():
        for conn_file in connections_dir.glob("*.yaml"):
            with open(conn_file) as f:
                conn = yaml.safe_load(f)
            
            # 权重：延迟或默认值
            weight = conn.get("latency_ms", 50) / 100.0  # 归一化
            if conn.get("type") == "tunnel":
                weight += 0.5  # 隧道增加权重
            
            graph.add_edge(
                conn["from"], 
                conn["to"], 
                weight=weight,
                edge_info=conn
            )
    
    return graph


def find_path(from_id: str, to_id: str) -> Dict:
    """查找路径"""
    graph = build_graph_from_topology()
    path, total_weight = dijkstra(graph, from_id, to_id)
    
    if not path:
        return {
            "success": False,
            "error": f"无法找到从 {from_id} 到 {to_id} 的路径"
        }
    
    return {
        "success": True,
        "path": path,
        "hops": len(path) - 1,
        "weight": total_weight,
        "formatted": " → ".join(path)
    }


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="路径规划")
    parser.add_argument("--from", dest="from_id", required=True, help="起点")
    parser.add_argument("--to", dest="to_id", required=True, help="终点")
    
    args = parser.parse_args()
    
    result = find_path(args.from_id, args.to_id)
    
    if result["success"]:
        print(f"路径: {result['formatted']}")
        print(f"跳数: {result['hops']}")
    else:
        print(result["error"])
