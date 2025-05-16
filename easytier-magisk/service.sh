#!/data/adb/magisk/busybox sh

MODDIR=${0%/*}

# wait_until_login from yc9559/uperf at uperf/magisk/script/libcommon.sh
wait_until_login() {
    # in case of /data encryption is disabled
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 1
    done

    # # we doesn't have the permission to rw "/sdcard" before the user unlocks the screen
    # local test_file="/sdcard/Android/.PERMISSION_TEST"
    # true >"$test_file"
    # while [ ! -f "$test_file" ]; do
    #     true >"$test_file"
    #     sleep 1
    # done
    # rm "$test_file"
}

wait_until_login

# 设置路由，让main表生效(easytier添加的规则都在main表里，默认main表不生效)
ip rule add lookup main
ip rule add lookup default

setsid $MODDIR/run.sh &
