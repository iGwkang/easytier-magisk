#!/data/adb/magisk/busybox sh

MODDIR=${0%/*}

# 从系统属性获取 CPU ABI
ARCH=$(getprop ro.product.cpu.abi)

case "$ARCH" in
    armeabi-v7a) ARCH="arm" ;;
    arm64-v8a)   ARCH="arm64" ;;
    x86)         ARCH="x86" ;;
    x86_64)      ARCH="x64" ;;
    *)           ARCH="unknown" ;;
esac


mkdir -p $MODDIR/log

check_disable() {

    while [ ! -f $MODDIR/disable ]; do
        sleep 2
    done

    PIDS=$(pgrep -f "$MODDIR/easytier/$ARCH/easytier-core")
    kill -9 $PIDS
    echo "Easytier $PIDS 服务停止" >> $MODDIR/log/start.log
}

check_disable &
check_disable_pid=$!

$MODDIR/easytier/$ARCH/easytier-core -c /data/adb/easytier-magisk/config.yaml > $MODDIR/log/start.log 2>&1
kill $check_disable_pid
