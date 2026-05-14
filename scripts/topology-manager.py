#!/usr/bin/env python3
"""
拓扑管理器 - 核心管理脚本
"""

import argparse
import json
import yaml
from pathlib import Path
from typing import Dict, List, Optional


class TopologyManager:
    """拓扑管理器"""
    
    def __init__(self, config_dir: str = "~/.hermes/topology"):
        self.config_dir = Path(config_dir).expanduser()
        self.config_dir.mkdir(parents=True, exist_ok=True)
        
        # 子目录
        self.servers_dir = self.config_dir / "servers"
        self.connections_dir = self.config_dir / "connections"
        self.cache_dir = self.config_dir / "cache"
        
        for d in [self.servers_dir, self.connections_dir, self.cache_dir]:
            d.mkdir(exist_ok=True)
        
        # 主拓扑文件
        self.topology_file = self.config_dir / "topology.yaml"
    
    def init(self):
        """初始化拓扑配置"""
        if self.topology_file.exists():
            print("拓扑配置已存在")
            return
        
        topology = {
            "name": "my-servers",
            "version": "1.0",
            "servers": [],
            "connections": [],
            "routing": {
                "default_via": None,
                "fallback_enabled": True,
                "auto_optimize": True
            }
        }
        
        with open(self.topology_file, "w") as f:
            yaml.dump(topology, f)
        
        print(f"✓ 已创建拓扑配置: {self.topology_file}")
    
    def add_server(self, alias: str, ip: str, port: int, user: str, trust: str = "user"):
        """添加服务器"""
        server_id = alias.lower().replace("-", "_")
        
        server = {
            "id": server_id,
            "alias": alias,
            "ip_private": ip,
            "port": port,
            "user_default": user,
            "trust_level": trust
        }
        
        server_file = self.servers_dir / f"{server_id}.yaml"
        with open(server_file, "w") as f:
            yaml.dump(server, f)
        
        # 更新主拓扑
        self._update_topology_servers()
        
        print(f"✓ 已添加服务器: {alias}")
        print(f"  配置文件: {server_file}")
    
    def list_servers(self):
        """列出所有服务器"""
        servers = self._load_servers()
        
        if not servers:
            print("暂无服务器")
            return
        
        print("服务器列表:")
        print("-" * 50)
        for s in servers:
            status = "🟢" if self._test_server(s["id"]) else "🔴"
            print(f"{status} {s['alias']} ({s['id']})")
            print(f"   IP: {s.get('ip_private', s.get('ip_public', 'N/A'))}")
            print(f"   端口: {s['port']}")
            print(f"   信任等级: {s['trust_level']}")
    
    def _load_servers(self) -> List[Dict]:
        """加载所有服务器配置"""
        servers = []
        for f in self.servers_dir.glob("*.yaml"):
            with open(f) as fp:
                servers.append(yaml.safe_load(fp))
        return servers
    
    def _load_topology(self) -> Dict:
        """加载主拓扑文件"""
        if not self.topology_file.exists():
            return {}
        with open(self.topology_file) as f:
            return yaml.safe_load(f)
    
    def _update_topology_servers(self):
        """更新主拓扑的服务器列表"""
        topology = self._load_topology()
        servers = self._load_servers()
        topology["servers"] = [{"id": s["id"], "alias": s["alias"]} for s in servers]
        
        with open(self.topology_file, "w") as f:
            yaml.dump(topology, f)
    
    def _test_server(self, server_id: str) -> bool:
        """测试服务器连接（简化版）"""
        # TODO: 实现实际连接测试
        return True
    
    def matrix(self):
        """显示连接矩阵"""
        servers = self._load_servers()
        topology = self._load_topology()
        connections = topology.get("connections", [])
        
        # 构建矩阵
        server_ids = [s["id"] for s in servers]
        
        print("\n连接矩阵:")
        print("-" * 60)
        
        # 表头
        header = "        " + "  ".join(f"{sid[:8]}" for sid in server_ids)
        print(header)
        
        # 矩阵内容
        for from_id in server_ids:
            row = f"{from_id[:8]}  "
            for to_id in server_ids:
                if from_id == to_id:
                    cell = "  -  "
                else:
                    # 查找连接
                    conn = self._find_connection(connections, from_id, to_id)
                    if conn:
                        cell = "  ✓→ "
                    else:
                        cell = "  ?  "
                row += cell
            print(row)
        
        print("-" * 60)
        print("✓→ = 可连接  ? = 未配置  - = 自己")
    
    def path(self, from_id: str, to_id: str):
        """计算路径"""
        from pathlib import Path
        import sys
        
        # 动态导入 graph 模块
        scripts_dir = Path(__file__).parent
        sys.path.insert(0, str(scripts_dir))
        
        from graph import find_path
        
        result = find_path(from_id, to_id)
        
        if result["success"]:
            print(f"路径: {result['formatted']}")
            print(f"跳数: {result['hops']}")
            print(f"权重: {result['weight']:.2f}")
        else:
            print(result["error"])
    
    def _find_connection(self, connections: List[Dict], from_id: str, to_id: str) -> Optional[Dict]:
        """查找连接"""
        for c in connections:
            if c["from"] == from_id and c["to"] == to_id:
                return c
        return None


def main():
    parser = argparse.ArgumentParser(description="服务器网络拓扑管理")
    subparsers = parser.add_subparsers(dest="command")
    
    # init
    subparsers.add_parser("init", help="初始化拓扑配置")
    
    # add
    add_parser = subparsers.add_parser("add", help="添加服务器")
    add_parser.add_argument("--alias", required=True, help="服务器别名")
    add_parser.add_argument("--ip", required=True, help="IP 地址")
    add_parser.add_argument("--port", type=int, default=22, help="SSH 端口")
    add_parser.add_argument("--user", default="root", help="登录用户")
    add_parser.add_argument("--trust", default="user", help="信任等级")
    
    # list
    subparsers.add_parser("list", help="列出服务器")
    
    # matrix
    subparsers.add_parser("matrix", help="显示连接矩阵")
    
    # path
    path_parser = subparsers.add_parser("path", help="计算路径")
    path_parser.add_argument("--from", dest="from_id", required=True, help="起点")
    path_parser.add_argument("--to", dest="to_id", required=True, help="终点")
    
    args = parser.parse_args()
    
    manager = TopologyManager()
    
    if args.command == "init":
        manager.init()
    elif args.command == "add":
        manager.add_server(args.alias, args.ip, args.port, args.user, args.trust)
    elif args.command == "list":
        manager.list_servers()
    elif args.command == "matrix":
        manager.matrix()
    elif args.command == "path":
        manager.path(args.from_id, args.to_id)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()