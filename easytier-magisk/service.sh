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

setsid $MODDIR/run.sh &
