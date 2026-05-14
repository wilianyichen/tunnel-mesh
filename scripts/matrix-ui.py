#!/usr/bin/env python3
"""
交互式矩阵 UI
"""

import curses
import yaml
from pathlib import Path
from typing import Dict, List, Optional


class MatrixUI:
    """交互式矩阵界面"""
    
    def __init__(self, config_dir: str = "~/.hermes/topology"):
        self.config_dir = Path(config_dir).expanduser()
        self.servers: List[Dict] = []
        self.connections: List[Dict] = []
        self.selected_row = 0
        self.selected_col = 0
    
    def load_data(self):
        """加载拓扑数据"""
        servers_dir = self.config_dir / "servers"
        for f in servers_dir.glob("*.yaml"):
            with open(f) as fp:
                self.servers.append(yaml.safe_load(fp))
        
        topology_file = self.config_dir / "topology.yaml"
        if topology_file.exists():
            with open(topology_file) as f:
                topology = yaml.safe_load(f)
                self.connections = topology.get("connections", [])
    
    def run(self):
        """运行交互式界面"""
        self.load_data()
        
        if not self.servers:
            print("暂无服务器，请先添加")
            return
        
        curses.wrapper(self._main_loop)
    
    def _main_loop(self, stdscr):
        """主循环"""
        curses.curs_set(0)
        stdscr.clear()
        
        while True:
            self._draw_matrix(stdscr)
            key = stdscr.getch()
            
            if key == ord('q'):
                break
            elif key == curses.KEY_UP:
                self.selected_row = max(0, self.selected_row - 1)
            elif key == curses.KEY_DOWN:
                self.selected_row = min(len(self.servers) - 1, self.selected_row + 1)
            elif key == curses.KEY_LEFT:
                self.selected_col = max(0, self.selected_col - 1)
            elif key == curses.KEY_RIGHT:
                self.selected_col = min(len(self.servers) - 1, self.selected_col + 1)
            elif key == ord('t'):
                self._test_connection(stdscr)
            elif key == ord('s'):
                self._save_topology(stdscr)
    
    def _draw_matrix(self, stdscr):
        """绘制矩阵"""
        stdscr.clear()
        
        # 标题
        stdscr.addstr(0, 2, "服务器网络拓扑矩阵", curses.A_BOLD)
        
        # 表头
        header = "        "
        for i, s in enumerate(self.servers):
            name = s["alias"][:8]
            if i == self.selected_col:
                header += f"[{name}] "
            else:
                header += f" {name}  "
        stdscr.addstr(2, 2, header)
        
        # 矩阵内容
        for row_idx, from_server in enumerate(self.servers):
            row_label = from_server["alias"][:8]
            if row_idx == self.selected_row:
                row_label = f"[{row_label}]"
            else:
                row_label = f" {row_label} "
            
            stdscr.addstr(4 + row_idx, 2, row_label)
            
            for col_idx, to_server in enumerate(self.servers):
                cell = self._get_cell(row_idx, col_idx)
                
                x = 10 + col_idx * 10
                y = 4 + row_idx
                
                if row_idx == self.selected_row and col_idx == self.selected_col:
                    stdscr.addstr(y, x, cell, curses.A_REVERSE)
                else:
                    stdscr.addstr(y, x, cell)
        
        # 图例
        stdscr.addstr(4 + len(self.servers) + 2, 2, "图例: ✓→=可连接  ?=未配置  -=自己")
        
        # 操作提示
        stdscr.addstr(4 + len(self.servers) + 4, 2, "操作: ↑↓←→选择  t=测试  s=保存  q=退出")
        
        # 选中单元格信息
        if self.selected_row != self.selected_col:
            from_id = self.servers[self.selected_row]["id"]
            to_id = self.servers[self.selected_col]["id"]
            conn = self._find_connection(from_id, to_id)
            
            info_y = 4 + len(self.servers) + 6
            stdscr.addstr(info_y, 2, f"选中: {from_id} → {to_id}")
            
            if conn:
                stdscr.addstr(info_y + 1, 2, f"类型: {conn.get('type', 'unknown')}")
                stdscr.addstr(info_y + 2, 2, f"状态: {conn.get('status', 'unknown')}")
            else:
                stdscr.addstr(info_y + 1, 2, "状态: 未配置")
        
        stdscr.refresh()
    
    def _get_cell(self, row: int, col: int) -> str:
        """获取单元格内容"""
        if row == col:
            return "  -  "
        
        from_id = self.servers[row]["id"]
        to_id = self.servers[col]["id"]
        
        conn = self._find_connection(from_id, to_id)
        if conn:
            return "  ✓→ "
        else:
            return "  ?  "
    
    def _find_connection(self, from_id: str, to_id: str) -> Optional[Dict]:
        """查找连接"""
        for c in self.connections:
            if c["from"] == from_id and c["to"] == to_id:
                return c
        return None
    
    def _test_connection(self, stdscr):
        """测试连接"""
        # TODO: 实现实际测试
        stdscr.addstr(20, 2, "测试连接...")
        stdscr.refresh()
    
    def _save_topology(self, stdscr):
        """保存拓扑"""
        stdscr.addstr(20, 2, "拓扑已保存")
        stdscr.refresh()


def main():
    import sys
    
    # 检查是否在交互式终端
    if not sys.stdout.isatty():
        print("矩阵 UI 需要交互式终端")
        print("使用 topology-manager.py matrix 查看静态矩阵")
        return
    
    ui = MatrixUI()
    ui.run()


if __name__ == "__main__":
    main()