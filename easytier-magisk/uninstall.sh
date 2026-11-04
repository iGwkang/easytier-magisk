#!/data/adb/magisk/busybox sh
# 卸载：先停进程、清理 NAT 与策略路由，再删除持久化数据目录。

MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_module_conf

stop_pidfile_any "$SUPERVISOR_PID_FILE" run.sh
stop_pidfile "$CORE_PID_FILE"
stop_pidfile "$WEB_PID_FILE"
stop_pidfile_any "$HOTSPOT_PID_FILE" hotspot_nat.sh
# pid 文件可能已被新实例覆盖或缺失，兜底按进程特征再停一次。
stop_pid_checked "$(running_core_pid)" easytier-core
stop_pid_checked "$(running_web_pid)" easytier-web
"$MODDIR/hotspot_nat.sh" del >/dev/null 2>&1
remove_ip_rule

rm -rf /data/adb/easytier-magisk
