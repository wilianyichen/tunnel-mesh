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
# 命令实现
# ═══════════════════════════════════════════════════════════

def cmd_server_list(args):
    d = config_load()
    for s in d.get("servers", {}).values():
        extra = ""
        if s.get("fingerprint"):
            extra += f"  fp:{s['fingerprint'][:16]}..."
        print(f"  {s['name']:<15} {s.get('ip','?')}:{s.get('port',22)}{extra}")


def cmd_server_add(args):
    if len(args) < 2:
        print("用法: tunnel_mesh.py server-add <name> <ip> [port] [user]", file=sys.stderr)
        sys.exit(1)
    d = config_load()
    name, ip = args[0], args[1]
    port = int(args[2]) if len(args) > 2 and args[2].isdigit() else 22
    user = args[3] if len(args) > 3 else "root"
    d.setdefault("servers", {})[name] = {
        "name": name, "ip": ip, "port": port, "user": user,
        "fingerprint": "", "pubkey": "", "added": _now_iso(),
    }
    config_save(d)
    print(f"✓ 已添加服务器: {name} ({ip}:{port})")


def cmd_server_exists(args):
    d = config_load()
    name = args[0] if args else ""
    print(name in d.get("servers", {}))


def cmd_edge_list(args):
    d = config_load()
    for e in d.get("edges", []):
        port_str = f" 端口:{e['tunnel_port']}" if e.get("tunnel_port") else ""
        print(f"  {e['id']:<25} {e.get('type','?'):<10} {port_str}")


def cmd_edge_add(args):
    if len(args) < 3:
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
    print(f"✓ 已添加边: {eid} ({etype})")


def cmd_edge_remove(args):
    if len(args) < 1:
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
    print(f"✓ 已删除边: {eid}")


def cmd_port_is_free(args):
    d = config_load()
    port = int(args[0]) if args else 0
    used = d.get("ports", {}).get("used", [])
    print(port not in used)


def cmd_port_allocate(args):
    d = config_load()
    ports = d.setdefault("ports", {})
    used = ports.setdefault("used", [])
    nxt = ports.setdefault("next", 2201)
    while nxt in used:
        nxt += 1
    used.append(nxt)
    ports["next"] = nxt + 1
    config_save(d)
    print(nxt)


def cmd_viz(args):
    d = config_load()
    servers = d.get("servers", {})
    edges = d.get("edges", [])
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


def cmd_tunnel_cmds(args):
    d = config_load()
    for e in d.get("edges", []):
        if e.get("tunnel_cmd"):
            print(e["tunnel_cmd"])
            print()


def cmd_tutorial(args):
    d = config_load()
    hostname = os.environ.get("HOSTNAME", os.uname().nodename if hasattr(os, "uname") else "localhost")
    print("# Tunnel Mesh 教程\n")
    print("生成时间:", _now_iso())
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


def cmd_find_bridge(args):
    if len(args) < 4:
        print("用法: tunnel_mesh.py find-bridge <a_ip> <a_port> <b_ip> <b_port>", file=sys.stderr)
        sys.exit(1)
    d = config_load()
    candidates = []
    for name, s in d.get("servers", {}).items():
        candidates.append(f"{name} {s.get('ip','?')} {s.get('port',22)}")
    print("\n".join(candidates))


def cmd_identity(args=None):
    hostname = os.environ.get("HOSTNAME", "")
    if not hostname and hasattr(os, "uname"):
        hostname = os.uname().nodename
    print(hostname or "unknown")


# ═══════════════════════════════════════════════════════════
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


def cmd_status(args):
    d = config_load()
    edges = d.get("edges", [])
    if not edges:
        print("(无配置的隧道)")
        return
    print(f"{'边ID':<30} {'类型':<12} {'端口':<8} {'状态':<10} {'备注'}")
    print("-" * 80)
    for e in edges:
        eid = e.get("id", "?")
        etype = e.get("type", "?")
        port = e.get("tunnel_port", 0)
        port_str = str(port) if port else "-"
        status = "未知"
        note = ""
        if etype == "reverse" and port > 0:
            if _check_port_local(port):
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
        print(f"  {eid:<28} {etype:<12} {port_str:<8} {status:<10} {note}")


def cmd_health(args):
    d = config_load()
    edges = d.get("edges", [])
    if not edges:
        print("(无配置的隧道)")
        return

    import socket as _sock
    passed, failed, total = 0, 0, 0

    for e in edges:
        eid = e.get("id", "?")
        etype = e.get("type", "?")
        port = e.get("tunnel_port", 0)

        if etype == "forward":
            # 正向：直接尝试 TCP 连接目标
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
            total += 1
            if ok:
                passed += 1
                print(f"  ✅ {eid}: {ip}:{target_port} 可达")
            else:
                failed += 1
                print(f"  ❌ {eid}: {ip}:{target_port} 不可达")
        elif etype == "reverse" and port > 0:
            # 反向隧道：检查本地端口
            total += 1
            if _check_port_local(port):
                passed += 1
                print(f"  ✅ {eid}: localhost:{port} 隧道存活")
            else:
                failed += 1
                print(f"  ❌ {eid}: localhost:{port} 隧道断开")
        elif etype in ("chained", "proxyjump"):
            # 链式/跳板：简单跳过（不做复杂检查）
            print(f"  ⏭  {eid}: {etype}（跳过自动检测）")

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


def _generate_systemd_service(name, cmd):
    """生成 systemd user service 内容"""
    return f"""[Unit]
Description=Tunnel Mesh: {name}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart={cmd}
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
"""


def cmd_apply(args):
    """部署隧道：检测冲突、写入 SSH config、生成 systemd service"""
    dry_run = True
    yes_mode = False
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
        else:
            remaining.append(args[i])
            i += 1

    d = config_load()
    edges = d.get("edges", [])
    hosts = set()
    plans = []

    for e in edges:
        eid = e.get("id", "?")
        etype = e.get("type", "?")
        port = e.get("tunnel_port", 0)
        target = e.get("to", "")
        cmd = e.get("tunnel_cmd", "")

        if etype == "reverse" and port > 0:
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
                service_name = f"tunnel-mesh-{target}.service"
                service_content = _generate_systemd_service(target, cmd)
                plan["actions"].append({"type": "systemd_service", "name": service_name, "content": service_content})
                plan["actions"].append({"type": "enable_service", "name": service_name, "cmd": f"systemctl --user enable --now {service_name}"})

            plans.append(plan)

        elif etype == "forward":
            target = e.get("to", "")
            srv = d.get("servers", {}).get(target, {})
            ip = srv.get("ip", "?")
            target_port = srv.get("port", 22)
            user = srv.get("user", "root")
            if ip and ip != "?":
                plan = {"id": eid, "type": etype, "port": target_port, "target": target, "actions": [], "warnings": [], "errors": []}
                hosts.add(target)
                ssh_conflicts = _check_ssh_config_conflicts(target)
                if ssh_conflicts:
                    for c in ssh_conflicts:
                        plan["warnings"].append(f"SSH config 冲突: {c}")
                ssh_entry = f"Host {target}\n    HostName {ip}\n    Port {target_port}\n    User {user}"
                plan["actions"].append({"type": "ssh_config", "host": target, "content": ssh_entry})
                plans.append(plan)

    # 输出
    header = "🔍 预览模式 (--dry-run)" if dry_run else "🚀 执行模式"
    print(f"{header}\n")
    if not plans:
        print("(无需要部署的隧道)")
        return

    total_actions = 0
    warnings_count = 0

    for plan in plans:
        print(f"  [{plan['type'].upper()}] {plan['id']}")
        if plan["warnings"]:
            for w in plan["warnings"]:
                print(f"    ⚠ {w}")
                warnings_count += 1
        for a in plan["actions"]:
            total_actions += 1
            if a["type"] == "ssh_config":
                print(f"    📝 SSH config: ~/.ssh/config")
                print(f"       {a['content'].replace(chr(10), chr(10)+'       ')}")
            elif a["type"] == "systemd_service":
                print(f"    📝 systemd: ~/.config/systemd/user/{a['name']}")
            elif a["type"] == "enable_service":
                print(f"    ▶ {a['cmd']}")
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
    ssh_config_path = os.path.expanduser("~/.ssh/config")
    systemd_user_dir = os.path.expanduser("~/.config/systemd/user")
    os.makedirs(systemd_user_dir, exist_ok=True)
    os.makedirs(os.path.dirname(ssh_config_path), exist_ok=True)

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
                with open(svc_path, "w") as f:
                    f.write(a["content"])
                print(f"  ✓ 写入 {svc_path}")
            elif a["type"] == "enable_service":
                import subprocess as _sp
                try:
                    _sp.run(a["cmd"].split(), check=False)
                    print(f"  ✓ {a['cmd']}")
                except Exception as e:
                    print(f"  ❌ {e}")

    if ssh_entries:
        # 去重 SSH config 条目
        existing = set()
        if os.path.isfile(ssh_config_path):
            with open(ssh_config_path) as f:
                for line in f:
                    existing.add(line.strip())
        with open(ssh_config_path, "a") as f:
            for entry in ssh_entries:
                # 简单去重：检查 Host 行是否已存在
                host_line = entry.split("\n")[0].strip()
                if host_line not in [l.strip() for l in existing]:
                    f.write("\n" + entry + "\n")
                    print(f"  ✓ 添加 SSH config: {host_line}")

    print("\n✓ 部署完成")


def _confirm(prompt):
    """简单确认提示"""
    try:
        return input(prompt).strip().lower() in ("y", "yes")
    except (EOFError, KeyboardInterrupt):
        return False


# ═══════════════════════════════════════════════════════════
# Fabric 命令
# ═══════════════════════════════════════════════════════════

def cmd_fabric_list(args):
    d = config_load()
    fabrics = d.get("fabrics", {})
    if not fabrics:
        print("  (无 Fabric)")
        return
    for fid, fab in fabrics.items():
        print(f"  {fid:<20} {fab.get('logical_edge','?'):<25} 端口:{fab.get('port','?')} 状态:{fab.get('status','?')}")


def cmd_fabric_health(args):
    fid = args[0] if args else ""
    d = config_load()
    fabrics = d.get("fabrics", {})
    if fid:
        fab = fabrics.get(fid, {})
        print(json.dumps({"id": fid, "status": fab.get("status", "unknown"), "hops": len(fab.get("hops", []))}, indent=2))
    else:
        result = {}
        for fid, fab in fabrics.items():
            result[fid] = {"status": fab.get("status", "unknown"), "hops": len(fab.get("hops", []))}
        print(json.dumps(result, indent=2))


def cmd_fabric_cmds(args):
    d = config_load()
    for e in d.get("edges", []):
        if e.get("tunnel_cmd"):
            print(e["tunnel_cmd"])
            print()


def cmd_fabric_viz(args):
    d = config_load()
    fabrics = d.get("fabrics", {})
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

def cmd_reachability(args):
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
        results.append({
            "target": name, "ip": ip,
            "default_port": s.get("port", 22),
            "ports": sorted_ports,
        })

    report = {
        "from": hostname, "from_ip": from_ip,
        "timestamp": _now_iso(),
        "probed_ports": ports_to_probe,
        "results": results,
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))


def cmd_reachability_merge(args):
    import subprocess
    lib_dir = os.path.join(_SCRIPT_DIR, "lib")
    subprocess.run([sys.executable, os.path.join(lib_dir, "_reachability.py"), "merge"] + args)


def cmd_deploy_guide(args):
    import subprocess
    lib_dir = os.path.join(_SCRIPT_DIR, "lib")
    subprocess.run([sys.executable, os.path.join(lib_dir, "_reachability.py"), "deploy-guide"] + args)


def cmd_path(args):
    if len(args) < 2:
        print("用法: tunnel_mesh.py path <from> <to>", file=sys.stderr)
        sys.exit(1)
    import subprocess
    subprocess.run([sys.executable, os.path.join(_SCRIPT_DIR, "graph.py"), "--json"] + args)


# ═══════════════════════════════════════════════════════════
# 命令分发
# ═══════════════════════════════════════════════════════════

USAGE = """Tunnel Mesh v3.0.0 — 分布式 SSH 隧道网状连接工具

用法: python3 tunnel_mesh.py <命令> [参数...]

命令:
  server-list                    列出所有服务器
  server-add <name> <ip> [port] [user]
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
  identity                       显示当前节点名
  reachability                   生成网络可达报告
  reachability-merge <r1.json>... 合并多机可达报告
  deploy-guide <r1.json>...       按机器聚合部署指南
  fabric-list                    列出所有 Fabric
  fabric-health [id]              Fabric 健康检查
  fabric-cmds                    列出维持命令
  fabric-viz                      物理拓扑图
  status                          查看所有隧道运行状态
  health                          健康检查所有隧道
  apply [--dry-run|--yes]         部署隧道（冲突检测 + systemd 持久化）"""


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--help", "-h"):
        print(USAGE)
        sys.exit(0)
    if sys.argv[1] in ("--version", "-v"):
        print("Tunnel Mesh v3.0.0")
        sys.exit(0)

    cmd = sys.argv[1].replace("-", "_")
    args = sys.argv[2:]

    # 特殊处理：deploy-guide → deploy_guide
    fn = globals().get(f"cmd_{cmd}")
    if not fn:
        print(f"未知命令: {sys.argv[1]}\n可用: server-list|server-add|edge-list|edge-add|edge-remove|port-is-free|port-allocate|viz|tunnel-cmds|tutorial|path|identity|reachability|reachability-merge|deploy-guide|fabric-list|fabric-health|fabric-cmds|fabric-viz", file=sys.stderr)
        sys.exit(1)
    fn(args)


if __name__ == "__main__":
    main()
