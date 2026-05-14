#!/usr/bin/env python3
"""
主控 API 服务 - 全自动模式核心
"""

import argparse
import json
import yaml
import secrets
import time
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Dict, List, Optional
from urllib.parse import urlparse, parse_qs


class TopologyAPIHandler(BaseHTTPRequestHandler):
    """API 请求处理器"""
    
    topology_dir = Path("~/.hermes/topology").expanduser()
    tokens_file = topology_dir / "tokens.json"
    
    def log_message(self, format, *args):
        """自定义日志格式"""
        print(f"[API] {args[0]}")
    
    def send_json(self, data: Dict, status: int = 200):
        """发送 JSON 响应"""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode())
    
    def read_body(self) -> Dict:
        """读取请求体"""
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            return {}
        body = self.rfile.read(content_length)
        try:
            return json.loads(body)
        except json.JSONDecodeError:
            return {}
    
    def do_GET(self):
        """处理 GET 请求"""
        path = urlparse(self.path).path
        
        if path == "/api/servers":
            self.handle_list_servers()
        elif path.startswith("/api/servers/"):
            server_id = path.split("/")[-1]
            self.handle_get_server(server_id)
        elif path == "/api/topology":
            self.handle_get_topology()
        elif path == "/api/status":
            self.handle_get_status()
        elif path == "/api/tokens":
            self.handle_list_tokens()
        else:
            self.send_json({"error": "Not found"}, 404)
    
    def do_POST(self):
        """处理 POST 请求"""
        path = urlparse(self.path).path
        
        if path == "/api/servers/register":
            self.handle_register_server()
        elif path == "/api/tokens/generate":
            self.handle_generate_token()
        elif path.startswith("/api/join/"):
            token = path.split("/")[-1]
            self.handle_join(token)
        elif path == "/api/connections":
            self.handle_add_connection()
        elif path.startswith("/api/connections/test/"):
            parts = path.split("/")
            if len(parts) >= 5:
                from_id, to_id = parts[-2], parts[-1]
                self.handle_test_connection(from_id, to_id)
            else:
                self.send_json({"error": "Invalid path"}, 400)
        else:
            self.send_json({"error": "Not found"}, 404)
    
    def do_DELETE(self):
        """处理 DELETE 请求"""
        path = urlparse(self.path).path
        
        if path.startswith("/api/servers/"):
            server_id = path.split("/")[-1]
            self.handle_delete_server(server_id)
        elif path.startswith("/api/tokens/"):
            token_id = path.split("/")[-1]
            self.handle_delete_token(token_id)
        else:
            self.send_json({"error": "Not found"}, 404)
    
    # === 服务器管理 ===
    
    def handle_list_servers(self):
        """列出所有服务器"""
        servers = self._load_servers()
        self.send_json({"servers": servers})
    
    def handle_get_server(self, server_id: str):
        """获取服务器详情"""
        server_file = self.topology_dir / "servers" / f"{server_id}.yaml"
        if not server_file.exists():
            self.send_json({"error": "Server not found"}, 404)
            return
        
        with open(server_file) as f:
            server = yaml.safe_load(f)
        self.send_json(server)
    
    def handle_register_server(self):
        """注册新服务器"""
        data = self.read_body()
        
        alias = data.get("alias")
        if not alias:
            self.send_json({"error": "alias is required"}, 400)
            return
        
        server_id = alias.lower().replace("-", "_")
        
        server = {
            "id": server_id,
            "alias": alias,
            "ip_private": data.get("ip"),
            "port": data.get("port", 22),
            "user_default": data.get("user", "root"),
            "trust_level": data.get("trust_level", "user"),
            "public_key": data.get("public_key"),
            "registered_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        
        # 保存服务器配置
        server_file = self.topology_dir / "servers" / f"{server_id}.yaml"
        with open(server_file, "w") as f:
            yaml.dump(server, f)
        
        # 更新主拓扑
        self._update_topology()
        
        # 自动写入公钥到 authorized_keys
        key_added = False
        if data.get("public_key"):
            key_added = self._add_authorized_key(server_id, data["public_key"])
        
        # 生成 SSH config
        ssh_config = self._generate_ssh_config(server)
        
        self.send_json({
            "success": True,
            "server_id": server_id,
            "message": "服务器已注册",
            "key_added": key_added,
            "config": {
                "ssh_config": ssh_config,
                "test_command": f"ssh {server_id} 'hostname'"
            }
        })
    
    def _add_authorized_key(self, server_id: str, public_key: str) -> bool:
        """添加公钥到 authorized_keys"""
        try:
            ssh_dir = Path.home() / ".ssh"
            ssh_dir.mkdir(mode=0o700, exist_ok=True)
            
            authorized_keys = ssh_dir / "authorized_keys"
            
            # 检查是否已存在
            if authorized_keys.exists():
                content = authorized_keys.read_text()
                if public_key in content:
                    print(f"[API] 公钥已存在: {server_id}")
                    return True
            
            # 添加公钥
            with open(authorized_keys, "a") as f:
                f.write(f"\n# topology-manager: {server_id}\n")
                f.write(f"{public_key}\n")
            
            # 设置权限
            authorized_keys.chmod(0o600)
            print(f"[API] 已添加公钥: {server_id}")
            return True
            
        except Exception as e:
            print(f"[API] 添加公钥失败: {e}")
            return False
    
    def handle_delete_server(self, server_id: str):
        """删除服务器"""
        server_file = self.topology_dir / "servers" / f"{server_id}.yaml"
        if not server_file.exists():
            self.send_json({"error": "Server not found"}, 404)
            return
        
        server_file.unlink()
        self._update_topology()
        self.send_json({"success": True, "message": "服务器已删除"})
    
    # === 令牌管理 ===
    
    def handle_generate_token(self):
        """生成注册令牌"""
        data = self.read_body()
        
        token = secrets.token_hex(16)
        expires_hours = data.get("duration_hours", 24)
        
        token_info = {
            "token": token,
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "expires_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", 
                                         time.localtime(time.time() + expires_hours * 3600)),
            "max_uses": data.get("max_uses", 1),
            "uses_remaining": data.get("max_uses", 1),
            "trust_level": data.get("trust_level", "user")
        }
        
        # 保存令牌
        tokens = self._load_tokens()
        tokens.append(token_info)
        self._save_tokens(tokens)
        
        self.send_json({
            "success": True,
            "token": token,
            "expires_at": token_info["expires_at"],
            "join_url": f"http://localhost:8888/api/join/{token}"
        })
    
    def handle_list_tokens(self):
        """列出所有令牌"""
        tokens = self._load_tokens()
        self.send_json({"tokens": tokens})
    
    def handle_delete_token(self, token_id: str):
        """删除令牌"""
        tokens = self._load_tokens()
        tokens = [t for t in tokens if t["token"] != token_id]
        self._save_tokens(tokens)
        self.send_json({"success": True, "message": "令牌已删除"})
    
    # === 加入网络 ===
    
    def handle_join(self, token: str):
        """使用令牌加入网络"""
        tokens = self._load_tokens()
        
        # 查找令牌
        token_info = None
        for t in tokens:
            if t["token"] == token:
                token_info = t
                break
        
        if not token_info:
            self.send_json({"error": "Invalid token"}, 400)
            return
        
        # 检查过期
        expires_at = time.strptime(token_info["expires_at"], "%Y-%m-%dT%H:%M:%SZ")
        if time.mktime(expires_at) < time.time():
            self.send_json({"error": "Token expired"}, 400)
            return
        
        # 检查使用次数
        if token_info["uses_remaining"] <= 0:
            self.send_json({"error": "Token exhausted"}, 400)
            return
        
        # 注册服务器
        data = self.read_body()
        data["trust_level"] = token_info["trust_level"]
        
        # 更新令牌使用次数
        for t in tokens:
            if t["token"] == token:
                t["uses_remaining"] -= 1
        self._save_tokens(tokens)
        
        # 调用注册逻辑
        self.handle_register_server()
    
    # === 连接管理 ===
    
    def handle_add_connection(self):
        """添加连接"""
        data = self.read_body()
        
        from_id = data.get("from")
        to_id = data.get("to")
        
        if not from_id or not to_id:
            self.send_json({"error": "from and to are required"}, 400)
            return
        
        connection = {
            "from": from_id,
            "to": to_id,
            "type": data.get("type", "direct"),
            "via": data.get("via"),
            "status": "active",
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        
        # 保存连接
        conn_file = self.topology_dir / "connections" / f"{from_id}-{to_id}.yaml"
        with open(conn_file, "w") as f:
            yaml.dump(connection, f)
        
        self._update_topology()
        self.send_json({"success": True, "connection": connection})
    
    def handle_test_connection(self, from_id: str, to_id: str):
        """测试连接"""
        # 简化实现：返回模拟结果
        self.send_json({
            "success": True,
            "from": from_id,
            "to": to_id,
            "latency_ms": 50,
            "status": "active"
        })
    
    # === 拓扑管理 ===
    
    def handle_get_topology(self):
        """获取完整拓扑"""
        topology_file = self.topology_dir / "topology.yaml"
        if topology_file.exists():
            with open(topology_file) as f:
                topology = yaml.safe_load(f)
        else:
            topology = {"servers": [], "connections": []}
        
        self.send_json(topology)
    
    def handle_get_status(self):
        """获取整体状态"""
        servers = self._load_servers()
        topology_file = self.topology_dir / "topology.yaml"
        
        if topology_file.exists():
            with open(topology_file) as f:
                topology = yaml.safe_load(f)
            connections = topology.get("connections", [])
        else:
            connections = []
        
        self.send_json({
            "servers_total": len(servers),
            "servers_online": len(servers),  # 简化
            "connections_total": len(connections),
            "connections_active": len(connections),
            "status": "running"
        })
    
    # === 辅助方法 ===
    
    def _load_servers(self) -> List[Dict]:
        """加载所有服务器"""
        servers = []
        servers_dir = self.topology_dir / "servers"
        if servers_dir.exists():
            for f in servers_dir.glob("*.yaml"):
                with open(f) as fp:
                    servers.append(yaml.safe_load(fp))
        return servers
    
    def _load_tokens(self) -> List[Dict]:
        """加载令牌"""
        if self.tokens_file.exists():
            with open(self.tokens_file) as f:
                return json.load(f)
        return []
    
    def _save_tokens(self, tokens: List[Dict]):
        """保存令牌"""
        self.tokens_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.tokens_file, "w") as f:
            json.dump(tokens, f, indent=2)
    
    def _update_topology(self):
        """更新主拓扑文件"""
        topology_file = self.topology_dir / "topology.yaml"
        
        if topology_file.exists():
            with open(topology_file) as f:
                topology = yaml.safe_load(f)
        else:
            topology = {"name": "my-servers", "version": "1.0"}
        
        servers = self._load_servers()
        topology["servers"] = [{"id": s["id"], "alias": s["alias"]} for s in servers]
        
        with open(topology_file, "w") as f:
            yaml.dump(topology, f)
    
    def _generate_ssh_config(self, server: Dict) -> str:
        """生成 SSH 配置"""
        lines = [
            f"Host {server['id']}",
            f"    HostName {server.get('ip_private', server.get('ip_public', 'unknown'))}",
            f"    Port {server.get('port', 22)}",
            f"    User {server.get('user_default', 'root')}",
        ]
        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="服务器网络拓扑 API 服务")
    parser.add_argument("--port", type=int, default=8888, help="监听端口")
    parser.add_argument("--host", default="0.0.0.0", help="监听地址")
    args = parser.parse_args()
    
    # 确保目录存在
    topology_dir = Path("~/.hermes/topology").expanduser()
    topology_dir.mkdir(parents=True, exist_ok=True)
    (topology_dir / "servers").mkdir(exist_ok=True)
    (topology_dir / "connections").mkdir(exist_ok=True)
    
    server = HTTPServer((args.host, args.port), TopologyAPIHandler)
    print(f"✓ API 服务已启动: http://{args.host}:{args.port}/api")
    print(f"  服务器列表: GET /api/servers")
    print(f"  注册服务器: POST /api/servers/register")
    print(f"  生成令牌: POST /api/tokens/generate")
    print(f"  加入网络: POST /api/join/<token>")
    print("")
    print("按 Ctrl+C 停止服务")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n服务已停止")
        server.shutdown()


if __name__ == "__main__":
    main()