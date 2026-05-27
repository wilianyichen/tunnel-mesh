#!/usr/bin/env python3
"""Tunnel Mesh — 统一 Python CLI 入口。所有数据操作通过此入口，bash/PS1 只做菜单展示。"""
import json
import os
import sys

# 确保能找到同目录和 lib 下的模块
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _SCRIPT_DIR)
sys.path.insert(0, os.path.join(_SCRIPT_DIR, "lib"))

from _json_op import load as config_load, emit as _emit

CONFIG_DIR = os.path.expanduser("~/.tunnel-mesh")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")


def config_save(d):
    """安全写入 config.json（含备份 + 锁）"""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    payload = json.dumps(d, indent=2)

    # 验证 JSON 合法性
    try:
        json.loads(payload)
    except json.JSONDecodeError:
        print("❌ config.json 写入校验失败", file=sys.stderr)
        return False

    # 备份 + 锁 + 写入
    import fcntl
    lock_path = CONFIG_PATH + ".lock"
    with open(lock_path, "w") as lf:
        try:
            fcntl.flock(lf, fcntl.LOCK_EX)
        except (IOError, OSError):
            pass  # 部分文件系统不支持锁，继续

        if os.path.exists(CONFIG_PATH):
            bak = os.path.join(CONFIG_DIR, f"config.json.bak.{_now_compact()}")
            try:
                with open(CONFIG_PATH) as src, open(bak, "w") as dst:
                    dst.write(src.read())
            except Exception:
                pass

        with open(CONFIG_PATH, "w") as f:
            f.write(payload)

        # 清理旧备份（保留最近 5 个）
        try:
            baks = sorted(
                [f for f in os.listdir(CONFIG_DIR) if f.startswith("config.json.bak.")],
                reverse=True
            )
            for old in baks[5:]:
                os.remove(os.path.join(CONFIG_DIR, old))
        except Exception:
            pass

    return True


def _now_compact():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")


def _now_iso():
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ═══════════════════════════════════════════════════════════
# JSON 输出辅助
# ═══════════════════════════════════════════════════════════

def _json_ok(data=None):
    """输出统一 JSON 成功响应"""
    print(json.dumps({"status": "ok", "data": data}, ensure_ascii=False))


def _json_err(msg):
    """输出统一 JSON 错误响应到 stderr"""
    print(json.dumps({"status": "error", "error": msg}, ensure_ascii=False), file=sys.stderr)


def _parse_json_flag(args):
    """解析 args 中的 --json / --no-json 标志，返回 (filtered_args, json_output, explicit)。
    explicit 表示用户显式指定了输出格式。"""
    filtered = [a for a in args if a not in ("--json", "--no-json")]
    has_json = any(a == "--json" for a in args)
    has_no_json = any(a == "--no-json" for a in args)
    explicit = has_json or has_no_json
    if has_no_json:
        return filtered, False, explicit
    return filtered, has_json, explicit


# ═══════════════════════════════════════════════════════════
# 命令实现
# ═══════════════════════════════════════════════════════════

def cmd_server_list(args, json_output=False):
    d = config_load()
    servers = d.get("servers", {})
    if json_output:
        _json_ok({"servers": servers})
        return
    for s in servers.values():
        extra = ""
        if s.get("fingerprint"):
            extra += f"  fp:{s['fingerprint'][:16]}..."
        print(f"  {s['name']:<15} {s.get('ip','?')}:{s.get('port',22)}{extra}")


def cmd_server_add(args, json_output=False):
    if len(args) < 2:
        if json_output:
            _json_err("用法: server-add <name> <ip> [port] [user] [fingerprint] [pubkey]")
        else:
            print("用法: tunnel_mesh.py server-add <name> <ip> [port] [user] [fingerprint] [pubkey]", file=sys.stderr)
        sys.exit(1)
    d = config_load()
    name, ip = args[0], args[1]
    port = int(args[2]) if len(args) > 2 and args[2].isdigit() else 22
    user = args[3] if len(args) > 3 else "root"
    fp = args[4] if len(args) > 4 else ""
    pubkey = args[5] if len(args) > 5 else ""
    existing = d.setdefault("servers", {}).get(name, {})
    d["servers"][name] = {
        "name": name, "ip": ip, "port": port, "user": user,
        "fingerprint": fp, "pubkey": pubkey, "added": _now_iso(),
    }
    config_save(d)
    if json_output:
        _json_ok({"name": name, "ip": ip, "port": port, "user": user})
    else:
        print(f"✓ 已添加服务器: {name} ({ip}:{port})")


def cmd_server_exists(args, json_output=False):
    d = config_load()
    name = args[0] if args else ""
    exists = name in d.get("servers", {})
    if json_output:
        _json_ok({"name": name, "exists": exists})
    else:
        print(exists)


def cmd_server_remove(args, json_output=False):
    if len(args) < 1:
        if json_output:
            _json_err("用法: server-remove <name>")
        else:
            print("用法: tunnel_mesh.py server-remove <name>", file=sys.stderr)
        sys.exit(1)
    d = config_load()
    name = args[0]
    if name not in d.get("servers", {}):
        if json_output:
            _json_err(f"服务器 '{name}' 不存在")
        else:
            print(f"❌ 服务器 '{name}' 不存在", file=sys.stderr)
        sys.exit(1)
    del d["servers"][name]
    d["edges"] = [e for e in d.get("edges", [])
                  if e.get("from") != name and e.get("to") != name]
    config_save(d)
    if json_output:
        _json_ok({"name": name, "removed": True})
    else:
        print(f"✓ 已删除服务器: {name}")


def cmd_edge_list(args, json_output=False):
    d = config_load()
    edges = d.get("edges", [])
    if json_output:
        _json_ok({"edges": edges})
        return
    for e in edges:
        port_str = f" 端口:{e['tunnel_port']}" if e.get("tunnel_port") else ""
        print(f"  {e['id']:<25} {e.get('type','?'):<10} {port_str}")


def cmd_edge_add(args, json_output=False):
    if len(args) < 3:
        if json_output:
            _json_err("用法: edge-add <from> <to> <type> [port] [cmd] [maintainer] [fabric_id] [weight]")
        else:
            print("用法: tunnel_mesh.py edge-add <from> <to> <type> [port] [cmd] [maintainer] [fabric_id] [weight]", file=sys.stderr)
        sys.exit(1)
    d = config_load()
    frm, to, etype = args[0], args[1], args[2]
    eid = f"{frm}→{to}"
    edge = {
        "id": eid, "from": frm, "to": to, "type": etype,
        "tunnel_port": int(args[3]) if len(args) > 3 and args[3].lstrip("-").isdigit() else 0,
        "tunnel_cmd": args[4] if len(args) > 4 else "",
        "maintainer": args[5] if len(args) > 5 else "",
        "status": "active", "created": _now_iso(),
    }
    if len(args) > 6 and args[6]:
        edge["fabric_id"] = args[6]
    if len(args) > 7 and args[7]:
        try:
            edge["weight"] = float(args[7])
        except ValueError:
            pass
    d.setdefault("edges", []).append(edge)
    tp = edge["tunnel_port"]
    if tp > 0:
        used = d.setdefault("ports", {}).setdefault("used", [])
        if tp not in used:
            used.append(tp)
    config_save(d)
    if json_output:
        _json_ok({"id": eid, "from": frm, "to": to, "type": etype, "port": tp})
    else:
        print(f"✓ 已添加边: {eid} ({etype})")


def cmd_edge_remove(args, json_output=False):
    if len(args) < 1:
        if json_output:
            _json_err("用法: edge-remove <id>")
        else:
            print("用法: tunnel_mesh.py edge-remove <id>", file=sys.stderr)
        sys.exit(1)
    d = config_load()
    eid = args[0]
    edges = d.get("edges", [])
    released_port = 0
    for e in edges:
        if e.get("id") == eid and e.get("tunnel_port", 0) > 0:
            released_port = e["tunnel_port"]
            used = d.get("ports", {}).get("used", [])
            if released_port in used:
                used.remove(released_port)
    d["edges"] = [e for e in edges if e.get("id") != eid]
    if released_port > 0:
        ports = d.setdefault("ports", {})
        ports.setdefault("used", [])
        nxt = ports.get("next", 2201)
        if released_port < nxt and released_port not in ports.get("used", []):
            ports["next"] = released_port
    config_save(d)
    if json_output:
        _json_ok({"id": eid, "removed": True, "released_port": released_port})
    else:
        print(f"✓ 已删除边: {eid}")


def cmd_port_is_free(args, json_output=False):
    d = config_load()
    port = int(args[0]) if args else 0
    used = d.get("ports", {}).get("used", [])
    free = port not in used
    if json_output:
        _json_ok({"port": port, "free": free})
    else:
        print(free)


def cmd_port_allocate(args, json_output=False):
    d = config_load()
    ports = d.setdefault("ports", {})
    used = ports.setdefault("used", [])
    nxt = ports.setdefault("next", 2201)
    while nxt in used:
        nxt += 1
    used.append(nxt)
    ports["next"] = nxt + 1
    config_save(d)
    if json_output:
        _json_ok({"port": nxt, "used_ports": used})
    else:
        print(nxt)


def cmd_viz(args, json_output=False):
    d = config_load()
    servers = d.get("servers", {})
    edges = d.get("edges", [])
    if json_output:
        server_list = {name: {"ip": s.get("ip", "?"), "port": s.get("port", 22)} for name, s in servers.items()}
        _json_ok({"servers": server_list, "edges": edges})
        return
    if not servers:
        print("  (空图)")
        return
    print("节点:")
    for name, s in servers.items():
        extra = f" (公网:{s['public_ip']})" if s.get("public_ip") and s["public_ip"] != s.get("ip", "") else ""
        print(f"  {name}  {s.get('ip','?')}:{s.get('port',22)}{extra}")
    if not edges:
        print("\n  (无边)")
        return
    print("\n边:")
    for e in edges:
        frm, to, typ = e["from"], e["to"], e.get("type", "?")
        label = f"{typ}"
        if e.get("tunnel_port"):
            label += f":{e['tunnel_port']}"
        arrow = "─隧道→" if typ == "reverse" else "──→"
        print(f"  {frm} {arrow} {to}  ({label})")


def cmd_tunnel_cmds(args, json_output=False):
    d = config_load()
    for e in d.get("edges", []):
        if e.get("tunnel_cmd"):
            print(e["tunnel_cmd"])
            print()


def cmd_tutorial(args, json_output=False):
    """生成部署教程 — fabric.json 优先，fallback config.json"""
    d = config_load()
    hostname = os.environ.get("HOSTNAME", os.uname().nodename if hasattr(os, "uname") else "localhost")
    fabric = _load_fabric()
    fabrics = fabric.get("fabrics", {})
    use_fabric = bool(fabrics)

    print("# Tunnel Mesh 教程\n")
    print("生成时间:", _now_iso())

    if use_fabric:
        print("\n## 逻辑拓扑\n```")
        for e in d.get("edges", []):
            t = e.get("type", "?")
            fid = e.get("fabric_id", "")
            arrow = "─隧道→" if t == "reverse" else "──→"
            fabric_tag = f"  [{fid}]" if fid else ""
            print(f"  {e['from']} {arrow} {e['to']}  ({t}){fabric_tag}")
        print("```")

        for fid, fab in fabrics.items():
            logical_edge = fab.get("logical_edge", "?")
            port = fab.get("port", 0)
            print(f"\n## Fabric: {fid}")
            print(f"逻辑边: **{logical_edge}**  端口: `{port}`\n")

            hops = fab.get("hops", [])
            if hops:
                print("### 物理跳\n")
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
                print("### 维持者（需持久化运行）\n")
                for m in maintainers:
                    node = m.get("node", "?")
                    role = m.get("role", "?")
                    persist = m.get("persist", "manual")
                    mcmd = m.get("cmd", "")
                    print(f"- **{node}** [{role}] ({persist})")
                    if mcmd:
                        print(f"  ```bash\n  {mcmd}\n  ```")
                print()

            externals = fab.get("external_maintainers", [])
            if externals:
                print("### 外部维持者\n")
                for ext in externals:
                    ename = ext.get("name", "?")
                    eplatform = ext.get("platform", "linux")
                    ecmd = ext.get("cmd", "")
                    print(f"- **{ename}** @ {eplatform}")
                    if eplatform == "windows":
                        print(f"  在 Windows 上用 `tunnel-mesh.ps1` → [2] 导入以下命令:")
                    if ecmd:
                        print(f"  ```\n  {ecmd}\n  ```")
                print()

            transit = fab.get("transit_nodes", {})
            if transit:
                print("### 中转节点\n")
                for tname, tn in transit.items():
                    print(f"- **{tname}**: {tn.get('ip','?')}:{tn.get('port',22)} ({tn.get('user','root')})")
                print()

        print("## 一键部署\n")
        print("在本机运行:\n```bash\ntunnel-mesh --cmd apply --yes\n```")
        print("这将自动写入 SSH config 并生成 systemd 服务。")

    else:
        print("\n## 拓扑图\n```")
        for e in d.get("edges", []):
            t = e.get("type", "?")
            arrow = "─隧道→" if t == "reverse" else "→"
            print(f"  {e['from']} {arrow} {e['to']}  ({t})")
        print("```\n")
        print("## 操作步骤\n")
        step = 1
        for e in d.get("edges", []):
            if e.get("type") != "reverse":
                continue
            print(f"### Step {step}: {e['from']} → {e['to']}（反向隧道）\n")
            print(f"在 **{e['from']}** 上 SSH config 已自动配置:")
            print("```")
            print(f"Host {e['to']}")
            print("    HostName localhost")
            print(f"    Port {e['tunnel_port']}")
            print("```\n")
            m = e.get("maintainer", "")
            cmd = e.get("tunnel_cmd", "")
            if m == "2":
                print("把以下命令发给 **维持者 (Windows)**:\n```")
                print(cmd)
                print("```\nWindows: 双击 tunnel-mesh.bat → [1]导入 → 粘贴命令")
            elif cmd:
                print(f"在 **{e['to']}** 上运行:\n```")
                print(cmd)
                print("```")
            print()
            step += 1

    print("## 验证\n")
    print(f"在 **{hostname}** 上:\n```bash")
    for e in d.get("edges", []):
        print(f'ssh {e["to"]} hostname')
    print("```")


def cmd_find_bridge(args, json_output=False):
    if len(args) < 4:
        print("用法: tunnel_mesh.py find-bridge <a_ip> <a_port> <b_ip> <b_port>", file=sys.stderr)
        sys.exit(1)
    d = config_load()
    candidates = []
    for name, s in d.get("servers", {}).items():
        candidates.append(f"{name} {s.get('ip','?')} {s.get('port',22)}")
    print("\n".join(candidates))


def cmd_identity(args=None, json_output=False):
    """输出本机身份卡（===IDENTITY v1=== 格式）"""
    import subprocess as _sp
    hostname = os.environ.get("HOSTNAME", os.uname().nodename)
    try:
        ip = _sp.check_output(["hostname", "-I"], text=True).strip().split()[0]
    except Exception:
        ip = "?.?.?.?"
    key_path = os.path.expanduser("~/.ssh/id_ed25519.pub")
    pubkey = ""
    if os.path.isfile(key_path):
        with open(key_path) as f:
            pubkey = f.read().strip()
    import hashlib
    checksum = hashlib.sha256((pubkey or " ").encode()).hexdigest()[:16]
    user = os.environ.get("USER", "root")
    if json_output:
        _json_ok({
            "hostname": hostname, "ip": ip, "port": 22,
            "user": user, "pubkey": pubkey, "checksum": f"sha256:{checksum}"
        })
        return
    print("===IDENTITY v1===")
    print(f"NAME={hostname}")
    print(f"IP={ip}")
    print("PORT=22")
    print(f"USER={user}")
    print(f"PUBKEY={pubkey}")
    print(f"CHECKSUM=sha256:{checksum}")
    print("===END===")


def cmd_identity_import(args, json_output=False):
    """从文本导入身份卡。用法: pipe 传入 或 直接参数"""
    import sys as _sys
    if not _sys.stdin.isatty():
        text = _sys.stdin.read()
    elif args:
        text = " ".join(args)
        # 支持参数中的换行符
        text = text.replace("\\n", "\n")
    else:
        print("用法: echo 'NAME=...' | tunnel_mesh.py identity-import", file=_sys.stderr)
        print("  或: tunnel_mesh.py identity-import 'NAME=x IP=1.2.3.4 ...'", file=_sys.stderr)
        _sys.exit(1)

    fields = {}
    for line in text.strip().split("\n"):
        line = line.strip()
        if not line or line.startswith("===") or line.startswith("CHECKSUM"):
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            fields[k.strip()] = v.strip()

    missing = [k for k in ["NAME", "IP"] if k not in fields]
    if missing:
        print(f"❌ 缺少必要字段: {', '.join(missing)}", file=_sys.stderr)
        _sys.exit(1)

    name = fields["NAME"]
    ip = fields["IP"]
    port = fields.get("PORT", "22")
    user = fields.get("USER", "root")
    pubkey = fields.get("PUBKEY", "")

    d = config_load()
    if name in d.get("servers", {}):
        print(f"⚠ 服务器 '{name}' 已存在，将被覆盖")

    d.setdefault("servers", {})[name] = {
        "name": name, "ip": ip,
        "port": int(port) if port.isdigit() else 22,
        "user": user,
        "fingerprint": "",
        "pubkey": pubkey,
        "added": _now_iso(),
    }
    config_save(d)
    print(f"✓ 已导入服务器: {name} ({ip}:{port})")


# ═══════════════════════════════════════════════════════════
def _probe_ssh(ssh_host, srv_info=None):
    """用 SSH config 别名探测 SSH 可达性。返回 (reachable, via_str)。
    ssh_host: server name（非 IP），让 SSH client 用 ~/.ssh/config
    srv_info: server dict from config.json（可选，用于获取 port/user）"""
    import subprocess as _sp
    port = srv_info.get("port", 22) if srv_info else 22
    user = srv_info.get("user", "root") if srv_info else "root"

    # 方式 1：直接用 server name（利用 SSH config 别名）
    cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
           "-o", "StrictHostKeyChecking=accept-new", ssh_host, "echo ok"]
    try:
        r = _sp.run(cmd, capture_output=True, text=True, timeout=10)
        if r.returncode == 0 and "ok" in r.stdout:
            return True, ""
    except (_sp.TimeoutExpired, Exception):
        pass

    # 方式 2：server name 不行，尝试 user@host 和 user@ip
    ip = srv_info.get("ip", "") if srv_info else ""
    for dest in [ssh_host, ip] if ip and ip != "?" else [ssh_host]:
        if not dest:
            continue
        try:
            cmd2 = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-p", str(port), f"{user}@{dest}", "echo ok"]
            r2 = _sp.run(cmd2, capture_output=True, text=True, timeout=10)
            if r2.returncode == 0 and "ok" in r2.stdout:
                via_str = f"user@ip:{port}" if dest == ip and dest != ssh_host else ""
                return True, via_str
        except (_sp.TimeoutExpired, Exception):
            pass

    # 方式 3：检查 ~/.ssh/config 中是否有 Host 条目，提取 HostName 和 Port
    ssh_config = os.path.expanduser("~/.ssh/config")
    if os.path.isfile(ssh_config):
        try:
            with open(ssh_config) as f:
                in_host = False
                conf_host = conf_port = None
                for line in f:
                    line = line.strip()
                    if line.startswith("Host ") and not line.startswith("HostName "):
                        in_host = (ssh_host in line.split())
                        conf_host = conf_port = None
                    elif in_host:
                        if line.startswith("HostName "):
                            conf_host = line.split()[1] if len(line.split()) > 1 else None
                        elif line.startswith("Port "):
                            parts = line.split()
                            conf_port = int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else None
                if conf_host:
                    # 用解析出的 HostName 和 Port 做 TCP 检查
                    via_str = f"{conf_host}:{conf_port or 22}"
                    import socket as _sock
                    s = _sock.socket(_sock.AF_INET, _sock.SOCK_STREAM)
                    s.settimeout(2)
                    try:
                        if s.connect_ex((conf_host, conf_port or 22)) == 0:
                            return True, via_str
                    except Exception:
                        pass
                    finally:
                        s.close()
        except Exception:
            pass

    return False, ""


# --cmd status / --cmd health
# ═══════════════════════════════════════════════════════════

def _check_port_local(port):
    """检查本地端口是否被监听"""
    import subprocess as _sp
    try:
        out = _sp.check_output(["ss", "-tlnp"], text=True, timeout=3)
        return f":{port} " in out
    except Exception:
        # fallback: try TCP connect
        import socket as _sock
        s = _sock.socket(_sock.AF_INET, _sock.SOCK_STREAM)
        s.settimeout(0.5)
        try:
            return s.connect_ex(("127.0.0.1", port)) == 0
        except Exception:
            return False
        finally:
            s.close()


def _test_ssh_jump(target_host, jump_via, srv_info=None):
    """通过跳板测试 SSH 连接。
    jump_via: 单个节点名或节点名列表（如 ['I1'] 或 ['I1','I2']）"""
    import subprocess as _sp
    port = srv_info.get("port", 22) if srv_info else 22
    user = srv_info.get("user", "root") if srv_info else "root"
    ip = srv_info.get("ip", "") if srv_info else ""

    j_arg = ",".join(jump_via) if isinstance(jump_via, list) else jump_via
    cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
           "-o", "StrictHostKeyChecking=accept-new", "-J", j_arg, target_host, "echo ok"]
    try:
        r = _sp.run(cmd, capture_output=True, text=True, timeout=15)
        if r.returncode == 0 and "ok" in r.stdout:
            return True
    except (_sp.TimeoutExpired, Exception):
        pass

    # Fallback: 用 IP 直连
    if ip and ip != "?":
        try:
            cmd2 = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                    "-o", "StrictHostKeyChecking=accept-new", "-J", j_arg,
                    "-p", str(port), f"{user}@{ip}", "echo ok"]
            r2 = _sp.run(cmd2, capture_output=True, text=True, timeout=15)
            return r2.returncode == 0 and "ok" in r2.stdout
        except (_sp.TimeoutExpired, Exception):
            pass

    return False


def cmd_status(args, json_output=False):
    d = config_load()
    edges = d.get("edges", [])
    if not edges:
        if json_output:
            _json_ok({"edges": [], "summary": "无配置的隧道"})
        else:
            print("(无配置的隧道)")
        return
    result_edges = []
    for e in edges:
        eid = e.get("id", "?")
        etype = e.get("type", "?")
        port = e.get("tunnel_port", 0)
        status = "未知"
        note = ""
        if etype == "reverse" and port > 0:
            listening = _check_port_local(port)
            if listening:
                status = "存活"
                note = f"localhost:{port} 监听中"
            else:
                status = "断开"
                note = f"localhost:{port} 无监听"
        elif etype == "forward":
            status = "直连"
            note = "无需隧道"
        else:
            note = "无隧道端口"
        result_edges.append({
            "id": eid, "type": etype, "port": port,
            "status": status, "note": note, "listening": _check_port_local(port) if port > 0 else None
        })
    if json_output:
        _json_ok({"edges": result_edges})
        return
    print(f"{'边ID':<30} {'类型':<12} {'端口':<8} {'状态':<10} {'备注'}")
    print("-" * 80)
    for re in result_edges:
        port_str = str(re["port"]) if re["port"] else "-"
        print(f"  {re['id']:<28} {re['type']:<12} {port_str:<8} {re['status']:<10} {re['note']}")


def cmd_health(args, json_output=False):
    d = config_load()
    edges = d.get("edges", [])
    if not edges:
        if json_output:
            _json_ok({"checks": [], "passed": 0, "failed": 0, "total": 0, "summary": "无配置的隧道"})
        else:
            print("(无配置的隧道)")
        return

    import socket as _sock
    passed, failed, total = 0, 0, 0
    checks = []  # JSON 模式收集结果

    def _add_check(eid, ok, detail):
        nonlocal passed, failed, total
        total += 1
        if ok:
            passed += 1
        else:
            failed += 1
        checks.append({"id": eid, "passed": ok, "detail": detail})

    for e in edges:
        eid = e.get("id", "?")
        etype = e.get("type", "?")
        port = e.get("tunnel_port", 0)

        if etype == "forward":
            target = e.get("to", "")
            srv = d.get("servers", {}).get(target, {})
            ip = srv.get("ip", "?")
            target_port = srv.get("port", 22)
            ok = False
            if ip and ip != "?":
                s = _sock.socket(_sock.AF_INET, _sock.SOCK_STREAM)
                s.settimeout(3)
                try:
                    ok = s.connect_ex((ip, target_port)) == 0
                except Exception:
                    pass
                finally:
                    s.close()
            detail = f"{ip}:{target_port} {'可达' if ok else '不可达'}"
            _add_check(eid, ok, detail)
            if not json_output:
                icon = "✅" if ok else "❌"
                print(f"  {icon} {eid}: {detail}")
        elif etype == "reverse" and port > 0:
            ok = _check_port_local(port)
            detail = f"localhost:{port} {'隧道存活' if ok else '隧道断开'}"
            _add_check(eid, ok, detail)
            if not json_output:
                icon = "✅" if ok else "❌"
                print(f"  {icon} {eid}: {detail}")
        elif etype == "proxyjump":
            candidates = e.get("proxyjump_candidates", [])
            target = e.get("to", "")
            srv = d.get("servers", {}).get(target, {})
            if candidates:
                best = candidates[0]
                via = best["via"]
                j_str = ",".join(via) if isinstance(via, list) else via
                ok = _test_ssh_jump(target, via, srv)
                detail = f"经 {j_str} 跳转 {target} {'可达' if ok else '失败'}"
                _add_check(eid, ok, detail)
                if not json_output:
                    icon = "✅" if ok else "❌"
                    print(f"  {icon} {eid}: {detail}")
            elif not json_output:
                print(f"  ⏭  {eid}: {etype}（无跳板候选）")
        elif etype == "chained":
            bridge = e.get("bridge", "")
            target = e.get("to", "")
            srv = d.get("servers", {}).get(target, {})
            if bridge:
                ok = _test_ssh_jump(target, bridge, srv)
                detail = f"经 {bridge} 桥接 {target} {'可达' if ok else '失败'}"
                _add_check(eid, ok, detail)
                if not json_output:
                    icon = "✅" if ok else "❌"
                    print(f"  {icon} {eid}: {detail}")
            elif not json_output:
                print(f"  ⏭  {eid}: {etype}（无桥接节点）")

    # 3. fabric.json 逐跳健康检查
    fabric = _load_fabric()
    for fid, fab in fabric.get("fabrics", {}).items():
        logical_edge = fab.get("logical_edge", "?")
        if not json_output:
            print(f"\n── Fabric: {fid} ({logical_edge}) ──")
        for hop in fab.get("hops", []):
            hop_type = hop.get("type", "?")
            hop_from = hop.get("from", "?")
            hop_to = hop.get("to", "?")
            hop_port = hop.get("port", 0)
            hid = f"{fid}/hop{hop.get('seq',0)}"
            if hop_type == "forward_direct":
                tip = hop.get("target_ip", "")
                tp = hop.get("target_port", 22)
                ok = False
                if tip:
                    s = _sock.socket(_sock.AF_INET, _sock.SOCK_STREAM)
                    s.settimeout(3)
                    try:
                        ok = s.connect_ex((tip, tp)) == 0
                    except Exception:
                        pass
                    finally:
                        s.close()
                detail = f"{hop_from} → {hop_to} ({hop_type}) {tip}:{tp} {'可达' if ok else '不可达'}"
                _add_check(hid, ok, detail)
                if not json_output:
                    icon = "✅" if ok else "❌"
                    print(f"  {icon} 跳{hop.get('seq',0)}: {detail}")
            elif hop_port > 0:
                ok = _check_port_local(hop_port)
                detail = f"{hop_from} → {hop_to} ({hop_type}) localhost:{hop_port} {'监听中' if ok else '无监听'}"
                _add_check(hid, ok, detail)
                if not json_output:
                    icon = "✅" if ok else "❌"
                    print(f"  {icon} 跳{hop.get('seq',0)}: {detail}")
            elif not json_output:
                print(f"  ⏭ 跳{hop.get('seq',0)}: {hop_from} → {hop_to} ({hop_type}) 无法检测")

    if json_output:
        summary = "全部健康" if (failed == 0 and total > 0) else ("无可检测的隧道" if total == 0 else f"{failed} 项失败")
        _json_ok({"checks": checks, "passed": passed, "failed": failed, "total": total, "summary": summary})
        return
    print(f"\n{'='*40}")
    print(f"结果: {passed} 通过 / {failed} 失败 / {total} 总计")
    if failed == 0 and total > 0:
        print("状态: 全部健康 ✓")
    elif total == 0:
        print("状态: 无可检测的隧道")


# ═══════════════════════════════════════════════════════════
# --cmd apply: 部署隧道（含冲突检测 + systemd 持久化）
# ═══════════════════════════════════════════════════════════

def _check_port_used_by_other(port):
    """检查端口是否被非 tunnel-mesh 进程占用"""
    import subprocess as _sp
    try:
        out = _sp.check_output(["ss", "-tlnp"], text=True, timeout=3)
        return f":{port} " in out
    except Exception:
        return False


def _check_ssh_config_conflicts(hostname):
    """检查 ~/.ssh/config 中是否有 Host 条目冲突（含 config.d/*.conf）"""
    ssh_config = os.path.expanduser("~/.ssh/config")
    conflicts = []
    for path in [ssh_config] + _list_config_d():
        if not os.path.isfile(path):
            continue
        try:
            with open(path) as f:
                in_host = False
                for line in f:
                    line = line.strip()
                    if line.startswith("Host ") and not line.startswith("HostName "):
                        current = line.split()
                        if hostname in current:
                            in_host = True
                            conflicts.append(f"{path}: {line}")
        except Exception:
            pass
    return conflicts


def _list_config_d():
    """列出 ~/.ssh/config.d/*.conf 文件"""
    config_d = os.path.expanduser("~/.ssh/config.d")
    if not os.path.isdir(config_d):
        return []
    import glob
    return sorted(glob.glob(os.path.join(config_d, "*.conf")))


def _load_fabric():
    """加载 fabric.json（物理连接层）"""
    fabric_path = os.path.expanduser("~/.tunnel-mesh/fabric.json")
    if os.path.isfile(fabric_path):
        try:
            with open(fabric_path) as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            pass
    return {"fabrics": {}}


def _generate_systemd_service(name, cmd):
    """生成 systemd user service 内容，自动注入 SSH 保活/失败检测选项"""
    # 注入关键 SSH 选项（幂等，已存在则跳过）
    if "ServerAliveInterval" not in cmd:
        cmd += " -o ServerAliveInterval=30 -o ServerAliveCountMax=3"
    if "ExitOnForwardFailure" not in cmd:
        cmd += " -o ExitOnForwardFailure=yes"
    if "TCPKeepAlive" not in cmd:
        cmd += " -o TCPKeepAlive=yes"
    if " -N " not in cmd and not cmd.endswith(" -N"):
        cmd = cmd.replace("ssh ", "ssh -N ", 1)

    return f"""[Unit]
Description=Tunnel Mesh: {name}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart={cmd}
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
"""


def _detect_identity():
    """返回本机节点名（用于 --local 过滤）"""
    return os.environ.get("HOSTNAME", os.uname().nodename)


def cmd_apply(args, json_output=False):
    """部署隧道：检测冲突、写入 SSH config、生成 systemd service
    --local: 仅部署本机为 from 的边（agent 安全模式）
    --json:  结构化输出"""
    dry_run = True
    yes_mode = False
    local_only = False
    remaining = []
    i = 0
    while i < len(args):
        if args[i] == "--yes":
            dry_run = False
            yes_mode = True
            i += 1
        elif args[i] == "--dry-run":
            dry_run = True
            i += 1
        elif args[i] == "--force":
            dry_run = False
            i += 1
        elif args[i] == "--local":
            local_only = True
            i += 1
        else:
            remaining.append(args[i])
            i += 1

    d = config_load()
    edges = d.get("edges", [])
    local_node = _detect_identity()
    hosts = set()
    plans = []

    for e in edges:
        eid = e.get("id", "?")
        etype = e.get("type", "?")
        port = e.get("tunnel_port", 0)
        target = e.get("to", "")
        cmd = e.get("tunnel_cmd", "")
        from_node = e.get("from", "")

        # --local 过滤：仅部署本机为 from 的边
        if local_only and from_node != local_node:
            continue
            plan = {"id": eid, "type": etype, "port": port, "target": target, "actions": [], "warnings": [], "errors": []}
            hosts.add(target)

            # 1. 端口冲突检测
            if _check_port_used_by_other(port):
                plan["warnings"].append(f"端口 {port} 已被占用（ss -tlnp 检测）")

            # 2. SSH config 冲突检测
            ssh_conflicts = _check_ssh_config_conflicts(target)
            if ssh_conflicts:
                for c in ssh_conflicts:
                    plan["warnings"].append(f"SSH config 冲突: {c}")

            # 3. SSH config 条目
            ssh_entry = f"Host {target}\n    HostName localhost\n    Port {port}\n    User {d.get('servers',{}).get(target,{}).get('user','root')}"
            plan["actions"].append({"type": "ssh_config", "host": target, "content": ssh_entry})

            # 4. 隧道命令 + systemd service
            if cmd:
                from_node = e.get("from", "")
                service_name = f"tunnel-mesh-rev-{from_node}-{target}.service"
                service_content = _generate_systemd_service(f"{from_node}→{target} (reverse)", cmd)
                plan["actions"].append({"type": "systemd_service", "name": service_name, "content": service_content})
                plan["actions"].append({"type": "enable_service", "name": service_name, "cmd": f"systemctl --user enable --now {service_name}"})

            plans.append(plan)

        elif etype == "forward":
            target = e.get("to", "")
            srv = d.get("servers", {}).get(target, {})
            ip = srv.get("ip", "?")
            target_port = srv.get("port", 22)
            user = srv.get("user", "root")
            cmd = e.get("tunnel_cmd", "")
            if ip and ip != "?":
                plan = {"id": eid, "type": etype, "port": target_port, "target": target, "actions": [], "warnings": [], "errors": []}
                hosts.add(target)
                ssh_conflicts = _check_ssh_config_conflicts(target)
                if ssh_conflicts:
                    for c in ssh_conflicts:
                        plan["warnings"].append(f"SSH config 冲突: {c}")
                ssh_entry = f"Host {target}\n    HostName {ip}\n    Port {target_port}\n    User {user}"
                plan["actions"].append({"type": "ssh_config", "host": target, "content": ssh_entry})
                # forward 边有 tunnel_cmd 时也生成 systemd service（维护本地端口转发）
                if cmd:
                    from_node = e.get("from", "")
                    service_name = f"tunnel-mesh-fwd-{from_node}-{target}.service"
                    service_content = _generate_systemd_service(f"{from_node}→{target} (forward)", cmd)
                    plan["actions"].append({"type": "systemd_service", "name": service_name, "content": service_content})
                    plan["actions"].append({"type": "enable_service", "name": service_name, "cmd": f"systemctl --user enable --now {service_name}"})
                plans.append(plan)

        elif etype == "proxyjump":
            target = e.get("to", "")
            srv = d.get("servers", {}).get(target, {})
            ip = srv.get("ip", "?")
            target_port = srv.get("port", 22)
            user = srv.get("user", "root")
            candidates = e.get("proxyjump_candidates", [])
            if ip and ip != "?" and candidates:
                plan = {"id": eid, "type": etype, "port": target_port, "target": target, "actions": [], "warnings": [], "errors": []}
                hosts.add(target)
                ssh_conflicts = _check_ssh_config_conflicts(target)
                if ssh_conflicts:
                    for c in ssh_conflicts:
                        plan["warnings"].append(f"SSH config 冲突: {c}")
                best = candidates[0]
                via = best["via"]
                j_arg = ",".join(via) if isinstance(via, list) else via
                ssh_entry = f"Host {target}\n    ProxyJump {j_arg}\n    HostName {ip}\n    Port {target_port}\n    User {user}"
                plan["actions"].append({"type": "ssh_config", "host": target, "content": ssh_entry})
                plan["actions"].append({"type": "info", "text": f"跳板: {j_arg} → {target} ({best.get('desc','')})"})
                plans.append(plan)

        elif etype == "chained":
            target = e.get("to", "")
            bridge = e.get("bridge", "")
            srv = d.get("servers", {}).get(target, {})
            ip = srv.get("ip", "?")
            target_port = srv.get("port", 22)
            user = srv.get("user", "root")
            if bridge and ip and ip != "?":
                plan = {"id": eid, "type": etype, "port": target_port, "target": target, "actions": [], "warnings": [], "errors": []}
                hosts.add(target)
                ssh_conflicts = _check_ssh_config_conflicts(target)
                if ssh_conflicts:
                    for c in ssh_conflicts:
                        plan["warnings"].append(f"SSH config 冲突: {c}")
                bridge_srv = d.get("servers", {}).get(bridge, {})
                if bridge_srv:
                    ssh_entry = f"Host {target}\n    ProxyJump {bridge}\n    HostName {ip}\n    Port {target_port}\n    User {user}"
                    plan["actions"].append({"type": "ssh_config", "host": target, "content": ssh_entry})
                    plan["actions"].append({"type": "info", "text": f"链式桥接: {bridge} → {target}"})
                else:
                    plan["warnings"].append(f"桥节点 {bridge} 不在服务器列表中")
                    plan["actions"].append({"type": "info", "text": f"需手动建立到 {bridge} 的隧道，然后通过 {bridge} 跳转到 {target}"})
                plans.append(plan)

    # 2. fabric.json 补充：为每个 fabric 的 maintainers 生成部署计划
    fabric = _load_fabric()
    for fid, fab in fabric.get("fabrics", {}).items():
        for m in fab.get("maintainers", []):
            m_cmd = m.get("cmd", "")
            if not m_cmd:
                continue
            node = m.get("node", "?")
            # --local 过滤：仅部署本机为维持者的 fabric
            if local_only and node != local_node:
                continue
            m_cmd = m.get("cmd", "")
            persist = m.get("persist", "manual")
            plan = {"id": f"{fid}/{node}", "type": "fabric_maintainer",
                    "port": 0, "target": node, "actions": [], "warnings": [], "errors": []}
            hosts.add(node)
            service_name = f"tunnel-mesh-fab-{fid}-{node}.service"
            service_content = _generate_systemd_service(f"{fid}/{node}", m_cmd)
            plan["actions"].append({"type": "systemd_service", "name": service_name, "content": service_content})
            plan["actions"].append({"type": "enable_service", "name": service_name,
                                     "cmd": f"systemctl --user enable --now {service_name}"})
            plan["actions"].append({"type": "info", "text": f"维持者: {node} [{persist}] {m_cmd}"})
            plans.append(plan)
    # external maintainers (Windows etc.)
    for fid, fab in fabric.get("fabrics", {}).items():
        for ext in fab.get("external_maintainers", []):
            ext_cmd = ext.get("cmd", "")
            if not ext_cmd:
                continue
            ext_name = ext.get("name", "?")
            # --local 过滤：外部维持者（Windows 等）不是本机，跳过
            if local_only:
                continue
            ext_cmd = ext.get("cmd", "")
            ext_platform = ext.get("platform", "linux")
            plan = {"id": f"{fid}/{ext_name}", "type": "fabric_external",
                    "port": 0, "target": ext_name, "actions": [], "warnings": [], "errors": []}
            if ext_platform == "windows":
                plan["actions"].append({"type": "info", "text": f"Windows 维持者: {ext_name}"})
                plan["actions"].append({"type": "info", "text": f"命令: {ext_cmd}"})
                plan["actions"].append({"type": "info", "text": "在 Windows 上用 tunnel-mesh.ps1 → [2] 导入此命令"})
            else:
                service_name = f"tunnel-mesh-fab-{fid}-{ext_name}.service"
                service_content = _generate_systemd_service(f"{fid}/{ext_name}", ext_cmd)
                plan["actions"].append({"type": "systemd_service", "name": service_name, "content": service_content})
                plan["actions"].append({"type": "enable_service", "name": service_name,
                                         "cmd": f"systemctl --user enable --now {service_name}"})
            plans.append(plan)

    # 输出
    total_actions = 0
    warnings_count = 0
    for plan in plans:
        for a in plan["actions"]:
            total_actions += 1

    if json_output:
        result = {
            "dry_run": dry_run,
            "local_node": local_node if local_only else None,
            "local_only": local_only,
            "plans": [],
            "total_actions": total_actions,
            "warnings_count": warnings_count,
        }
        for plan in plans:
            plan_out = {"id": plan["id"], "type": plan["type"], "target": plan.get("target", ""),
                        "port": plan.get("port", 0), "warnings": plan.get("warnings", []),
                        "actions": []}
            warnings_count += len(plan.get("warnings", []))
            for a in plan["actions"]:
                action_out = {"type": a["type"]}
                if a["type"] == "ssh_config":
                    action_out["host"] = a.get("host", "")
                elif a["type"] == "systemd_service":
                    action_out["name"] = a["name"]
                elif a["type"] == "enable_service":
                    action_out["cmd"] = a.get("cmd", "")
                elif a["type"] == "info":
                    action_out["text"] = a.get("text", "")
                plan_out["actions"].append(action_out)
            result["plans"].append(plan_out)
        result["warnings_count"] = warnings_count

        if not plans:
            result["note"] = "无需要部署的隧道"
            _json_ok(result)
            return

        if dry_run:
            _json_ok(result)
            return

        # JSON 模式执行不需要交互确认，--yes 已隐含
        _json_ok({**result, "executed": True, "results": _execute_plans(plans)})
        return

    # --- 人类可读输出（原有逻辑不变）---
    header = "🔍 预览模式 (--dry-run)" if dry_run else "🚀 执行模式"
    print(f"{header}\n")
    if not plans:
        print("(无需要部署的隧道)")
        return

    for plan in plans:
        print(f"  [{plan['type'].upper()}] {plan['id']}")
        if plan["warnings"]:
            for w in plan["warnings"]:
                print(f"    ⚠ {w}")
                warnings_count += 1
        for a in plan["actions"]:
            if a["type"] == "ssh_config":
                print(f"    📝 SSH config: ~/.ssh/config")
                print(f"       {a['content'].replace(chr(10), chr(10)+'       ')}")
            elif a["type"] == "systemd_service":
                print(f"    📝 systemd: ~/.config/systemd/user/{a['name']}")
            elif a["type"] == "enable_service":
                print(f"    ▶ {a['cmd']}")
            elif a["type"] == "info":
                print(f"    ℹ {a['text']}")
        print()

    print(f"──")
    print(f"总计: {total_actions} 个操作, {warnings_count} 个警告")

    if dry_run:
        print(f"\n确认无误后运行: tunnel-mesh --cmd apply --yes")
        return

    if not yes_mode and not _confirm("确认执行以上所有操作？[y/N] "):
        print("已取消")
        return

    # 实际执行
    print("\n执行中...")
    results = _execute_plans(plans)
    for r in results:
        if r.get("ok"):
            print(f"  ✓ {r['action']}")
        else:
            print(f"  ❌ {r['action']}: {r.get('error', '?')}")

    print("\n✓ 部署完成")


def _execute_plans(plans):
    """执行部署计划，返回结构化结果列表（供 apply --json 和 apply 人类可读共用）"""
    results = []
    is_windows = sys.platform == "win32"
    ssh_config_path = os.path.expanduser("~/.ssh/config")
    os.makedirs(os.path.dirname(ssh_config_path), exist_ok=True)

    if is_windows:
        return [{"action": "info", "ok": True, "detail": "Windows 请用 tunnel-mesh.ps1 [2] 导入隧道命令"}]

    systemd_user_dir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(systemd_user_dir, exist_ok=True)

    # 备份 SSH config
    if os.path.isfile(ssh_config_path):
        import shutil
        shutil.copy2(ssh_config_path, f"{ssh_config_path}.bak.{_now_compact()}")

    ssh_entries = []
    for plan in plans:
        for a in plan["actions"]:
            if a["type"] == "ssh_config":
                ssh_entries.append(a["content"])
            elif a["type"] == "systemd_service":
                svc_path = os.path.join(systemd_user_dir, a["name"])
                try:
                    with open(svc_path, "w") as f:
                        f.write(a["content"])
                    results.append({"action": f"写入 {svc_path}", "ok": True})
                except Exception as e:
                    results.append({"action": f"写入 {svc_path}", "ok": False, "error": str(e)})
            elif a["type"] == "enable_service":
                import subprocess as _sp
                try:
                    _sp.run(a["cmd"].split(), check=False)
                    results.append({"action": a["cmd"], "ok": True})
                except Exception as e:
                    results.append({"action": a["cmd"], "ok": False, "error": str(e)})

    # 去重写入 SSH config
    if ssh_entries:
        existing = set()
        if os.path.isfile(ssh_config_path):
            with open(ssh_config_path) as f:
                for line in f:
                    existing.add(line.strip())
        with open(ssh_config_path, "a") as f:
            for entry in ssh_entries:
                host_line = entry.split("\n")[0].strip()
                if host_line not in [l.strip() for l in existing]:
                    f.write("\n" + entry + "\n")
                    results.append({"action": f"添加 SSH config: {host_line}", "ok": True})

    return results


def _confirm(prompt):
    """简单确认提示"""
    try:
        return input(prompt).strip().lower() in ("y", "yes")
    except (EOFError, KeyboardInterrupt):
        return False


# ═══════════════════════════════════════════════════════════
# Fabric 命令
# ═══════════════════════════════════════════════════════════

def cmd_fabric_list(args, json_output=False):
    fabric = _load_fabric()
    fabrics = fabric.get("fabrics", {})
    if json_output:
        _json_ok({"fabrics": fabrics})
        return
    if not fabrics:
        print("  (无 Fabric)")
        return
    for fid, fab in fabrics.items():
        print(f"  {fid:<25} {fab.get('logical_edge','?'):<25} 端口:{fab.get('port','?')} 状态:{fab.get('status','?')}")


def cmd_fabric_health(args, json_output=False):
    fid = args[0] if args else ""
    fabric = _load_fabric()
    fabrics = fabric.get("fabrics", {})
    if fid:
        fab = fabrics.get(fid, {})
        result = {"id": fid, "status": fab.get("status", "unknown"), "hops": len(fab.get("hops", []))}
    else:
        result = {}
        for fid, fab in fabrics.items():
            result[fid] = {"status": fab.get("status", "unknown"), "hops": len(fab.get("hops", []))}
    # 始终输出 JSON（已有行为），但走统一格式
    if json_output:
        _json_ok(result)
    else:
        print(json.dumps(result, indent=2))


def cmd_fabric_cmds(args, json_output=False):
    fabric = _load_fabric()
    for fid, fab in fabric.get("fabrics", {}).items():
        for m in fab.get("maintainers", []):
            if m.get("cmd"):
                print(f"  [{m.get('node','?')}] {m['cmd']}")
        for ext in fab.get("external_maintainers", []):
            if ext.get("cmd"):
                print(f"  [{ext.get('name','?')} @ {ext.get('platform','?')}] {ext['cmd']}")


def cmd_fabric_viz(args, json_output=False):
    fabric = _load_fabric()
    fabrics = fabric.get("fabrics", {})
    if json_output:
        _json_ok({"fabrics": fabrics})
        return
    if not fabrics:
        print("  (无 Fabric 物理拓扑)")
        return
    print("物理拓扑:")
    for fid, fab in fabrics.items():
        print(f"\n  [{fid}] {fab.get('logical_edge','?')}")
        for hop in fab.get("hops", []):
            arrow = "─隧道→" if hop.get("type") == "reverse_tunnel" else "──→"
            print(f"    {hop.get('from','?')} {arrow} {hop.get('to','?')} ({hop.get('type','?')})")


# ═══════════════════════════════════════════════════════════
# 可达性命令（委托给 _reachability.py）
# ═══════════════════════════════════════════════════════════

def cmd_reachability(args, json_output=False):
    """多端口并行 TCP 探测，输出可达报告 JSON"""
    # 解析 --ports 参数
    ports_to_probe = [22, 80, 443, 8080, 8443, 18080]
    i = 0
    while i < len(args):
        if args[i] == "--ports" and i + 1 < len(args):
            ports_to_probe = [int(p) for p in args[i + 1].split(",") if p.strip().isdigit()]
            if not ports_to_probe:
                ports_to_probe = [22]
            i += 2
        else:
            i += 1

    d = config_load()
    # 融合 config.json 中所有 server 的自定义 SSH 端口
    custom_ports = set()
    for s in d.get("servers", {}).values():
        p = s.get("port", 22)
        if p:
            custom_ports.add(int(p))
    ports_to_probe = sorted(set(ports_to_probe) | custom_ports)
    import socket as _socket
    import time as _time
    from concurrent.futures import ThreadPoolExecutor, as_completed

    hostname = os.environ.get("HOSTNAME", os.uname().nodename)
    # 获取本机 IP
    import subprocess as _sp
    try:
        from_ip = _sp.check_output(["hostname", "-I"], text=True).strip().split()[0]
    except Exception:
        from_ip = "?"

    def probe_port(ip, port, timeout=2):
        """单端口 TCP 探测，返回 (port, reachable, latency_ms, error)"""
        sock = _socket.socket(_socket.AF_INET, _socket.SOCK_STREAM)
        sock.settimeout(timeout)
        start = _time.time()
        error = None
        reachable = False
        latency_ms = 0
        try:
            if sock.connect_ex((ip, int(port))) == 0:
                reachable = True
                latency_ms = int((_time.time() - start) * 1000)
            else:
                error = "refused"
        except _socket.timeout:
            error = "timeout"
        except OSError as e:
            error = str(e)
        finally:
            sock.close()
        return (port, reachable, latency_ms, error)

    results = []
    for name, s in sorted(d.get("servers", {}).items()):
        if name == hostname:
            continue
        ip = s.get("ip", "?")
        if not ip or ip == "?":
            results.append({"target": name, "ip": ip, "ports": {
                str(p): {"reachable": False, "error": "unknown IP"} for p in ports_to_probe
            }})
            continue

        # 并行探测所有端口
        ports_result = {}
        with ThreadPoolExecutor(max_workers=min(len(ports_to_probe), 10)) as executor:
            futures = {executor.submit(probe_port, ip, p): p for p in ports_to_probe}
            for future in as_completed(futures):
                p, reachable, lat, err = future.result()
                entry = {"reachable": reachable, "latency_ms": lat}
                if err:
                    entry["error"] = err
                ports_result[str(p)] = entry

        # 按端口号排序
        sorted_ports = {str(p): ports_result[str(p)] for p in sorted(ports_to_probe)}
        result_entry = {
            "target": name, "ip": ip,
            "default_port": s.get("port", 22),
            "ports": sorted_ports,
        }
        # SSH 可达探测（使用 server name，让 SSH client 使用 ~/.ssh/config 别名）
        ssh_ok, ssh_via = _probe_ssh(name, s)
        result_entry["ssh_reachable"] = ssh_ok
        if ssh_via:
            result_entry["ssh_via"] = ssh_via
        results.append(result_entry)

    report = {
        "from": hostname, "from_ip": from_ip,
        "timestamp": _now_iso(),
        "probed_ports": ports_to_probe,
        "results": results,
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))


def cmd_reachability_merge(args, json_output=False):
    import subprocess
    lib_dir = os.path.join(_SCRIPT_DIR, "lib")
    try:
        subprocess.run([sys.executable, os.path.join(lib_dir, "_reachability.py"), "merge"] + args, check=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ 可达报告合并失败 (exit {e.returncode})", file=sys.stderr)
        sys.exit(1)


def cmd_deploy_guide(args, json_output=False):
    import subprocess
    lib_dir = os.path.join(_SCRIPT_DIR, "lib")
    try:
        subprocess.run([sys.executable, os.path.join(lib_dir, "_reachability.py"), "deploy-guide"] + args, check=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ 部署指南生成失败 (exit {e.returncode})", file=sys.stderr)
        sys.exit(1)


def cmd_path(args, json_output=False):
    if len(args) < 2:
        print("用法: tunnel_mesh.py path <from> <to>", file=sys.stderr)
        sys.exit(1)
    import subprocess
    try:
        subprocess.run([sys.executable, os.path.join(_SCRIPT_DIR, "graph.py"),
                        "--json", "--from", args[0], "--to", args[1]], check=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ 路径查询失败 (exit {e.returncode})", file=sys.stderr)
        sys.exit(1)


def _detect_target_os(ip, port, user):
    """检测目标 OS 类型。返回 'linux' | 'windows' | 'unknown'"""
    import subprocess as _sp
    # 先检测 Windows（cmd /c 是 Windows 特有命令）
    try:
        r = _sp.run(
            ["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
             "-o", "StrictHostKeyChecking=accept-new",
             "-p", str(port), f"{user}@{ip}", "cmd /c echo WIN_OK"],
            capture_output=True, text=True, timeout=10
        )
        if "WIN_OK" in r.stdout:
            return "windows"
    except (_sp.TimeoutExpired, Exception):
        pass
    # 再检测 Linux（uname -s 输出 Linux）
    try:
        r = _sp.run(
            ["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
             "-o", "StrictHostKeyChecking=accept-new",
             "-p", str(port), f"{user}@{ip}", "uname -s"],
            capture_output=True, text=True, timeout=10
        )
        if "Linux" in r.stdout:
            return "linux"
    except (_sp.TimeoutExpired, Exception):
        pass
    return "unknown"


def _is_windows_admin(ip, port, user):
    """检测 Windows 用户是否在 Administrators 组"""
    import subprocess as _sp
    try:
        r = _sp.run(
            ["ssh", "-o", "ConnectTimeout=5",
             "-p", str(port), f"{user}@{ip}",
             "cmd /c \"whoami /groups | findstr S-1-5-32-544\""],
            capture_output=True, text=True, timeout=10
        )
        return "S-1-5-32-544" in r.stdout
    except (_sp.TimeoutExpired, Exception):
        return False


def _get_authorized_keys_path(ip, port, user):
    """返回目标服务器的 authorized_keys 正确路径"""
    os_type = _detect_target_os(ip, port, user)
    if os_type == "windows":
        if _is_windows_admin(ip, port, user):
            return "C:\\ProgramData\\ssh\\administrators_authorized_keys"
        else:
            return ".ssh\\authorized_keys"
    return "~/.ssh/authorized_keys"


def cmd_key_deploy(args, json_output=False):
    """部署本机公钥到目标服务器。用法: key-deploy <server> [--key <path>]"""
    import subprocess as _sp
    if len(args) < 1:
        if json_output:
            _json_err("用法: key-deploy <server> [--key ~/.ssh/id_ed25519.pub]")
        else:
            print("用法: tunnel_mesh.py key-deploy <server> [--key ~/.ssh/id_ed25519.pub]", file=sys.stderr)
        sys.exit(1)

    target = args[0]
    key_path = os.path.expanduser("~/.ssh/id_ed25519.pub")
    i = 1
    while i < len(args):
        if args[i] == "--key" and i + 1 < len(args):
            key_path = os.path.expanduser(args[i + 1])
            i += 2
        else:
            i += 1

    if not os.path.isfile(key_path):
        alt = os.path.expanduser("~/.ssh/id_rsa.pub")
        if os.path.isfile(alt):
            key_path = alt
        else:
            if json_output:
                _json_err(f"公钥文件不存在: {key_path}")
            else:
                print(f"❌ 公钥文件不存在: {key_path}", file=sys.stderr)
                print(f"   先生成: ssh-keygen -t ed25519", file=sys.stderr)
            sys.exit(1)

    with open(key_path) as f:
        pubkey = f.read().strip()

    d = config_load()
    srv = d.get("servers", {}).get(target, {})
    if not srv:
        if json_output:
            _json_err(f"服务器 '{target}' 不在 config.json 中，先 server-add")
        else:
            print(f"❌ 服务器 '{target}' 不在 config.json 中，先 server-add", file=sys.stderr)
        sys.exit(1)

    ip, port, user = srv["ip"], srv.get("port", 22), srv.get("user", "root")
    target_path = _get_authorized_keys_path(ip, port, user)
    if not json_output:
        print(f"🔑 部署公钥到 {target} ({user}@{ip}:{port})")
        print(f"   目标路径: {target_path}")

    # 构建远程命令：创建 .ssh 目录、追加公钥、去重
    if target_path.startswith("C:\\"):
        # Windows: 使用 PowerShell 追加
        remote_cmd = (
            f'powershell -Command \"'
            f'$path = \\\"{target_path}\\\"; '
            f'$dir = Split-Path $path -Parent; '
            f'if (!(Test-Path $dir)) {{ New-Item -ItemType Directory -Path $dir -Force | Out-Null }}; '
            f'$key = \\\"{pubkey}\\\"; '
            f'if (Test-Path $path) {{ $content = Get-Content $path -Raw; if ($content -notmatch [regex]::Escape($key)) {{ Add-Content -Path $path -Value $key }} }} '
            f'else {{ Set-Content -Path $path -Value $key }}'
            f'\"'
        )
    else:
        # Linux: 标准 shell
        remote_cmd = (
            f"mkdir -p ~/.ssh && touch {target_path} && chmod 600 {target_path} && "
            f"grep -qF '{pubkey}' {target_path} 2>/dev/null || echo '{pubkey}' >> {target_path}"
        )

    try:
        result = _sp.run(
            ["ssh", "-o", "ConnectTimeout=10", "-o", "StrictHostKeyChecking=accept-new",
             "-p", str(port), f"{user}@{ip}", remote_cmd],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            if json_output:
                _json_ok({"server": target, "user": user, "ip": ip, "port": port, "key_path": target_path})
            else:
                print(f"✓ 公钥已部署到 {target}")
                print(f"  验证: ssh {user}@{ip} -p {port}")
        else:
            err = result.stderr.strip() or result.stdout.strip()
            if json_output:
                _json_err(f"部署失败: {err}")
            else:
                print(f"❌ 部署失败: {err}", file=sys.stderr)
            sys.exit(1)
    except _sp.TimeoutExpired:
        if json_output:
            _json_err("SSH 连接超时")
        else:
            print(f"❌ SSH 连接超时", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        if json_output:
            _json_err(f"部署异常: {e}")
        else:
            print(f"❌ 部署异常: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_upgrade(args, json_output=False):
    """从 GitHub 拉取最新版本"""
    import subprocess as _sp, shutil
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.dirname(script_dir)

    if not shutil.which("git"):
        print("❌ 未找到 git。Windows 请用 Git Bash 运行，或手动下载最新版", file=sys.stderr)
        sys.exit(1)

    if not os.path.isdir(os.path.join(repo_dir, ".git")):
        print("❌ 当前不是 git 仓库，无法自动升级", file=sys.stderr)
        sys.exit(1)

    force = "--force" in args or "-f" in args
    print("⬇ 正在从 GitHub 拉取最新版本...")
    try:
        _sp.run(["git", "-C", repo_dir, "fetch", "origin"], check=True)
    except _sp.CalledProcessError:
        print("❌ git fetch 失败，请检查网络或手动 git pull", file=sys.stderr)
        sys.exit(1)

    # 检查是否有本地修改
    result = _sp.run(["git", "-C", repo_dir, "diff", "--stat"], capture_output=True, text=True)
    if result.stdout.strip():
        print("📦 暂存本地修改...")
        _sp.run(["git", "-C", repo_dir, "stash"], check=False)

    try:
        if force:
            _sp.run(["git", "-C", repo_dir, "reset", "--hard", "origin/main"], check=True)
        else:
            _sp.run(["git", "-C", repo_dir, "merge", "origin/main"], check=True)
    except _sp.CalledProcessError:
        print("❌ 合并失败，尝试 git reset --hard origin/main 或手动处理", file=sys.stderr)
        sys.exit(1)

    print("✓ 升级完成：")
    _sp.run(["git", "-C", repo_dir, "log", "--oneline", "-3"])


def cmd_deploy_windows(args, json_output=False):
    """部署隧道到 Windows 目标：推送 tunnel-mesh.ps1 + 注册 Scheduled Tasks。
    用法: deploy-windows <server>"""
    import subprocess as _sp, base64

    if len(args) < 1:
        if json_output:
            _json_err("用法: deploy-windows <server>")
        else:
            print("用法: tunnel_mesh.py deploy-windows <server>", file=sys.stderr)
        sys.exit(1)

    target = args[0]
    d = config_load()
    srv = d.get("servers", {}).get(target, {})
    if not srv:
        if json_output:
            _json_err(f"服务器 '{target}' 不在 config.json 中，先 server-add")
        else:
            print(f"❌ 服务器 '{target}' 不在 config.json 中，先 server-add", file=sys.stderr)
        sys.exit(1)

    ip = srv["ip"]
    port = srv.get("port", 22)
    user = srv.get("user", "root")

    # 1. 确认目标是 Windows
    os_type = _detect_target_os(ip, port, user)
    if os_type != "windows":
        if json_output:
            _json_err(f"{target} 不是 Windows 机器（检测结果: {os_type}），deploy-windows 仅支持 Windows 目标")
        else:
            print(f"❌ {target} 不是 Windows 机器（检测结果: {os_type}）", file=sys.stderr)
            print(f"   deploy-windows 仅支持 Windows 目标。Linux 请用 apply", file=sys.stderr)
        sys.exit(1)

    if not json_output:
        print(f"🖥  目标: {target} ({user}@{ip}:{port}) — Windows 检测确认")

    # 2. 传输 PS1 脚本到 Windows
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ps1_path = os.path.join(repo_root, "tunnel-mesh.ps1")
    reg_path = os.path.join(repo_root, "scripts", "register-tunnel.ps1")

    def _ssh(cmd, timeout=30):
        return _sp.run(
            ["ssh", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes",
             "-o", "StrictHostKeyChecking=accept-new",
             "-p", str(port), f"{user}@{ip}", cmd],
            capture_output=True, text=True, timeout=timeout
        )

    def _transfer_script(local_path, remote_name):
        """通过 scp 传输脚本文件到 Windows"""
        remote_path = f"%USERPROFILE%\\{remote_name}"
        # 展开 Windows 路径用于 SCP（scp 需要 Linux 风格路径或正确转义）
        # 直接传到家目录下的文件名
        r = _sp.run(
            ["scp", "-o", "ConnectTimeout=10", "-o", "BatchMode=yes",
             "-o", "StrictHostKeyChecking=accept-new",
             "-P", str(port), local_path,
             f"{user}@{ip}:{remote_name}"],
            capture_output=True, text=True, timeout=30
        )
        if r.returncode != 0:
            if json_output:
                _json_err(f"scp 传输 {remote_name} 失败: {r.stderr.strip()}")
            else:
                print(f"  ❌ scp 传输 {remote_name} 失败: {r.stderr.strip()}", file=sys.stderr)
            return False
        # 如果目标是 scripts\ 子目录，移动到正确位置
        if "\\" in remote_name:
            _ssh(f"cmd /c \"move /Y %USERPROFILE%\\{remote_name.split(chr(92))[-1]} %USERPROFILE%\\{remote_name} 2>nul\"")
        return True

    # 检查目标是否已有脚本
    check = _ssh("cmd /c \"if exist %USERPROFILE%\\tunnel-mesh.ps1 (echo EXISTS) else (echo MISSING)\"")
    if "EXISTS" in check.stdout:
        if not json_output:
            print("  ℹ tunnel-mesh.ps1 已存在于目标，跳过传输")
    else:
        if not json_output:
            print("  ⬆ 传输 tunnel-mesh.ps1 ...")
        if not _transfer_script(ps1_path, "tunnel-mesh.ps1"):
            if json_output:
                _json_err("脚本传输失败")
            else:
                print("❌ 脚本传输失败", file=sys.stderr)
            sys.exit(1)
        if not json_output:
            print("  ✓ tunnel-mesh.ps1 已部署")

    # 确保 scripts 目录存在
    _ssh("cmd /c \"if not exist %USERPROFILE%\\scripts mkdir %USERPROFILE%\\scripts\"")
    _transfer_script(reg_path, "scripts\\register-tunnel.ps1")

    # 3. 确保 SSH key 存在
    if not json_output:
        print("  🔑 确保 SSH key ...")
    _ssh("powershell -File %USERPROFILE%\\tunnel-mesh.ps1 --cmd ensure-scripts")

    # 4. 读取 fabric.json 找 maintainers
    fabric = _load_fabric()
    maintainer_cmds = []
    for fid, fab in fabric.get("fabrics", {}).items():
        for m in fab.get("maintainers", []):
            if m.get("node") == target and m.get("cmd"):
                maintainer_cmds.append((fid, m["cmd"]))
        for m in fab.get("external_maintainers", []):
            # external maintainers 用 name 匹配
            if m.get("name") == target and m.get("cmd"):
                maintainer_cmds.append(("external", m["cmd"]))

    # 如果 fabric 没有，尝试从 config.json edges 生成
    if not maintainer_cmds:
        for edge in d.get("edges", []):
            if edge.get("from") == target and edge.get("tunnel_cmd"):
                maintainer_cmds.append((edge.get("id", "edge"), edge["tunnel_cmd"]))

    if not maintainer_cmds:
        if json_output:
            _json_ok({"server": target, "warning": "未找到属于该节点的维持命令，请先配置 fabric 或 edge"})
        else:
            print("  ⚠ 未找到属于该节点的维持命令。请先配置 fabric 或 edge")
            print("  提示: python3 tunnel_mesh.py edge-add <from> <to> reverse <port> '<ssh_cmd>'")
        sys.exit(0)

    # 5. 注册隧道
    if not json_output:
        print(f"\n  注册 {len(maintainer_cmds)} 个隧道 ...")
    success = 0
    failures = []
    for src, cmd in maintainer_cmds:
        # 使用 register-tunnel.ps1 直接注册（比 tunnel-mesh.ps1 --cmd 更简单可靠）
        # 双引号转义：外层 Python f-string → 内层 PowerShell 双引号
        safe_cmd = cmd.replace('"', "'")
        r = _ssh(
            f'powershell -File %USERPROFILE%\\scripts\\register-tunnel.ps1 '
            f'-SshCommand "{safe_cmd}"',
            timeout=30
        )
        # stdout 可能混有 PowerShell profile 输出（如 kp 函数提示），
        # 只检查关键字段
        combined = r.stdout + r.stderr
        if "OK" in combined or '"status":"ok"' in combined or ('Register' not in combined and r.returncode == 0):
            # 检查 Scheduled Task 是否真的创建成功
            task_check = _ssh(
                f'powershell -Command "if (Get-ScheduledTask -TaskName \\"Tunnel-*\\" -ErrorAction SilentlyContinue) '
                f'{{ Write-Output \\"FOUND\\" }} else {{ Write-Output \\"NONE\\" }}"',
                timeout=10
            )
            if "FOUND" in task_check.stdout:
                if not json_output:
                    print(f"  ✓ [{src}] 已注册")
                success += 1
            else:
                if not json_output:
                    print(f"  ❌ [{src}] 注册未生效（可能需管理员权限）", file=sys.stderr)
                failures.append({"source": src, "error": "注册未生效（可能需管理员权限）"})
        else:
            err_msg = f"{r.stdout.strip()} {r.stderr.strip()}"
            if not json_output:
                print(f"  ❌ [{src}] 失败: {err_msg}", file=sys.stderr)
                # 提示可能需要管理员权限
                if "Access is denied" in combined or "denied" in combined.lower():
                    print(f"     💡 提示: Scheduled Task 注册需要管理员权限，请以管理员身份运行", file=sys.stderr)
            failures.append({"source": src, "error": err_msg.strip()})

    if json_output:
        _json_ok({"server": target, "user": user, "ip": ip, "deployed": success, "total": len(maintainer_cmds), "failures": failures})
    else:
        print(f"\n✓ 完成: {success}/{len(maintainer_cmds)} 隧道已部署到 {target}")
        print(f"  验证: ssh {user}@{ip} powershell -File tunnel-mesh.ps1 --cmd list-tunnels")


# ═══════════════════════════════════════════════════════════
# Phase 2: 自动化配置命令
# ═══════════════════════════════════════════════════════════

def _allocate_port(d):
    """从端口池分配下一个可用端口，返回端口号"""
    ports = d.setdefault("ports", {})
    used = ports.setdefault("used", [])
    nxt = ports.setdefault("next", 2201)
    while nxt in used:
        nxt += 1
    used.append(nxt)
    ports["next"] = nxt + 1
    config_save(d)
    return nxt


def _save_server(d, name, ip, port, user):
    """保存服务器到 config.json，返回更新后的 d"""
    d.setdefault("servers", {})[name] = {
        "name": name, "ip": ip, "port": int(port) if port else 22,
        "user": user or "root",
        "added": _now_iso(),
    }
    config_save(d)
    return d


def _save_edge(d, frm, to, typ, port, cmd):
    """保存边到 config.json，返回更新后的 d"""
    eid = f"{frm}→{to}"
    edge = {
        "id": eid, "from": frm, "to": to, "type": typ,
        "tunnel_port": int(port) if port else 0,
        "tunnel_cmd": cmd,
        "status": "active", "created": _now_iso(),
    }
    d.setdefault("edges", []).append(edge)
    tp = edge["tunnel_port"]
    if tp > 0:
        used = d.setdefault("ports", {}).setdefault("used", [])
        if tp not in used:
            used.append(tp)
    config_save(d)
    return d


# ═══════════════════════════════════════════════════════════

def cmd_discover(args, json_output=False):
    """基于 config.json 中所有 servers，运行全拓扑探测，输出边类型建议。
    用法: discover [--ports 22,80,443]"""
    import socket as _socket
    import time as _time
    from concurrent.futures import ThreadPoolExecutor, as_completed

    ports_to_probe = [22, 80, 443, 8080, 8443]
    i = 0
    while i < len(args):
        if args[i] == "--ports" and i + 1 < len(args):
            ports_to_probe = [int(p) for p in args[i + 1].split(",") if p.strip().isdigit()]
            i += 2
        else:
            i += 1

    d = config_load()
    servers = d.get("servers", {})
    existing_edges = d.get("edges", [])

    if len(servers) < 2:
        if json_output:
            _json_ok({"suggestions": [], "reason": "至少需要 2 个服务器才能探测拓扑"})
        else:
            print("至少需要 2 个服务器才能探测拓扑")
        return

    hostname = os.environ.get("HOSTNAME", os.uname().nodename if hasattr(os, "uname") else "localhost")

    # 1. TCP 可达矩阵探测
    def probe_tcp(ip, port, timeout=2):
        sock = _socket.socket(_socket.AF_INET, _socket.SOCK_STREAM)
        sock.settimeout(timeout)
        try:
            reachable = sock.connect_ex((ip, int(port))) == 0
        except Exception:
            reachable = False
        finally:
            sock.close()
        return reachable

    server_list = sorted(servers.keys())
    tcp_matrix = {}  # {name: {port: bool}}

    for name, s in servers.items():
        ip = s.get("ip", "")
        if not ip or ip == "?":
            tcp_matrix[name] = {str(p): False for p in ports_to_probe}
            continue
        tcp_matrix[name] = {}
        with ThreadPoolExecutor(max_workers=min(len(ports_to_probe), 10)) as executor:
            futures = {executor.submit(probe_tcp, ip, p): p for p in ports_to_probe}
            for future in as_completed(futures):
                p = futures[future]
                tcp_matrix[name][str(p)] = future.result()

    # 2. SSH 可达探测
    ssh_matrix = {}  # {(from_name, to_name): bool}
    for src_name in server_list:
        if src_name == hostname:
            # 本机到其他节点
            for dst_name in server_list:
                if dst_name == hostname:
                    continue
                dst = servers[dst_name]
                ok, via = _probe_ssh(dst_name, dst)
                ssh_matrix[(src_name, dst_name)] = ok
        # 非本机：检查 SSH config 中是否有跳板可达
        ssh_config = os.path.expanduser("~/.ssh/config")
        if os.path.isfile(ssh_config):
            for dst_name in server_list:
                if src_name == dst_name:
                    continue
                # 解析 SSH config 找 ProxyJump
                try:
                    with open(ssh_config) as f:
                        in_host = False
                        for line in f:
                            line = line.strip()
                            if line.startswith("Host ") and not line.startswith("HostName "):
                                in_host = dst_name in line.split()
                            elif in_host and line.startswith("ProxyJump "):
                                jump_host = line.split()[1]
                                # 检查这个 jump host 是否就是 src_name 的 server
                                if jump_host == src_name or src_name in jump_host:
                                    ssh_matrix[(src_name, dst_name)] = True
                except Exception:
                    pass

    # 3. 生成边类型建议
    suggestions = []
    existing_edge_pairs = {(e["from"], e["to"]) for e in existing_edges}

    for src in server_list:
        for dst in server_list:
            if src == dst:
                continue
            pair = (src, dst) in existing_edge_pairs

            src_info = servers[src]
            dst_info = servers[dst]
            src_ip = src_info.get("ip", "")
            dst_ip = dst_info.get("ip", "")

            # 检查 TCP 可达性
            dst_tcp = tcp_matrix.get(dst, {})
            ssh_port = str(dst_info.get("port", 22))
            direct_tcp = dst_tcp.get(ssh_port, False)
            direct_ssh = ssh_matrix.get((src, dst), False)

            suggestion = None

            if direct_ssh and direct_tcp:
                # 前向隧道（本地端口转发到远程）
                free_port = _allocate_port(d)
                if free_port:
                    suggestion = {
                        "from": src, "to": dst,
                        "type": "forward",
                        "port": free_port,
                        "cmd": f"ssh -N -L 0.0.0.0:{free_port}:localhost:{dst_info.get('port', 22)} {dst}",
                        "confidence": "high" if direct_ssh else "medium",
                        "reason": "直接 TCP + SSH 可达" if direct_ssh else "仅 TCP 可达",
                        "exists": pair,
                    }
            elif direct_ssh:
                suggestion = {
                    "from": src, "to": dst,
                    "type": "forward",
                    "port": dst_info.get("port", 22),
                    "cmd": f"ssh -N -L 0.0.0.0:{dst_info.get('port', 22)}:localhost:{dst_info.get('port', 22)} {dst}",
                    "confidence": "medium",
                    "reason": "SSH 可达（TCP 未探测）",
                    "exists": pair,
                }
            else:
                # 反向隧道：dst → src（从 dst 主动连接 src）
                free_port = _allocate_port(d)
                if free_port:
                    user = dst_info.get("user", "root")
                    suggestion = {
                        "from": dst, "to": src,
                        "type": "reverse_tunnel",
                        "port": free_port,
                        "cmd": f"ssh -N -R {free_port}:localhost:{src_info.get('port', 22)} {user}@{src_ip} -p {src_info.get('port', 22)}",
                        "confidence": "low",
                        "reason": "无直接 SSH 可达，尝试反向隧道",
                        "maintainer": dst,
                        "exists": pair,
                    }

            if suggestion:
                suggestions.append(suggestion)

    # 4. 检测 ProxyJump / 链式连接
    for src in server_list:
        for dst in server_list:
            if src == dst:
                continue
            if ssh_matrix.get((src, dst), False):
                continue  # 已经直接可达
            # 查找中转节点
            for mid in server_list:
                if mid in (src, dst):
                    continue
                if ssh_matrix.get((src, mid), False) and ssh_matrix.get((mid, dst), False):
                    free_port = _allocate_port(d)
                    if free_port:
                        suggestions.append({
                            "from": src, "to": dst,
                            "type": "chained",
                            "port": free_port,
                            "via": mid,
                            "cmd": f"ssh -J {mid} -N -L 0.0.0.0:{free_port}:localhost:{dst_info.get('port', 22)} {dst}",
                            "confidence": "medium",
                            "reason": f"通过 {mid} ProxyJump 链式连接",
                            "exists": False,
                        })
                    break  # 只需要一个中转节点

    if json_output:
        _json_ok({"suggestions": suggestions, "server_count": len(servers)})
    else:
        print(f"拓扑探测结果 ({len(servers)} 节点, {len(suggestions)} 建议):\n")
        if not suggestions:
            print("  无可用连接建议")
            return
        for sg in sorted(suggestions, key=lambda x: (x.get("confidence", "low"), x.get("from", ""))):
            marker = " (已存在)" if sg.get("exists") else " ✨新建"
            arrow = "─隧道→" if sg["type"] == "reverse_tunnel" else "──→"
            via_str = f" via {sg.get('via', '')}" if sg.get("via") else ""
            print(f"  {sg['from']} {arrow} {sg['to']}  [{sg['type']}:{sg['port']}]{via_str}  ({sg.get('confidence','?')}){marker}")
            print(f"    cmd: {sg['cmd']}")


def cmd_quickstart(args, json_output=False):
    """引导式配置：自动检测本机身份 → 探测拓扑 → 生成配置。
    用法: quickstart [--non-interactive] [--yes]"""
    non_interactive = "--non-interactive" in args
    auto_yes = "--yes" in args or non_interactive

    d = config_load()
    servers = d.get("servers", {})
    hostname = os.environ.get("HOSTNAME", os.uname().nodename if hasattr(os, "uname") else "localhost")

    # 收集结果
    steps = []
    errors = []

    if not json_output:
        print("╔══════════════════════════════════════════╗")
        print("║   Tunnel Mesh Quickstart                ║")
        print("╚══════════════════════════════════════════╝\n")

    # Step 1: 检测本机身份
    if not json_output:
        print("[1/5] 检测本机身份 ...")

    my_ip = "?"
    try:
        import subprocess as _sp
        my_ip = _sp.check_output(["hostname", "-I"], text=True).strip().split()[0]
    except Exception:
        pass

    my_port = 22
    try:
        out = _sp.check_output(["ss", "-tlnp"], text=True, timeout=3)
        for line in out.splitlines():
            if ":22 " in line and "sshd" in line:
                break
        else:
            my_port = int(os.environ.get("SSH_PORT", 22))
    except Exception:
        my_port = int(os.environ.get("SSH_PORT", 22))

    my_user = os.environ.get("USER", "root")
    my_pubkey = ""
    pubkey_path = os.path.expanduser("~/.ssh/id_ed25519.pub")
    if not os.path.isfile(pubkey_path):
        pubkey_path = os.path.expanduser("~/.ssh/id_rsa.pub")
    if os.path.isfile(pubkey_path):
        with open(pubkey_path) as f:
            my_pubkey = f.read().strip()

    identity = {
        "hostname": hostname, "ip": my_ip, "port": my_port,
        "user": my_user, "pubkey": my_pubkey,
    }
    steps.append({"step": "identity", "status": "ok", "data": identity})

    if not json_output:
        print(f"  本机: {hostname} ({my_user}@{my_ip}:{my_port})")
        print(f"  公钥: {'✓ ' + my_pubkey[:40] + '...' if my_pubkey else '✗ 未找到'}\n")

    # Step 2: 收集其他节点
    if not json_output:
        print("[2/5] 节点信息 ...")

    if not servers:
        if json_output:
            _json_ok({"steps": steps, "warning": "config.json 中无服务器，请先 server-add 添加节点"})
        else:
            print("  config.json 中暂无服务器。")
            print("  运行: python3 tunnel_mesh.py server-add <name> <ip> [port] [user]")
            print("  或粘贴身份卡: python3 tunnel_mesh.py identity-import")
        return
    else:
        if not json_output:
            print(f"  已配置 {len(servers)} 个节点: {', '.join(servers.keys())}\n")
        steps.append({"step": "nodes", "status": "ok", "count": len(servers), "nodes": list(servers.keys())})

    # Step 3: 密钥部署
    if not json_output:
        print("[3/5] 密钥部署 ...")

    key_deployed = []
    for name, s in servers.items():
        if name == hostname:
            continue
        if not my_pubkey:
            if not json_output:
                print(f"  ⚠ 跳过 {name}: 无本地公钥")
            continue
        # 探测 SSH 连接
        ok, _ = _probe_ssh(name, s)
        if ok:
            # 部署公钥
            ip = s.get("ip", "")
            port = s.get("port", 22)
            user = s.get("user", "root")
            try:
                r = _sp.run(
                    ["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
                     "-o", "StrictHostKeyChecking=accept-new",
                     "-p", str(port), f"{user}@{ip}",
                     f"grep -qF '{my_pubkey}' ~/.ssh/authorized_keys 2>/dev/null || echo '{my_pubkey}' >> ~/.ssh/authorized_keys"],
                    capture_output=True, text=True, timeout=15
                )
                if r.returncode == 0:
                    key_deployed.append(name)
                    if not json_output:
                        print(f"  ✓ {name}: 公钥已部署")
                else:
                    errors.append({"step": "key-deploy", "server": name, "error": r.stderr.strip()})
                    if not json_output:
                        print(f"  ⚠ {name}: 密钥部署失败 — {r.stderr.strip()[:80]}")
            except Exception as e:
                errors.append({"step": "key-deploy", "server": name, "error": str(e)})
                if not json_output:
                    print(f"  ✗ {name}: 连接失败 — {e}")
        else:
            if not json_output:
                print(f"  ⚠ {name}: SSH 不可达，跳过密钥部署")

    steps.append({"step": "key-deploy", "status": "ok", "deployed": key_deployed})

    # Step 4: 拓扑探测
    if not json_output:
        print("\n[4/5] 拓扑探测 ...")

    # 内联简易可达探测
    import socket as _sock
    from concurrent.futures import ThreadPoolExecutor, as_completed

    suggestions = []
    for src_name, src_info in servers.items():
        for dst_name, dst_info in servers.items():
            if src_name == dst_name:
                continue
            # check if edge already exists
            already = any(
                (e["from"] == src_name and e["to"] == dst_name) or
                (e["from"] == dst_name and e["to"] == src_name)
                for e in d.get("edges", [])
            )
            if already:
                continue

            # direct SSH probe
            ok, _ = _probe_ssh(dst_name, dst_info)
            if ok:
                free_port = _allocate_port(d)
                suggestions.append({
                    "from": src_name, "to": dst_name,
                    "type": "forward", "port": free_port,
                    "cmd": f"ssh -N -L 0.0.0.0:{free_port}:localhost:{dst_info.get('port', 22)} {dst_name}",
                    "confidence": "high",
                })
            else:
                # reverse tunnel suggestion
                free_port = _allocate_port(d)
                suggestions.append({
                    "from": dst_name, "to": src_name,
                    "type": "reverse_tunnel", "port": free_port,
                    "cmd": f"ssh -N -R {free_port}:localhost:{src_info.get('port', 22)} {src_info.get('user', 'root')}@{src_info.get('ip', '?')} -p {src_info.get('port', 22)}",
                    "confidence": "low",
                    "maintainer": dst_name,
                })

    steps.append({"step": "discover", "status": "ok", "suggestions": suggestions})

    if not json_output:
        if suggestions:
            print(f"  发现 {len(suggestions)} 个潜在连接:")
            for sg in suggestions:
                arrow = "─隧道→" if sg["type"] == "reverse_tunnel" else "──→"
                print(f"    {sg['from']} {arrow} {sg['to']}  [{sg['type']}:{sg['port']}] ({sg['confidence']})")
        else:
            print("  未发现新连接建议（所有边已存在）")

    # Step 5: 部署
    if not json_output:
        print(f"\n[5/5] 应用配置 ...")

    if suggestions and auto_yes:
        added = []
        for sg in suggestions:
            if sg["type"] == "forward":
                _ = _save_edge(d, sg["from"], sg["to"], sg["type"], sg["port"], sg.get("cmd", ""))
                added.append(f"{sg['from']}→{sg['to']}")
        if added:
            steps.append({"step": "apply", "status": "ok", "added": added})
            if not json_output:
                for a in added:
                    print(f"  ✓ {a} 已添加")
        else:
            if not json_output:
                print("  无新边需要添加")
    elif suggestions and not auto_yes:
        if not json_output:
            print(f"  发现 {len(suggestions)} 个建议连接，使用 --yes 自动应用")
            print(f"  或手动添加: python3 tunnel_mesh.py edge-add <from> <to> <type> <port> '<cmd>'")
        steps.append({"step": "apply", "status": "skipped", "reason": "需要 --yes 确认"})

    if json_output:
        _json_ok({"steps": steps, "errors": errors})
    else:
        print(f"\n✓ Quickstart 完成 ({len(steps)} 步骤, {len(errors)} 警告)")
        if not auto_yes and suggestions:
            print("  提示: 加 --yes 自动应用建议的边配置")


def cmd_ensure(args, json_output=False):
    """幂等操作：确保资源存在，可安全重复执行。
    用法:
      ensure server <name> <ip> [port] [user]
      ensure edge <from> <to> <type> <remote_port> <cmd>
      ensure key <server>"""
    if len(args) < 2:
        if json_output:
            _json_err("用法: ensure <server|edge|key> ...")
        else:
            print("用法: tunnel_mesh.py ensure <server|edge|key> ...", file=sys.stderr)
            print("  ensure server <name> <ip> [port] [user]", file=sys.stderr)
            print("  ensure edge <from> <to> <type> <remote_port> <cmd>", file=sys.stderr)
            print("  ensure key <server>", file=sys.stderr)
        sys.exit(1)

    resource_type = args[0]
    rest = args[1:]

    if resource_type == "server":
        if len(rest) < 2:
            if json_output:
                _json_err("ensure server 需要: <name> <ip> [port] [user] [--update-ip]")
            else:
                print("用法: ensure server <name> <ip> [port] [user] [--update-ip]", file=sys.stderr)
            sys.exit(1)
        # 解析 --update-ip 标志
        update_ip = False
        clean_rest = []
        for a in rest:
            if a == "--update-ip":
                update_ip = True
            else:
                clean_rest.append(a)
        rest = clean_rest

        name, ip = rest[0], rest[1]
        port = rest[2] if len(rest) > 2 else "22"
        user = rest[3] if len(rest) > 3 else "root"

        d = config_load()
        existing = d.get("servers", {}).get(name)
        if existing:
            if update_ip:
                old_ip = existing.get("ip", "")
                existing["ip"] = ip
                existing["port"] = int(port)
                existing["user"] = user
                d["servers"][name] = existing
                if not config_save(d):
                    if json_output:
                        _json_err("配置写入失败")
                    else:
                        print("❌ 配置写入失败", file=sys.stderr)
                    sys.exit(1)
                if json_output:
                    _json_ok({"name": name, "ip": ip, "port": port, "user": user,
                              "action": "updated", "old_ip": old_ip})
                else:
                    print(f"✓ {name}: IP 已更新 {old_ip} → {ip}")
                return
            if json_output:
                _json_ok({"name": name, "action": "noop", "reason": "已存在"})
            else:
                print(f"✓ {name} 已存在，跳过")
            return

        _ = _save_server(d, name, ip, port, user)
        if json_output:
            _json_ok({"name": name, "ip": ip, "port": port, "user": user, "action": "created"})
        else:
            print(f"✓ 已添加服务器: {name} ({user}@{ip}:{port})")

    elif resource_type == "edge":
        if len(rest) < 5:
            if json_output:
                _json_err("ensure edge 需要: <from> <to> <type> <remote_port> <cmd>")
            else:
                print("用法: ensure edge <from> <to> <type> <remote_port> <cmd>", file=sys.stderr)
            sys.exit(1)
        frm, to, typ = rest[0], rest[1], rest[2]
        remote_port = rest[3]
        cmd = rest[4] if len(rest) > 4 else ""

        d = config_load()
        # 检查是否已存在相同边
        for e in d.get("edges", []):
            if e.get("from") == frm and e.get("to") == to and e.get("type") == typ:
                if json_output:
                    _json_ok({"from": frm, "to": to, "type": typ, "action": "noop", "reason": "已存在"})
                else:
                    print(f"✓ 边 {frm}→{to} ({typ}) 已存在，跳过")
                return

        _ = _save_edge(d, frm, to, typ, remote_port, cmd)
        if json_output:
            _json_ok({"from": frm, "to": to, "type": typ, "port": remote_port, "action": "created"})
        else:
            print(f"✓ 已添加边: {frm}→{to} ({typ}:{remote_port})")

    elif resource_type == "key":
        if len(rest) < 1:
            if json_output:
                _json_err("ensure key 需要: <server>")
            else:
                print("用法: ensure key <server>", file=sys.stderr)
            sys.exit(1)
        target = rest[0]

        # 读取本地公钥
        pubkey_path = os.path.expanduser("~/.ssh/id_ed25519.pub")
        if not os.path.isfile(pubkey_path):
            pubkey_path = os.path.expanduser("~/.ssh/id_rsa.pub")
        if not os.path.isfile(pubkey_path):
            if json_output:
                _json_err("未找到本地公钥 (~/.ssh/id_ed25519.pub 或 id_rsa.pub)")
            else:
                print("❌ 未找到本地公钥", file=sys.stderr)
            sys.exit(1)
        with open(pubkey_path) as f:
            pubkey = f.read().strip()

        d = config_load()
        srv = d.get("servers", {}).get(target)
        if not srv:
            if json_output:
                _json_err(f"服务器 '{target}' 不在 config.json 中")
            else:
                print(f"❌ 服务器 '{target}' 不在 config.json 中", file=sys.stderr)
            sys.exit(1)

        ip = srv.get("ip", "")
        port = srv.get("port", 22)
        user = srv.get("user", "root")

        # 检查密钥是否已存在
        import subprocess as _sp
        try:
            check = _sp.run(
                ["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
                 "-o", "StrictHostKeyChecking=accept-new",
                 "-p", str(port), f"{user}@{ip}",
                 f"grep -qF '{pubkey[:80]}' ~/.ssh/authorized_keys 2>/dev/null && echo EXISTS || echo MISSING"],
                capture_output=True, text=True, timeout=10
            )
            if "EXISTS" in check.stdout:
                if json_output:
                    _json_ok({"server": target, "action": "noop", "reason": "密钥已存在"})
                else:
                    print(f"✓ {target}: 公钥已存在，跳过")
                return
        except Exception:
            pass

        # 部署密钥
        try:
            r = _sp.run(
                ["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
                 "-o", "StrictHostKeyChecking=accept-new",
                 "-p", str(port), f"{user}@{ip}",
                 f"mkdir -p ~/.ssh && echo '{pubkey}' >> ~/.ssh/authorized_keys"],
                capture_output=True, text=True, timeout=15
            )
            if r.returncode == 0:
                if json_output:
                    _json_ok({"server": target, "action": "deployed"})
                else:
                    print(f"✓ {target}: 公钥已部署")
            else:
                if json_output:
                    _json_err(f"密钥部署失败: {r.stderr.strip()}")
                else:
                    print(f"❌ 密钥部署失败: {r.stderr.strip()}", file=sys.stderr)
                sys.exit(1)
        except Exception as e:
            if json_output:
                _json_err(f"连接失败: {e}")
            else:
                print(f"❌ 连接失败: {e}", file=sys.stderr)
            sys.exit(1)

    else:
        if json_output:
            _json_err(f"未知资源类型: {resource_type}，可用: server, edge, key")
        else:
            print(f"❌ 未知资源类型: {resource_type}，可用: server, edge, key", file=sys.stderr)
        sys.exit(1)


def _edge_service_name(edge):
    """根据边类型返回对应的 systemd service 名称"""
    frm = edge.get("from", "")
    to = edge.get("to", "")
    etype = edge.get("type", "")
    if etype == "forward":
        return f"tunnel-mesh-fwd-{frm}-{to}.service"
    elif etype in ("reverse", "reverse_tunnel"):
        return f"tunnel-mesh-rev-{frm}-{to}.service"
    else:
        return f"tunnel-mesh-{frm}-{to}.service"


def cmd_service(args, json_output=False):
    """管控单条隧道的 systemd service。
    用法: service <edge-id|--all> <start|stop|restart|status>"""
    if len(args) < 2:
        if json_output:
            _json_err("用法: service <edge-id|--all> <start|stop|restart|status>")
        else:
            print("用法: service <edge-id|--all> <start|stop|restart|status>", file=sys.stderr)
        sys.exit(1)

    target = args[0]
    operation = args[1]
    if operation not in ("start", "stop", "restart", "status"):
        if json_output:
            _json_err(f"无效操作: {operation}，可用: start, stop, restart, status")
        else:
            print(f"无效操作: {operation}", file=sys.stderr)
        sys.exit(1)

    d = config_load()
    edges = d.get("edges", [])
    fabric = _load_fabric()

    # 收集所有 service 名称
    svc_names = []
    if target == "--all":
        for e in edges:
            svc_names.append(_edge_service_name(e))
        for fid, fab in fabric.get("fabrics", {}).items():
            for m in fab.get("maintainers", []):
                node = m.get("node", "?")
                svc_names.append(f"tunnel-mesh-fab-{fid}-{node}.service")
    else:
        # 按 edge id 查找
        found = None
        for e in edges:
            if e.get("id") == target:
                found = e
                break
        if not found:
            if json_output:
                _json_err(f"边 '{target}' 不存在")
            else:
                print(f"边 '{target}' 不存在", file=sys.stderr)
            sys.exit(1)
        svc_names.append(_edge_service_name(found))

    import subprocess as _sp
    results = []
    for name in svc_names:
        try:
            r = _sp.run(["systemctl", "--user", operation, name], capture_output=True, text=True, timeout=15)
            ok = r.returncode == 0
            results.append({"service": name, "operation": operation, "ok": ok,
                            "output": r.stdout.strip() or r.stderr.strip()})
        except Exception as e:
            results.append({"service": name, "operation": operation, "ok": False, "error": str(e)})

    if json_output:
        _json_ok({"operation": operation, "services": results})
    else:
        for r in results:
            status_icon = "✓" if r["ok"] else "✗"
            print(f"  {status_icon} {r['service']}: {r['operation']} {r.get('output', '')}")


def cmd_repair(args, json_output=False):
    """自愈：健康检查 → 重启失败的隧道 → 再检查。
    用法: repair [--scan] [--json]
    --scan: 对远程节点断开的隧道，自动调用 discover-ip 尝试找回。"""
    # 解析 --scan
    do_scan = False
    clean_args = [a for a in args if a != "--scan"]
    if len(clean_args) < len(args):
        do_scan = True
    args = clean_args

    d = config_load()
    edges = d.get("edges", [])
    fabric = _load_fabric()
    local_node = _detect_identity()

    # 1. 健康检查
    import subprocess as _sp
    failed_services = []
    health_results = []

    # 检查 edges
    for e in edges:
        eid = e.get("id", "?")
        target = e.get("to", "")
        port = e.get("tunnel_port", 0)
        etype = e.get("type", "?")

        passed = False
        detail = ""
        if etype == "forward":
            srv = d.get("servers", {}).get(target, {})
            ip = srv.get("ip", "?")
            srv_port = srv.get("port", 22)
            try:
                _sp.run(["timeout", "5", "bash", "-c", f"echo >/dev/tcp/{ip}/{srv_port}"],
                        check=True, capture_output=True)
                passed = True
            except Exception:
                detail = f"{ip}:{srv_port} 不可达"
        elif etype in ("reverse", "reverse_tunnel") and port > 0:
            try:
                _sp.run(["timeout", "2", "bash", "-c", f"echo >/dev/tcp/127.0.0.1/{port}"],
                        check=True, capture_output=True)
                passed = True
            except Exception:
                detail = f"localhost:{port} 隧道断开"

        health_results.append({"id": eid, "type": etype, "passed": passed, "detail": detail})
        if not passed:
            svc_name = _edge_service_name(e)
            frm = e.get("from", "")
            failed_services.append({"id": eid, "service": svc_name, "detail": detail,
                                    "from": frm, "type": etype})

    # 1.5 --scan: 对远程节点的失败隧道，尝试 discover-ip
    scan_results = []
    if do_scan:
        remote_failed = [fs for fs in failed_services
                         if fs.get("type") in ("reverse", "reverse_tunnel")
                         and fs.get("from") != local_node]
        for fs in remote_failed:
            frm = fs["from"]
            if not json_output:
                print(f"🔍 {frm} 隧道断开，扫描子网 ...")
            sr = _discover_single_server(frm, quick=False)
            scan_results.append(sr)
            if sr.get("updated"):
                fs["scan_found"] = True
                fs["scan_new_ip"] = sr["new_ip"]
                if not json_output:
                    print(f"  ✓ 找到 {frm}: {sr['old_ip']} → {sr['new_ip']}")

    # 2. 重启失败的服务（仅本机 service）
    repair_results = []
    for fs in failed_services:
        frm = fs.get("from", "")
        if frm and frm != local_node and fs.get("type") in ("reverse", "reverse_tunnel"):
            # 远程节点：跳过 service 重启（由对端 Scheduled Task 负责）
            repair_results.append({**fs, "restarted": False,
                                   "output": f"远程节点 {frm}，跳过本地重启"})
            continue
        try:
            r = _sp.run(["systemctl", "--user", "restart", fs["service"]],
                        capture_output=True, text=True, timeout=15)
            repair_results.append({**fs, "restarted": r.returncode == 0,
                                   "output": r.stdout.strip() or r.stderr.strip()})
        except Exception as e:
            repair_results.append({**fs, "restarted": False, "error": str(e)})

    # 3. 再检查（等待服务启动）
    import time
    time.sleep(2)
    recheck_results = []
    for fs in failed_services:
        eid = fs["id"]
        for e in edges:
            if e.get("id") == eid:
                port = e.get("tunnel_port", 0)
                etype = e.get("type", "?")
                alive = False
                if etype == "forward":
                    target_name = e.get("to", "")
                    srv = d.get("servers", {}).get(target_name, {})
                    ip = srv.get("ip", "?")
                    srv_port = srv.get("port", 22)
                    try:
                        _sp.run(["timeout", "5", "bash", "-c", f"echo >/dev/tcp/{ip}/{srv_port}"],
                                check=True, capture_output=True)
                        alive = True
                    except Exception:
                        pass
                elif port > 0:
                    try:
                        _sp.run(["timeout", "2", "bash", "-c", f"echo >/dev/tcp/127.0.0.1/{port}"],
                                check=True, capture_output=True)
                        alive = True
                    except Exception:
                        pass
                recheck_results.append({"id": eid, "alive": alive})
                break

    result = {
        "health": health_results,
        "failed_count": len(failed_services),
        "repairs": repair_results,
        "recheck": recheck_results,
    }
    if do_scan and scan_results:
        result["scan_results"] = scan_results

    if json_output:
        _json_ok(result)
    else:
        total = len(health_results)
        failed = len(failed_services)
        recovered = sum(1 for r in recheck_results if r.get("alive"))
        print(f"健康: {total - failed}/{total} 通过")
        if failed:
            print(f"修复: 重启 {failed} 条隧道")
            for r in repair_results:
                icon = "✓" if r.get("restarted") else "✗"
                print(f"  {icon} {r['id']}: {r.get('output', '')}")
            print(f"恢复: {recovered}/{failed}")


def cmd_scan_watch(args, json_output=False):
    """cron 友好的定时扫描：对所有有 pubkey 的 server 做 quick 扫描，
    IP 变化自动更新。--quiet 模式：无变化时不输出。
    用法: scan-watch [--quiet] [--subnets ...] [--json]"""
    quiet = False
    subnets = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--quiet":
            quiet = True
        elif a == "--subnets" and i + 1 < len(args):
            subnets = [s.strip() for s in args[i + 1].split(",") if s.strip()]
            i += 1
        i += 1

    d = config_load()
    servers = d.get("servers", {})
    target_names = [n for n, s in servers.items() if s.get("pubkey")]

    changes = []
    for name in target_names:
        r = _discover_single_server(name, quick=True, subnets=subnets)
        if r.get("updated"):
            changes.append(r)
        elif r.get("error"):
            pass  # 静默跳过不可扫描的 server

    # 记录到日志
    log_path = os.path.join(CONFIG_DIR, "scan-watch.log")
    import datetime as _dt
    ts = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    summary = f"[{ts}] 扫描 {len(target_names)} 台: {len(changes)} 变化"
    try:
        with open(log_path, "a") as lf:
            if changes:
                for c in changes:
                    lf.write(f"[{ts}] {c['server']}: {c['old_ip']} → {c['new_ip']}\n")
            else:
                lf.write(f"{summary}\n")
    except Exception:
        pass

    if json_output:
        _json_ok({"changes": changes, "scanned": len(target_names)})
    elif changes:
        for c in changes:
            print(f"✓ {c['server']}: {c['old_ip']} → {c['new_ip']}")
    elif not quiet:
        print(summary)


def _try_connect(ip):
    """单 IP 的 TCP connect 探测，供 _scan_subnet 并发调用"""
    import socket as _sock
    s = _sock.socket(_sock.AF_INET, _sock.SOCK_STREAM)
    s.settimeout(0.5)
    try:
        if s.connect_ex((ip, 22)) == 0:
            return {"ip": ip}
    except Exception:
        pass
    finally:
        s.close()
    return None


def _scan_subnet(subnet, max_workers=50):
    """并发 TCP connect 扫描一个子网中所有 IP 的 22 端口。
    50 线程并发 → /24 扫描 ~2-5s（原串行 ~30s）。
    返回: [{"ip": "x.x.x.x"}, ...]"""
    import ipaddress as _ipaddr
    from concurrent.futures import ThreadPoolExecutor, as_completed
    results = []
    try:
        net = _ipaddr.IPv4Network(subnet, strict=False)
    except ValueError:
        return results
    ips = [str(ip) for ip in net.hosts()]
    if not ips:
        return results
    with ThreadPoolExecutor(max_workers=min(max_workers, len(ips))) as executor:
        futures = {executor.submit(_try_connect, ip): ip for ip in ips}
        for f in as_completed(futures):
            r = f.result()
            if r:
                results.append(r)
    return results


def _get_host_key_fingerprint(ip, port=22):
    """获取远程 SSH host key 的 SHA256 指纹（通过 ssh-keyscan + ssh-keygen）。
    返回: "SHA256:xxxx..." 或 None"""
    import subprocess as _sp
    try:
        r = _sp.run(["ssh-keyscan", "-p", str(port), "-T", "3", ip],
                    capture_output=True, text=True, timeout=8)
        for line in r.stdout.splitlines():
            if line.startswith("#") or not line.strip():
                continue
            r2 = _sp.run(["ssh-keygen", "-lf", "-"],
                        input=line, capture_output=True, text=True, timeout=3)
            parts = r2.stdout.strip().split()
            if len(parts) >= 2:
                return parts[1]
    except Exception:
        pass
    return None


def _pubkey_to_fingerprint(pubkey):
    """将 config.json 中的公钥字符串转为 SHA256 指纹（与 ssh-keygen -lf 格式一致）。
    返回: "SHA256:xxxx..." 或 None"""
    import base64 as _b64
    import hashlib as _hashlib
    try:
        parts = pubkey.strip().split()
        if len(parts) >= 2:
            raw = _b64.b64decode(parts[1])
            h = _hashlib.sha256(raw).digest()
            return "SHA256:" + _b64.b64encode(h).decode().rstrip("=")
    except Exception:
        pass
    return None


def _discover_single_server(name, quick=False, subnets=None, config=None):
    """扫描子网发现单个 server 的新 IP。供 discover-ip 和 repair --scan 共用。
    返回: dict with server, found, old_ip, new_ip, updated, scanned, candidates, error"""
    d = config if config is not None else config_load()
    servers = d.get("servers", {})
    srv = servers.get(name)
    if not srv:
        return {"server": name, "found": False, "error": "server 不在 config 中"}
    pubkey = srv.get("pubkey", "")
    if not pubkey:
        return {"server": name, "found": False, "error": "无 pubkey"}

    target_fp = _pubkey_to_fingerprint(pubkey)
    old_ip = srv.get("ip", "")

    # 子网列表
    scan_subnets = list(subnets) if subnets else []
    if not scan_subnets:
        if old_ip:
            parts = old_ip.split(".")
            if len(parts) == 4:
                scan_subnets.append(f"{parts[0]}.{parts[1]}.{parts[2]}.0/24")

    if not scan_subnets:
        return {"server": name, "found": False, "error": "无子网可扫描"}

    found_ip = None
    candidates = []
    total_scanned = 0
    total_responsive = 0

    for subnet in scan_subnets:
        responsive = _scan_subnet(subnet)
        try:
            import ipaddress as _ipaddr
            total_scanned += max(0, _ipaddr.IPv4Network(subnet, strict=False).num_addresses - 2)
        except Exception:
            total_scanned += 256
        total_responsive += len(responsive)

        for entry in responsive:
            ip = entry["ip"]
            if quick:
                if ip == old_ip:
                    candidates.append({"ip": ip, "matched": False, "reason": "quick: same as current"})
                    continue
                candidates.append({"ip": ip, "matched": False, "reason": "quick: needs keyscan to verify"})
                continue

            fp = _get_host_key_fingerprint(ip)
            if fp is None:
                candidates.append({"ip": ip, "matched": False, "reason": "keyscan timeout"})
                continue

            if target_fp and fp == target_fp:
                candidates.append({"ip": ip, "matched": True})
                if ip != old_ip:
                    found_ip = ip
                break
            else:
                candidates.append({"ip": ip, "matched": False, "reason": "fingerprint mismatch"})

        if found_ip:
            break

    updated = False
    if found_ip and found_ip != old_ip:
        srv["ip"] = found_ip
        srv["port"] = srv.get("port", 22)
        srv["user"] = srv.get("user", "root")
        d["servers"][name] = srv
        if config_save(d):
            updated = True

    return {
        "server": name,
        "scanned": {"total": total_scanned, "responsive": total_responsive},
        "found": found_ip is not None,
        "old_ip": old_ip,
        "new_ip": found_ip,
        "updated": updated,
        "candidates": candidates,
    }


def cmd_discover_ip(args, json_output=False):
    """子网扫描发现设备新 IP。
    用法: discover-ip <server> [--subnets a.b.c.0/24,...] [--quick]
          discover-ip --all [--subnets ...]"""
    # 解析参数
    target_all = False
    quick_mode = False
    subnets = []
    targets = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--all":
            target_all = True
        elif a == "--quick":
            quick_mode = True
        elif a == "--subnets" and i + 1 < len(args):
            subnets = [s.strip() for s in args[i + 1].split(",") if s.strip()]
            i += 1
        elif not a.startswith("--"):
            targets.append(a)
        i += 1

    if not target_all and not targets:
        if json_output:
            _json_err("用法: discover-ip <server> [--subnets ...] [--quick]")
        else:
            print("用法: discover-ip <server> [--subnets a.b.c.0/24,...] [--quick]", file=sys.stderr)
        sys.exit(1)

    d = config_load()
    servers = d.get("servers", {})

    if target_all:
        target_names = [n for n, s in servers.items() if s.get("pubkey")]
    else:
        target_names = targets

    all_results = []
    for name in target_names:
        if not json_output:
            print(f"扫描 {name} ...")
        r = _discover_single_server(name, quick=quick_mode, subnets=subnets)
        all_results.append(r)

    if json_output:
        if target_all or len(all_results) > 1:
            _json_ok({"results": all_results})
        else:
            _json_ok(all_results[0])
    else:
        for r in all_results:
            if r.get("error"):
                print(f"✗ {r['server']}: {r['error']}")
            elif r["found"]:
                if r["updated"]:
                    print(f"✓ {r['server']}: {r['old_ip']} → {r['new_ip']}（已更新）")
                else:
                    print(f"✓ {r['server']}: 仍在 {r['old_ip']}（无需更新）")
            else:
                print(f"✗ {r['server']}: 未找到（扫描 {r['scanned']['total']} 个 IP，{r['scanned']['responsive']} 个响应）")


# ═══════════════════════════════════════════════════════════
# 命令分发
# ═══════════════════════════════════════════════════════════

USAGE = """Tunnel Mesh v3.0.0 — 分布式 SSH 隧道网状连接工具

用法: python3 tunnel_mesh.py <命令> [参数...]

命令:
  server-list                    列出所有服务器
  server-add <name> <ip> [port] [user] [fingerprint] [pubkey]
  server-remove <name>            删除服务器（级联删关联边）
  server-exists <name>           检查服务器是否存在
  edge-list                      列出所有边
  edge-add <from> <to> <type> [port] [cmd] [maintainer] [fabric_id] [weight]
  edge-remove <id>               删除边
  port-is-free <port>            检查端口是否可用
  port-allocate                  分配下一个可用端口
  viz                            逻辑拓扑图
  tunnel-cmds                    列出所有隧道命令
  tutorial                       生成部署教程
  find-bridge <a_ip> <a_port> <b_ip> <b_port>
  path <from> <to>              查询逻辑路径
  identity                       显示当前节点身份卡
  identity-import [card_text]     导入身份卡（管道传入或参数）
  reachability                   生成网络可达报告
  reachability-merge <r1.json>... 合并多机可达报告
  deploy-guide <r1.json>...       按机器聚合部署指南
  fabric-list                    列出所有 Fabric
  fabric-health [id]              Fabric 健康检查
  fabric-cmds                    列出维持命令
  fabric-viz                      物理拓扑图
  status                          查看所有隧道运行状态
  health                          健康检查所有隧道
  apply [--dry-run|--yes] [--local] [--json]  部署隧道（--local 仅部署本机为 from 的边）
  key-deploy <server> [--key <path>] 部署公钥到目标服务器
  deploy-windows <server>          部署隧道到 Windows（推送脚本 + 注册启动任务）
  upgrade                          从 GitHub 拉取最新版本
  discover [--ports p1,p2,...]     自动探测拓扑，生成边类型建议
  quickstart [--non-interactive] [--yes] 引导式一键配置
  ensure <server|edge|key> ...      幂等操作，可安全重复执行（server 支持 --update-ip）
  service <edge-id|--all> <start|stop|restart|status>  管控隧道 systemd service
  repair [--scan]                 自愈：健康检查 → 重启失败隧道 → 再检查（--scan 自动发现远程节点）
  discover-ip <server> [--subnets ...] [--quick]  子网扫描发现设备新 IP
  scan-watch [--quiet] [--subnets ...]  定时扫描所有 server，IP 变化自动更新（cron 友好）"""


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--help", "-h"):
        print(USAGE)
        sys.exit(0)
    if sys.argv[1] in ("--version", "-v"):
        print("Tunnel Mesh v3.0.0")
        sys.exit(0)

    cmd = sys.argv[1].replace("-", "_")
    raw_args = sys.argv[2:]
    args, json_output, explicit = _parse_json_flag(raw_args)

    # TTY 自动检测：非 TTY 时默认输出 JSON（除非显式 --no-json）
    if not explicit:
        is_tty = sys.stdin.isatty()
        json_output = not is_tty

    # 特殊处理：deploy-guide → deploy_guide
    fn = globals().get(f"cmd_{cmd}")
    if not fn:
        if json_output:
            _json_err(f"未知命令: {sys.argv[1]}")
        else:
            print(f"未知命令: {sys.argv[1]}\n可用: server-list|server-add|server-remove|server-exists|edge-list|edge-add|edge-remove|port-is-free|port-allocate|viz|tunnel-cmds|tutorial|path|identity|identity-import|reachability|reachability-merge|deploy-guide|fabric-list|fabric-health|fabric-cmds|fabric-viz|status|health|apply|key-deploy|deploy-windows|upgrade|discover|discover-ip|scan-watch|quickstart|ensure|service|repair", file=sys.stderr)
        sys.exit(1)
    try:
        fn(args, json_output=json_output)
    except json.JSONDecodeError as e:
        if json_output:
            _json_err(f"JSON 解析失败: {e}")
        else:
            print(f"❌ JSON 解析失败: {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError as e:
        if json_output:
            _json_err(f"文件不存在: {e}")
        else:
            print(f"❌ 文件不存在: {e}", file=sys.stderr)
        sys.exit(1)
    except PermissionError as e:
        if json_output:
            _json_err(f"权限不足: {e}")
        else:
            print(f"❌ 权限不足: {e}", file=sys.stderr)
        sys.exit(1)
    except (OSError, IOError) as e:
        if json_output:
            _json_err(f"文件/网络错误: {e}")
        else:
            print(f"❌ 文件/网络错误: {e}", file=sys.stderr)
        sys.exit(1)
    except ValueError as e:
        if json_output:
            _json_err(f"参数错误: {e}")
        else:
            print(f"❌ 参数错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
