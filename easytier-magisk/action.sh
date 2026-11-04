#!/data/adb/magisk/busybox sh
# Magisk 模块“操作”按钮：重启 EasyTier 并显示运行状态。

MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_module_conf

ARCH=$(resolve_arch)
BIN_DIR="$MODDIR/easytier/$ARCH"

if [ -f "$MODDIR/disable" ]; then
    echo "模块已被 Magisk 禁用，请先在 Magisk 中启用模块。"
    exit 0
fi

if [ ! -x "$BIN_DIR/easytier-core" ]; then
    echo "当前架构 $ARCH 没有可用二进制（仅支持 arm / arm64 / x64）。"
    exit 0
fi

echo "正在重启 EasyTier（架构: $ARCH）..."
ensure_tun
ensure_ip_rule

_old_core=$(running_core_pid)
_sup=$(pid_from_file "$SUPERVISOR_PID_FILE")
if pid_is_supervisor "$_sup"; then
    kill -USR1 "$_sup" 2>/dev/null
else
    setsid "$MODDIR/run.sh" >> "$LOG_DIR/module.log" 2>&1 &
fi

# 等待旧核心退出、新核心启动，而不是只看到任意一个运行中的核心。
_i=0
while [ "$_i" -lt 10 ]; do
    sleep 1
    _core=$(running_core_pid)
    if [ -n "$_core" ] && [ "$_core" != "$_old_core" ]; then
        break
    fi
    _i=$((_i + 1))
done

_core=$(running_core_pid)
echo "----------------------------------------"
if pid_is_easytier "$_core"; then
    echo "状态: 运行中 (pid $_core)"
else
    echo "状态: 未运行"
fi
if command_args_present; then
    echo "模式: 启动参数（$COMMAND_ARGS_FILE）"
elif [ "$WEB_MANAGE_LOCAL" = "1" ]; then
    echo "模式: Web 托管（$WEB_CONFIG_PROTOCOL://127.0.0.1:$WEB_CONFIG_PORT）"
else
    echo "模式: 配置文件（$CONFIG_FILE）"
fi
[ "$WEB_ENABLE" = "1" ] && echo "Web: http://$WEB_ADDR:$WEB_PORT"
[ "$HOTSPOT_NAT" = "1" ] && echo "热点 NAT 转发: 已启用"
echo "日志: $LOG_DIR"
echo "----------------------------------------"

if pid_is_easytier "$_core"; then
    timeout 6 "$BIN_DIR/easytier-cli" -p "$RPC_PORTAL" peer 2>&1 | head -n 16
    echo "----------------------------------------"
fi

echo "最近日志:"
tail -n 12 "$LOG_DIR/core.console.log" 2>/dev/null
