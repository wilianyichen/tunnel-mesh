#!/usr/bin/env python3
"""
交互式配置助手 - 纯手动模式
用户逐步操作，助手生成配置文本供复制
"""

import os
import sys
import yaml
import time
from pathlib import Path
from typing import Dict, List, Optional


class InteractiveAssistant:
    """交互式配置助手"""
    
    def __init__(self):
        self.topology_dir = Path.home() / ".hermes" / "topology"
        self.servers_dir = self.topology_dir / "servers"
        self.connections_dir = self.topology_dir / "connections"
        
        # 确保目录存在
        self.topology_dir.mkdir(parents=True, exist_ok=True)
        self.servers_dir.mkdir(exist_ok=True)
        self.connections_dir.mkdir(exist_ok=True)
    
    def clear_screen(self):
        """清屏"""
        os.system('clear' if os.name == 'posix' else 'cls')
    
    def pause(self, msg="按 Enter 继续..."):
        """暂停等待"""
        input(f"\n{msg}")
    
    def run(self):
        """主循环"""
        while True:
            self.clear_screen()
            self.show_header()
            self.show_status()
            self.show_menu()
            
            choice = input("\n输入选择: ").strip().lower()
            
            if choice == '1':
                self.add_server()
            elif choice == '2':
                self.configure_connection()
            elif choice == '3':
                self.generate_registration()
            elif choice == '4':
                self.show_matrix()
            elif choice == '5':
                self.calculate_path()
            elif choice == '6':
                self.export_config()
            elif choice == '7':
                self.test_connection()
            elif choice == 'q':
                print("\n再见!")
                break
            else:
                print("\n无效选择")
                self.pause()
    
    def show_header(self):
        """显示标题"""
        print("=" * 60)
        print("   服务器网络拓扑配置助手")
        print("   (交互式模式 - 纯手动辅助)")
        print("=" * 60)
    
    def show_status(self):
        """显示当前状态"""
        servers = self._load_servers()
        connections = self._load_connections()
        
        print("\n当前状态:")
        print("-" * 60)
        
        if servers:
            print(f"已配置服务器: {len(servers)} 个")
            for s in servers:
                ip = s.get('ip_private') or s.get('ip_public') or 'N/A'
                print(f"  • {s['alias']} ({ip}:{s.get('port', 22)})")
        else:
            print("已配置服务器: 0 个")
        
        if connections:
            print(f"\n已配置连接: {len(connections)} 条")
            for c in connections:
                via = f" via {c['via']}" if c.get('via') else ""
                print(f"  • {c['from']} → {c['to']} ({c.get('type', 'direct')}{via})")
        else:
            print("\n已配置连接: 0 条")
        
        print("-" * 60)
    
    def show_menu(self):
        """显示菜单"""
        print("\n请选择操作:")
        print()
        print("  [1] 添加新服务器")
        print("  [2] 配置服务器间连接")
        print("  [3] 生成注册信息（供其他服务器使用）")
        print("  [4] 显示连接矩阵")
        print("  [5] 计算最优路径")
        print("  [6] 导出所有配置")
        print("  [7] 测试连接")
        print("  [q] 退出")
    
    def add_server(self):
        """添加服务器"""
        self.clear_screen()
        print("=" * 60)
        print("   添加新服务器")
        print("=" * 60)
        print()
        
        # 收集信息
        alias = input("服务器别名 (如 aliyun, node3): ").strip()
        if not alias:
            print("别名不能为空")
            self.pause()
            return
        
        ip = input("IP 地址: ").strip()
        if not ip:
            print("IP 不能为空")
            self.pause()
            return
        
        port = input("SSH 端口 [默认 22]: ").strip() or "22"
        user = input("登录用户 [默认 root]: ").strip() or "root"
        
        print("\n信任等级:")
        print("  [1] full   - 完全信任，可执行任意操作")
        print("  [2] admin  - 管理员权限")
        print("  [3] user   - 普通用户")
        print("  [4] guest  - 只读访问")
        trust_choice = input("选择 [默认 3]: ").strip() or "3"
        
        trust_map = {'1': 'full', '2': 'admin', '3': 'user', '4': 'guest'}
        trust = trust_map.get(trust_choice, 'user')
        
        # 生成配置
        server_id = alias.lower().replace("-", "_")
        server = {
            'id': server_id,
            'alias': alias,
            'ip_private': ip,
            'port': int(port),
            'user_default': user,
            'trust_level': trust,
            'created_at': time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        
        # 显示配置
        print("\n" + "=" * 60)
        print("生成的服务器配置:")
        print("-" * 60)
        print(yaml.dump(server, default_flow_style=False))
        print("-" * 60)
        
        # 询问保存
        save = input("\n保存此配置? [y/N]: ").strip().lower()
        if save == 'y':
            server_file = self.servers_dir / f"{server_id}.yaml"
            with open(server_file, 'w') as f:
                yaml.dump(server, f)
            print(f"✓ 已保存到: {server_file}")
        else:
            print("未保存")
        
        self.pause()
    
    def configure_connection(self):
        """配置连接"""
        self.clear_screen()
        print("=" * 60)
        print("   配置服务器间连接")
        print("=" * 60)
        
        servers = self._load_servers()
        if len(servers) < 2:
            print("\n需要至少 2 个服务器才能配置连接")
            self.pause()
            return
        
        print("\n可用服务器:")
        for i, s in enumerate(servers, 1):
            print(f"  [{i}] {s['alias']}")
        
        print()
        from_choice = input("源服务器 (输入编号): ").strip()
        to_choice = input("目标服务器 (输入编号): ").strip()
        
        try:
            from_server = servers[int(from_choice) - 1]['id']
            to_server = servers[int(to_choice) - 1]['id']
        except:
            print("无效选择")
            self.pause()
            return
        
        print("\n连接类型:")
        print("  [1] direct  - 直连")
        print("  [2] tunnel  - SSH 隧道")
        print("  [3] vpn     - VPN 连接")
        print("  [4] proxy   - 代理连接")
        type_choice = input("选择 [默认 1]: ").strip() or "1"
        
        type_map = {'1': 'direct', '2': 'tunnel', '3': 'vpn', '4': 'proxy'}
        conn_type = type_map.get(type_choice, 'direct')
        
        via = ""
        if conn_type in ['tunnel', 'proxy']:
            via = input("跳板服务器 (可选): ").strip()
        
        # 生成配置
        connection = {
            'from': from_server,
            'to': to_server,
            'type': conn_type,
            'status': 'pending',
            'created_at': time.strftime("%Y-%m-%dT%H:%M:%SZ")
        }
        if via:
            connection['via'] = via
        
        # 显示配置
        print("\n" + "=" * 60)
        print("生成的连接配置:")
        print("-" * 60)
        print(yaml.dump(connection, default_flow_style=False))
        
        # 生成 SSH 命令
        print("-" * 60)
        print("建议的 SSH 配置:")
        print()
        
        servers_info = {s['id']: s for s in servers}
        from_info = servers_info[from_server]
        to_info = servers_info[to_server]
        
        if conn_type == 'direct':
            ssh_config = f"""
Host {to_server}
    HostName {to_info.get('ip_private', 'N/A')}
    Port {to_info.get('port', 22)}
    User {to_info.get('user_default', 'root')}
"""
        elif conn_type == 'tunnel':
            local_port = 2200 + hash(to_server) % 1000
            ssh_config = f"""
# 在 {from_server} 上执行:
ssh -L {local_port}:{to_info.get('ip_private')}:{to_info.get('port', 22)} -N {via or 'target'}

# 本地连接:
Host {to_server}
    HostName localhost
    Port {local_port}
    User {to_info.get('user_default', 'root')}
"""
        
        print(ssh_config)
        print("-" * 60)
        
        # 询问保存
        save = input("\n保存此配置? [y/N]: ").strip().lower()
        if save == 'y':
            conn_file = self.connections_dir / f"{from_server}-{to_server}.yaml"
            with open(conn_file, 'w') as f:
                yaml.dump(connection, f)
            print(f"✓ 已保存到: {conn_file}")
            
            print("\n请手动执行以下步骤:")
            print("1. 复制上面的 SSH 配置到 ~/.ssh/config")
            print("2. 在源服务器上建立隧道（如需要）")
            print("3. 测试连接: ssh {} 'hostname'".format(to_server))
        else:
            print("未保存")
        
        self.pause()
    
    def generate_registration(self):
        """生成注册信息"""
        self.clear_screen()
        print("=" * 60)
        print("   生成注册信息")
        print("=" * 60)
        print()
        print("此信息用于在其他服务器上配置连接到本机")
        print()
        
        # 获取本机信息
        import subprocess
        
        try:
            hostname = subprocess.run(['hostname'], capture_output=True, text=True).stdout.strip()
        except:
            hostname = 'unknown'
        
        try:
            ip_result = subprocess.run(['hostname', '-I'], capture_output=True, text=True)
            local_ip = ip_result.stdout.strip().split()[0]
        except:
            local_ip = '127.0.0.1'
        
        # 获取公钥
        ssh_dir = Path.home() / '.ssh'
        public_key = ""
        for key_file in ['id_ed25519.pub', 'id_rsa.pub']:
            key_path = ssh_dir / key_file
            if key_path.exists():
                public_key = key_path.read_text().strip()
                break
        
        alias = input(f"服务器别名 [默认 {hostname}]: ").strip() or hostname
        port = input("SSH 端口 [默认 22]: ").strip() or "22"
        user = input(f"登录用户 [默认 {Path.home().name}]: ").strip() or Path.home().name
        
        # 生成注册信息
        print("\n" + "=" * 60)
        print("注册信息 (复制到目标服务器):")
        print("=" * 60)
        print()
        print("# ===== 服务器注册信息 =====")
        print(f"ALIAS={alias}")
        print(f"IP={local_ip}")
        print(f"PORT={port}")
        print(f"USER={user}")
        print(f"TRUST=full")
        if public_key:
            print(f"KEY={public_key}")
        print("# ==========================")
        print()
        
        print("在目标服务器上执行:")
        print()
        print("1. 添加公钥:")
        if public_key:
            print(f"   echo '{public_key}' >> ~/.ssh/authorized_keys")
        print()
        print("2. 配置 SSH config:")
        print(f"""
   cat >> ~/.ssh/config << EOF
Host {alias}
    HostName {local_ip}
    Port {port}
    User {user}
EOF
""")
        print()
        print("3. 测试连接:")
        print(f"   ssh {alias} 'hostname'")
        
        print("=" * 60)
        self.pause()
    
    def show_matrix(self):
        """显示连接矩阵"""
        self.clear_screen()
        print("=" * 60)
        print("   连接矩阵")
        print("=" * 60)
        print()
        
        servers = self._load_servers()
        connections = self._load_connections()
        
        if not servers:
            print("暂无服务器")
            self.pause()
            return
        
        server_ids = [s['id'] for s in servers]
        
        # 表头
        header = "        " + "  ".join(f"{sid[:8]}" for sid in server_ids)
        print(header)
        print("-" * 60)
        
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
        print("✓→ = 已配置  ? = 未配置  - = 自己")
        print()
        self.pause()
    
    def calculate_path(self):
        """计算最优路径"""
        self.clear_screen()
        print("=" * 60)
        print("   计算最优路径")
        print("=" * 60)
        
        servers = self._load_servers()
        if len(servers) < 2:
            print("\n需要至少 2 个服务器")
            self.pause()
            return
        
        print("\n可用服务器:")
        for i, s in enumerate(servers, 1):
            print(f"  [{i}] {s['alias']}")
        
        print()
        from_choice = input("起点服务器 (输入编号): ").strip()
        to_choice = input("终点服务器 (输入编号): ").strip()
        
        try:
            from_id = servers[int(from_choice) - 1]['id']
            to_id = servers[int(to_choice) - 1]['id']
        except:
            print("无效选择")
            self.pause()
            return
        
        # 导入路径计算
        scripts_dir = Path(__file__).parent
        sys.path.insert(0, str(scripts_dir))
        
        from graph import find_path
        
        result = find_path(from_id, to_id)
        
        print("\n" + "-" * 60)
        if result['success']:
            print(f"路径: {result['formatted']}")
            print(f"跳数: {result['hops']}")
            print(f"权重: {result['weight']:.2f}")
        else:
            print(result['error'])
        print("-" * 60)
        
        self.pause()
    
    def export_config(self):
        """导出配置"""
        self.clear_screen()
        print("=" * 60)
        print("   导出所有配置")
        print("=" * 60)
        print()
        
        servers = self._load_servers()
        connections = self._load_connections()
        
        # 生成完整 SSH config
        print("SSH 配置文件内容:")
        print("-" * 60)
        
        for s in servers:
            ip = s.get('ip_private') or s.get('ip_public') or 'N/A'
            print(f"""
Host {s['id']}
    HostName {ip}
    Port {s.get('port', 22)}
    User {s.get('user_default', 'root')}
""")
        
        print("-" * 60)
        
        # 询问保存
        save = input("\n保存到 ~/.ssh/config.d/topology.conf? [y/N]: ").strip().lower()
        if save == 'y':
            ssh_dir = Path.home() / '.ssh' / 'config.d'
            ssh_dir.mkdir(parents=True, exist_ok=True)
            
            config_file = ssh_dir / 'topology.conf'
            with open(config_file, 'w') as f:
                f.write("# Auto-generated by topology-manager\n\n")
                for s in servers:
                    ip = s.get('ip_private') or s.get('ip_public') or 'N/A'
                    f.write(f"Host {s['id']}\n")
                    f.write(f"    HostName {ip}\n")
                    f.write(f"    Port {s.get('port', 22)}\n")
                    f.write(f"    User {s.get('user_default', 'root')}\n")
                    f.write("\n")
            
            print(f"✓ 已保存到: {config_file}")
            print("\n请在 ~/.ssh/config 中添加:")
            print("    Include config.d/*.conf")
        else:
            print("未保存")
        
        self.pause()
    
    def test_connection(self):
        """测试连接"""
        self.clear_screen()
        print("=" * 60)
        print("   测试连接")
        print("=" * 60)
        
        servers = self._load_servers()
        if not servers:
            print("\n暂无服务器")
            self.pause()
            return
        
        print("\n可用服务器:")
        for i, s in enumerate(servers, 1):
            print(f"  [{i}] {s['alias']}")
        
        print()
        choice = input("选择服务器 (输入编号): ").strip()
        
        try:
            server = servers[int(choice) - 1]
        except:
            print("无效选择")
            self.pause()
            return
        
        import subprocess
        
        print(f"\n测试连接到 {server['alias']}...")
        
        try:
            result = subprocess.run(
                ['ssh', '-o', 'ConnectTimeout=5', '-o', 'BatchMode=yes', 
                 server['id'], 'hostname'],
                capture_output=True, text=True, timeout=10
            )
            
            if result.returncode == 0:
                print(f"✓ 连接成功")
                print(f"  主机名: {result.stdout.strip()}")
            else:
                print(f"✗ 连接失败")
                print(f"  错误: {result.stderr.strip()}")
        except subprocess.TimeoutExpired:
            print("✗ 连接超时")
        except Exception as e:
            print(f"✗ 测试失败: {e}")
        
        self.pause()
    
    def _load_servers(self) -> List[Dict]:
        """加载服务器"""
        servers = []
        for f in self.servers_dir.glob('*.yaml'):
            with open(f) as fp:
                servers.append(yaml.safe_load(fp))
        return servers
    
    def _load_connections(self) -> List[Dict]:
        """加载连接"""
        connections = []
        for f in self.connections_dir.glob('*.yaml'):
            with open(f) as fp:
                connections.append(yaml.safe_load(fp))
        return connections
    
    def _find_connection(self, connections: List[Dict], from_id: str, to_id: str) -> Optional[Dict]:
        """查找连接"""
        for c in connections:
            if c['from'] == from_id and c['to'] == to_id:
                return c
        return None


def main():
    assistant = InteractiveAssistant()
    assistant.run()


if __name__ == "__main__":
    main()