#!/bin/bash
# log.sh - 隧道日志查看
do_logs() {
    LOG_DIR="$HOME/.tunnel-mesh/logs"
    echo ""; echo "════════════════════════════════════════"; echo "  隧道日志"; echo "════════════════════════════════════════"
    if [ ! -d "$LOG_DIR" ] || [ -z "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
        echo ""; echo "暂无日志。隧道日志在 Windows 维持者上。"; echo "Windows: C:\\tunnel-mesh\\logs\\"; return
    fi
    echo ""; ls -lt "$LOG_DIR" | head -5
    read -p "查看哪个日志（回车跳过）: " F; [ -z "$F" ] && return
    [ -f "$LOG_DIR/$F" ] && tail -30 "$LOG_DIR/$F" || echo "未找到"
}
