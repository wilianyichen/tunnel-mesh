#!/usr/bin/env bash
# 共享辅助函数 — 所有 bats 测试的文件系统环境

setup_config_env() {
    TEST_TMPDIR=$(mktemp -d)
    export CONFIG_DIR="$TEST_TMPDIR"
    export CONFIG_FILE="$TEST_TMPDIR/config.json"
    export LIB_DIR="$(cd "$BATS_TEST_DIRNAME/../scripts/lib" && pwd)"
    export TPY=python3
    export TPY_ENTRY="$BATS_TEST_DIRNAME/../scripts/tunnel_mesh.py"
}

teardown_config_env() {
    rm -rf "$TEST_TMPDIR"
}
