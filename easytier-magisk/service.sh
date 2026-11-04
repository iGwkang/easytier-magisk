#!/data/adb/magisk/busybox sh
# Magisk late_start service：等待开机完成后拉起守护脚本。

MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_module_conf

while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done

# 部分机型需要补 /dev/net/tun；main 表需要策略路由规则才能生效。
ensure_tun
ensure_ip_rule
mkdir -p "$LOG_DIR" 2>/dev/null

if pid_is_supervisor "$(pid_from_file "$SUPERVISOR_PID_FILE")"; then
    log_line "service: supervisor 已在运行"
    exit 0
fi

log_line "service: starting supervisor"
setsid "$MODDIR/run.sh" >> "$LOG_DIR/module.log" 2>&1 &
