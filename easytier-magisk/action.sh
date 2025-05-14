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

easytier_pids=$(pgrep -f "$MODDIR/easytier/$ARCH/easytier-core")
echo "easytier_pids: $easytier_pids"
kill -9 $easytier_pids

setsid sh "$MODDIR/run.sh" &
echo "服务已重启"

sleep 3

cat $MODDIR/log/start.log
