#!/usr/bin/env python3
"""Safe JSON operations for config.json. All user data passed via argv, never interpolated into code."""
import json, sys, os

CONFIG_PATH = os.path.expanduser("~/.tunnel-mesh/config.json")


def load():
    """读取 config.json，容忍空文件/JSON错误/无servers/servers值缺name字段"""
    try:
        with open(CONFIG_PATH) as f:
            raw = f.read().strip()
            d = json.loads(raw) if raw else {}
    except (FileNotFoundError, json.JSONDecodeError):
        d = {}
    if not isinstance(d, dict) or "servers" not in d:
        d = {"servers": {}, "edges": [], "ports": {"used": [], "next": 2201}}
    # 回填缺失的 name 字段（旧版 server_add 未写入）
    for key, val in d.get("servers", {}).items():
        if isinstance(val, dict) and "name" not in val:
            val["name"] = key
    return d


def load_stdin():
    """从 stdin 读取 JSON（保持原有行为，用于管道场景）"""
    return json.load(sys.stdin)


def emit(d):
    print(json.dumps(d, indent=2))

def cmd_get():
    """config_get <key.path> — print a value from config"""
    d = load()
    path = sys.argv[2] if len(sys.argv) > 2 else ""
    for key in path.split("."):
        if isinstance(d, dict) and key in d:
            d = d[key]
        else:
            print("")
            return
    if isinstance(d, (dict, list)):
        emit(d)
    else:
        print(d)

def cmd_server_exists():
    d = load()
    name = sys.argv[2] if len(sys.argv) > 2 else ""
    print(name in d.get("servers", {}))

def cmd_server_add():
    """server_add <name> <ip> <port> <user> <fingerprint> <pubkey>"""
    d = load()
    name = sys.argv[2]
    d.setdefault("servers", {})[name] = {
        "name": name,
        "ip": sys.argv[3] if len(sys.argv) > 3 else "?",
        "port": int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4].isdigit() else 22,
        "user": sys.argv[5] if len(sys.argv) > 5 else "root",
        "fingerprint": sys.argv[6] if len(sys.argv) > 6 else "",
        "pubkey": sys.argv[7] if len(sys.argv) > 7 else "",
        "added": os.environ.get("_NOW", ""),
    }
    emit(d)

def cmd_server_list():
    d = load()
    for s in d.get("servers", {}).values():
        print(f"  {s['name']:<15} {s['ip']}:{s['port']}")

def cmd_port_is_free():
    d = load()
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    used = d.get("ports", {}).get("used", [])
    print(port not in used)

def cmd_port_allocate():
    d = load()
    ports = d.setdefault("ports", {})
    used = ports.setdefault("used", [])
    nxt = ports.setdefault("next", 2201)
    while nxt in used:
        nxt += 1
    ports["next"] = nxt + 1
    emit(d)
    # also print allocated port to stdout for capture
    sys.stderr.write(f"ALLOCATED={nxt}\n")

def cmd_edge_add():
    """edge_add <id> <from> <to> <type> <tunnel_port> <tunnel_cmd> <maintainer> [fabric_id] [weight]"""
    d = load()
    eid = sys.argv[2]
    edge = {
        "id": eid,
        "from": sys.argv[3] if len(sys.argv) > 3 else "?",
        "to": sys.argv[4] if len(sys.argv) > 4 else "?",
        "type": sys.argv[5] if len(sys.argv) > 5 else "forward",
        "tunnel_port": int(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6].lstrip("-").isdigit() else 0,
        "tunnel_cmd": sys.argv[7] if len(sys.argv) > 7 else "",
        "maintainer": sys.argv[8] if len(sys.argv) > 8 else "",
        "status": "active",
        "created": os.environ.get("_NOW", ""),
    }
    # 可选字段
    if len(sys.argv) > 9 and sys.argv[9]:
        edge["fabric_id"] = sys.argv[9]
    if len(sys.argv) > 10 and sys.argv[10]:
        try:
            edge["weight"] = float(sys.argv[10])
        except ValueError:
            pass
    d.setdefault("edges", []).append(edge)
    tp = int(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6].lstrip("-").isdigit() else 0
    if tp > 0:
        ports = d.setdefault("ports", {})
        used = ports.setdefault("used", [])
        if tp not in used:
            used.append(tp)
    emit(d)

def cmd_edge_list():
    d = load()
    for e in d.get("edges", []):
        port_str = f" 端口:{e['tunnel_port']}" if e.get("tunnel_port") else ""
        print(f"  {e['id']:<25} {e.get('type','?'):<10} {port_str}")

def cmd_edge_remove():
    d = load()
    eid = sys.argv[2] if len(sys.argv) > 2 else ""
    edges = d.get("edges", [])
    # release port and rewind next if applicable
    released_port = 0
    for e in edges:
        if e.get("id") == eid and e.get("tunnel_port", 0) > 0:
            released_port = e["tunnel_port"]
            used = d.get("ports", {}).get("used", [])
            if released_port in used:
                used.remove(released_port)
    d["edges"] = [e for e in edges if e.get("id") != eid]
    # rewind ports.next to the smallest free port
    if released_port > 0:
        ports = d.setdefault("ports", {})
        ports.setdefault("used", [])
        nxt = ports.get("next", 2201)
        if released_port < nxt and released_port not in ports.get("used", []):
            ports["next"] = released_port
    emit(d)

def cmd_tunnel_cmds():
    """List all tunnel commands"""
    d = load()
    for e in d.get("edges", []):
        if e.get("tunnel_cmd"):
            print(e["tunnel_cmd"])
            print()

def cmd_tutorial():
    """Generate tutorial markdown — fabric.json 优先，fallback config.json"""
    d = load()
    hostname = os.environ.get("HOSTNAME", "localhost")

    # 尝试读 fabric.json
    fabric_path = os.path.expanduser("~/.tunnel-mesh/fabric.json")
    fabric = {}
    if os.path.isfile(fabric_path):
        try:
            with open(fabric_path) as f:
                fabric = json.load(f)
        except (json.JSONDecodeError, IOError):
            pass

    fabrics = fabric.get("fabrics", {})
    use_fabric = bool(fabrics)

    print("# Tunnel Mesh 教程")
    print()
    print("生成时间:", os.environ.get("_NOW", ""))
    print()

    if use_fabric:
        print("## 逻辑拓扑")
        print()
        print("```")
        for e in d.get("edges", []):
            t = e.get("type", "?")
            fid = e.get("fabric_id", "")
            arrow = "─隧道→" if t == "reverse" else "──→"
            fabric_tag = f"  [{fid}]" if fid else ""
            print(f"  {e['from']} {arrow} {e['to']}  ({t}){fabric_tag}")
        print("```")
        print()

        for fid, fab in fabrics.items():
            logical_edge = fab.get("logical_edge", "?")
            port = fab.get("port", 0)
            print(f"## Fabric: {fid}")
            print(f"逻辑边: **{logical_edge}**  端口: `{port}`")
            print()

            hops = fab.get("hops", [])
            if hops:
                print("### 物理跳")
                print()
                print("| 序号 | 从 | 到 | 类型 | 端口 | 命令 |")
                print("|------|----|----|------|------|------|")
                for h in hops:
                    seq = h.get("seq", "?")
                    hfrom = h.get("from", "?")
                    hto = h.get("to", "?")
                    htype = h.get("type", "?")
                    hport = h.get("port", 0)
                    hcmd = h.get("cmd", "").replace("|", "\\|")
                    print(f"| {seq} | {hfrom} | {hto} | {htype} | {hport or '-'} | `{hcmd}` |")
                print()

            maintainers = fab.get("maintainers", [])
            if maintainers:
                print("### 维持者（需持久化运行）")
                print()
                for m in maintainers:
                    node = m.get("node", "?")
                    role = m.get("role", "?")
                    persist = m.get("persist", "manual")
                    mcmd = m.get("cmd", "")
                    print(f"- **{node}** [{role}] ({persist})")
                    if mcmd:
                        print(f"  ```bash")
                        print(f"  {mcmd}")
                        print(f"  ```")
                print()

            externals = fab.get("external_maintainers", [])
            if externals:
                print("### 外部维持者")
                print()
                for e in externals:
                    ename = e.get("name", "?")
                    eplatform = e.get("platform", "linux")
                    ecmd = e.get("cmd", "")
                    print(f"- **{ename}** @ {eplatform}")
                    if eplatform == "windows":
                        print(f"  在 Windows 上用 `tunnel-mesh.ps1` → [2] 导入以下命令:")
                    if ecmd:
                        print(f"  ```")
                        print(f"  {ecmd}")
                        print(f"  ```")
                print()

            transit = fab.get("transit_nodes", {})
            if transit:
                print("### 中转节点")
                print()
                for tname, tn in transit.items():
                    print(f"- **{tname}**: {tn.get('ip','?')}:{tn.get('port',22)} ({tn.get('user','root')})")
                print()

        print("## 一键部署")
        print()
        print("在本机运行:")
        print("```bash")
        print("tunnel-mesh --cmd apply --yes")
        print("```")
        print("这将自动写入 SSH config 并生成 systemd 服务。")
        print()

    else:
        # 旧格式 fallback
        print("## 拓扑图")
        print()
        print("```")
        for e in d.get("edges", []):
            t = e.get("type", "?")
            arrow = "─隧道→" if t == "reverse" else "→"
            print(f"  {e['from']} {arrow} {e['to']}  ({t})")
        print("```")
        print()
        print("## 操作步骤")
        print()
        step = 1
        for e in d.get("edges", []):
            if e.get("type") != "reverse":
                continue
            print(f"### Step {step}: {e['from']} → {e['to']}（反向隧道）")
            print()
            print(f"在 **{e['from']}** 上 SSH config 已自动配置:")
            print("```")
            print(f"Host {e['to']}")
            print("    HostName localhost")
            print(f"    Port {e['tunnel_port']}")
            print("```")
            print()
            m = e.get("maintainer", "")
            cmd = e.get("tunnel_cmd", "")
            if m == "2":
                print("把以下命令发给 **维持者 (Windows)**:")
                print("```")
                print(cmd)
                print("```")
                print()
                print("Windows: 双击 tunnel-mesh.bat → [1]导入 → 粘贴命令")
            elif cmd:
                print(f"在 **{e['to']}** 上运行:")
                print("```")
                print(cmd)
                print("```")
            print()
            step += 1

    print("## 验证")
    print()
    print(f"在 **{hostname}** 上:")
    print("```bash")
    for e in d.get("edges", []):
        print(f'ssh {e["to"]} hostname')
    print("```")

def cmd_find_bridge():
    """find_bridge <target_a_ip> <target_a_port> <target_b_ip> <target_b_port>"""
    d = load()
    a_ip = sys.argv[2] if len(sys.argv) > 2 else ""
    a_port = sys.argv[3] if len(sys.argv) > 3 else "22"
    b_ip = sys.argv[4] if len(sys.argv) > 4 else ""
    b_port = sys.argv[5] if len(sys.argv) > 5 else "22"
    # Can't actually do TCP from python here; just list candidate servers
    # Caller in network.sh will do the actual TCP test
    candidates = []
    for name, s in d.get("servers", {}).items():
        candidates.append(f"{name} {s['ip']} {s.get('port', 22)}")
    print("\n".join(candidates))

def cmd_viz():
    """ASCII topology visualization"""
    d = load()
    servers = d.get("servers", {})
    edges = d.get("edges", [])
    if not servers:
        print("  (空图)")
        return
    # Simple: list nodes then edges with arrows
    print("节点:")
    for name, s in servers.items():
        extra = f" (公网:{s['public_ip']})" if s.get("public_ip") and s["public_ip"] != s.get("ip", "") else ""
        print(f"  {name}  {s.get('ip','?')}:{s.get('port',22)}{extra}")
    if not edges:
        print("\n  (无边)")
    else:
        print("\n边:")
        for e in edges:
            frm, to, typ = e["from"], e["to"], e.get("type", "?")
            label = f"{typ}"
            if e.get("tunnel_port"):
                label += f":{e['tunnel_port']}"
            arrow = "─隧道→" if typ == "reverse" else "──→"
            print(f"  {frm} {arrow} {to}  ({label})")
    # 提示 fabric 数据
    fabric_path = os.path.expanduser("~/.tunnel-mesh/fabric.json")
    if os.path.isfile(fabric_path):
        try:
            with open(fabric_path) as f:
                fabric = json.load(f)
            if fabric.get("fabrics"):
                print(f"\n  物理拓扑: {len(fabric['fabrics'])} 个 Fabric（运行 fabric-viz 查看详情）")
        except (json.JSONDecodeError, IOError):
            pass


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: _json_op.py <cmd> [args...]", file=sys.stderr)
        sys.exit(1)
    cmd = sys.argv[1]
    fn = globals().get(f"cmd_{cmd}")
    if not fn:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
    fn()
