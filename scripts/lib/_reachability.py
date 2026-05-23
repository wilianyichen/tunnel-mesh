#!/usr/bin/env python3
"""
可达报告合并引擎 — 合并多机 TCP 探测报告，输出 N×N 矩阵 + 边类型推荐
用法: python3 _reachability.py merge <report1.json> [report2.json ...]
"""
import json
import sys
from collections import defaultdict


def load_report(path):
    with open(path) as f:
        return json.load(f)


def merge_reports(reports):
    """合并多份报告，构建可达矩阵 {(from, to): reachable}"""
    matrix = {}        # (from_name, to_name) -> bool
    nodes = set()      # all node names
    node_ips = {}      # name -> ip
    node_ports = {}    # name -> port

    for r in reports:
        frm = r["from"]
        nodes.add(frm)
        if frm not in node_ips:
            node_ips[frm] = r.get("from_ip", "?")
        for res in r.get("results", []):
            to = res["target"]
            nodes.add(to)
            if to not in node_ips:
                node_ips[to] = res.get("ip", "?")
            if to not in node_ports:
                node_ports[to] = res.get("port", 22)
            matrix[(frm, to)] = res.get("reachable", False)

    return matrix, sorted(nodes), node_ips, node_ports


def recommend_edges(matrix, nodes):
    """根据可达矩阵推荐边类型"""
    edges = []

    for a in nodes:
        for b in nodes:
            if a >= b:
                continue
            a_to_b = matrix.get((a, b), False)
            b_to_a = matrix.get((b, a), False)

            if a_to_b and b_to_a:
                edges.append({"from": a, "to": b, "type": "forward", "reason": f"{a} ⇄ {b} 双向直连"})
                edges.append({"from": b, "to": a, "type": "forward", "reason": f"{b} ⇄ {a} 双向直连"})
            elif a_to_b:
                edges.append({"from": a, "to": b, "type": "forward", "reason": f"{a} → {b} 可达"})
                edges.append({"from": b, "to": a, "type": "reverse",
                              "reason": f"{b} 不可达 {a}。{a} 可主动在 {b} 上开 ssh -R，使 {b} 能经由该端口连接 {a}",
                              "tunnel_runner": a, "tunnel_on": b})
            elif b_to_a:
                edges.append({"from": b, "to": a, "type": "forward", "reason": f"{b} → {a} 可达"})
                edges.append({"from": a, "to": b, "type": "reverse",
                              "reason": f"{a} 不可达 {b}。{b} 可主动在 {a} 上开 ssh -R，使 {a} 能经由该端口连接 {b}",
                              "tunnel_runner": b, "tunnel_on": a})
            else:
                # Neither reachable → 找公共桥节点
                bridge = find_bridge(a, b, matrix, nodes)
                if bridge:
                    edges.append({"from": a, "to": b, "type": "chained",
                                  "reason": f"双方不通，借 {bridge} 链式跳转",
                                  "bridge": bridge})
                    edges.append({"from": b, "to": a, "type": "chained",
                                  "reason": f"双方不通，借 {bridge} 链式跳转",
                                  "bridge": bridge})
                else:
                    edges.append({"from": a, "to": b, "type": "unreachable",
                                  "reason": "无可用路径，需引入新中转节点"})
                    edges.append({"from": b, "to": a, "type": "unreachable",
                                  "reason": "无可用路径，需引入新中转节点"})
    return edges


def find_bridge(a, b, matrix, nodes):
    """找一个公共可达节点作为桥"""
    for c in nodes:
        if c == a or c == b:
            continue
        if matrix.get((a, c), False) and matrix.get((b, c), False):
            return c
        if matrix.get((c, a), False) and matrix.get((c, b), False):
            return c
        # 混合情况：A→C 正向 + B→C 正向（C 可被双方访问）
        a_to_c = matrix.get((a, c), False) or matrix.get((c, a), False)
        b_to_c = matrix.get((b, c), False) or matrix.get((c, b), False)
        if a_to_c and b_to_c:
            return c
    return None


def format_matrix(matrix, nodes, node_ips):
    """格式化 N×N 可达矩阵（ASCII 表格）"""
    # 列宽
    col_w = max(max(len(n) for n in nodes), 8) + 2
    header = "".ljust(col_w) + "".join(n.ljust(col_w) for n in nodes)
    lines = [header, "-" * len(header)]

    for a in nodes:
        row = a.ljust(col_w)
        for b in nodes:
            if a == b:
                row += "-".ljust(col_w)
            else:
                v = matrix.get((a, b), None)
                if v is True:
                    row += "✓".ljust(col_w)
                elif v is False:
                    row += "✗".ljust(col_w)
                else:
                    row += "?".ljust(col_w)
        lines.append(row)
    return "\n".join(lines)


def cmd_deploy_guide():
    """读取多份报告，生成每台机器的部署指令"""
    if len(sys.argv) < 3:
        print("用法: python3 _reachability.py deploy-guide <report1.json> [report2.json ...]", file=sys.stderr)
        sys.exit(1)

    reports = [load_report(p) for p in sys.argv[2:]]
    matrix, node_list, node_ips, node_ports = merge_reports(reports)
    edges = recommend_edges(matrix, node_list)

    # 去重边（按 type+from+to 去重，保留反向隧道信息）
    seen = set()
    unique_edges = []
    for e in edges:
        key = (e["type"], e["from"], e["to"])
        if key not in seen:
            seen.add(key)
            unique_edges.append(e)

    # 每节点汇总任务
    node_tasks = {n: {"add_servers": set(), "run_tunnels": [], "ssh_config": [], "import_cards": set()} for n in node_list}

    for e in unique_edges:
        a, b = e["from"], e["to"]
        etype = e["type"]

        if etype == "forward":
            # 双方都需要把对方加入 servers
            node_tasks[a]["add_servers"].add(b)
            node_tasks[b]["add_servers"].add(a)
            # 两边的 SSH config
            node_tasks[a]["ssh_config"].append({
                "host": b, "hostname": node_ips.get(b, "?"), "port": node_ports.get(b, 22), "direct": True
            })
            node_tasks[b]["ssh_config"].append({
                "host": a, "hostname": node_ips.get(a, "?"), "port": node_ports.get(a, 22), "direct": True
            })

        elif etype == "reverse":
            runner = e.get("tunnel_runner", "")
            tun_on = e.get("tunnel_on", "")
            target = b if runner == a else (a if runner == b else "")

            # 维持者需要运行 ssh -R 命令
            if runner and tun_on:
                port = 2201  # 建议端口，实际由工具分配
                cmd = f"ssh -R <port>:localhost:22 {tun_on}"
                node_tasks[runner]["run_tunnels"].append({
                    "target": target, "tunnel_on": tun_on, "cmd": cmd,
                    "note": f"在 {tun_on} 上打开反向端口，使 {target} 能被 {runner} 连接"
                })

            # 双方需要对方的 ssh config（通过 localhost:port）
            for src, dst in [(a, b), (b, a)]:
                node_tasks[src]["ssh_config"].append({
                    "host": dst, "hostname": "localhost",
                    "port": "<分配端口>", "direct": False
                })

        elif etype == "chained":
            bridge = e.get("bridge", "")
            # 链式：需要经过桥节点
            for n in [a, b]:
                node_tasks[n]["ssh_config"].append({
                    "host": b if n == a else a, "hostname": node_ips.get(bridge, bridge),
                    "port": node_ports.get(bridge, 22),
                    "proxyjump": bridge, "direct": False,
                    "note": f"通过 ProxyJump {bridge} 跳转"
                })

    # 输出每台机器的部署指南
    for node_name in sorted(node_tasks.keys()):
        tasks = node_tasks[node_name]
        print(f"\n{'='*60}")
        print(f"## {node_name} ({node_ips.get(node_name, '?')}:{node_ports.get(node_name, 22)})")
        print(f"{'='*60}")

        if tasks["add_servers"]:
            print("\n### 1. 导入身份卡")
            for s in sorted(tasks["add_servers"]):
                print(f"   将 {s} 的身份卡导入 {node_name}:")
                print(f"     tunnel-mesh.sh --cmd import << 'EOF'")
                print(f"     <粘贴 {s} 的身份卡>")
                print(f"     EOF")

        if tasks["run_tunnels"]:
            print("\n### 2. 维持隧道命令")
            for t in tasks["run_tunnels"]:
                print(f"   目标: {t['target']}")
                print(f"   命令: {t['cmd']}")
                print(f"   说明: {t['note']}")
                print(f"   持久化建议:")
                print(f"     autossh -M 0 -o ServerAliveInterval=30 {t['cmd']}")
                print()

        if tasks["ssh_config"]:
            print("\n### 3. SSH Config 条目")
            for c in tasks["ssh_config"]:
                note = c.get("note", "")
                if note:
                    print(f"   # {note}")
                if c.get("direct"):
                    print(f"   Host {c['host']}")
                    print(f"       HostName {c['hostname']}")
                    print(f"       Port {c['port']}")
                else:
                    print(f"   Host {c['host']}")
                    print(f"       HostName {c['hostname']}")
                    print(f"       Port {c['port']}")
                    if "proxyjump" in c:
                        print(f"       ProxyJump {c['proxyjump']}")
                print()

    # 汇总（所有机器共用一个脚本）
    print(f"\n{'='*60}")
    print("## 汇总：全局部署步骤")
    print(f"{'='*60}")
    print("""
1. 每台机器运行 tunnel-mesh.sh --cmd reachability > <name>.json
2. 收集所有 JSON 到一台机器
3. 运行 tunnel-mesh.sh --cmd reachability-merge *.json
4. 将输出保存为 merged.json
5. 运行本部署指南: cat merged.json | python3 _reachability.py deploy-guide
6. 按各机器指南逐台执行
""")

    # 输出 JSON 供程序消费
    result = {
        "node_tasks": {
            n: {
                "add_servers": sorted(list(t["add_servers"])),
                "run_tunnels": t["run_tunnels"],
                "ssh_config": t["ssh_config"],
            }
            for n, t in node_tasks.items()
        }
    }
    print("\n---\n")
    print(json.dumps(result, indent=2, ensure_ascii=False))


def cmd_merge():
    if len(sys.argv) < 3:
        print("用法: python3 _reachability.py merge <report1.json> [report2.json ...]", file=sys.stderr)
        sys.exit(1)

    reports = [load_report(p) for p in sys.argv[2:]]
    matrix, nodes, node_ips, node_ports = merge_reports(reports)
    edges = recommend_edges(matrix, nodes)

    # 输出
    print("# 网络可达矩阵\n")
    print("```")
    print(format_matrix(matrix, nodes, node_ips))
    print("```\n")

    print("## 节点信息\n")
    for n in nodes:
        print(f"- **{n}**: {node_ips.get(n, '?')}:{node_ports.get(n, 22)}")

    print("\n## 推荐边\n")
    forward_edges = [e for e in edges if e["type"] == "forward"]
    reverse_edges = [e for e in edges if e["type"] == "reverse"]
    chained_edges = [e for e in edges if e["type"] == "chained"]
    unreachable = [e for e in edges if e["type"] == "unreachable"]

    if forward_edges:
        print("### 正向直连")
        for e in forward_edges:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")

    if reverse_edges:
        print("\n### 反向隧道")
        for e in reverse_edges:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")
            print(f"  - 维持者: **{e['tunnel_runner']}** 运行 `ssh -R <port>:localhost:22 {e['tunnel_on']}`")

    if chained_edges:
        print("\n### 链式跳转（借桥）")
        for e in chained_edges:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")

    if unreachable:
        print("\n### 不可达")
        for e in unreachable:
            print(f"- **{e['from']} → {e['to']}**: {e['reason']}")

    # 输出 JSON 供程序消费
    print("\n---\n")
    result = {
        "nodes": {n: {"ip": node_ips.get(n, "?"), "port": node_ports.get(n, 22)} for n in nodes},
        "matrix": {f"{a}->{b}": matrix.get((a, b)) for a in nodes for b in nodes if a != b},
        "edges": edges,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: _reachability.py merge|deploy-guide <report...>", file=sys.stderr)
        sys.exit(1)
    cmd = sys.argv[1].replace("-", "_")
    fn = globals().get(f"cmd_{cmd}")
    if not fn:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
    fn()
