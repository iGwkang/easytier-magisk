if [ "$ARCH" != "arm" ] && [ "$ARCH" != "arm64" ]; then
    abort "本模块仅支持ARM/ARM64设备"
fi

MODULE_ID = easytier-magisk

if [ -f "/data/adb/easytier-magisk/config.yaml" ]; then
    mv /data/adb/easytier-magisk/config.yaml /data/adb/easytier-magisk/config.conf
fi

if [ ! -f "/data/adb/easytier-magisk/config.conf" ]; then
    mkdir -p /data/adb/easytier-magisk
    cp -rf $MODPATH/config/config.conf /data/adb/easytier-magisk/config.conf
fi

set_perm_recursive "$MODPATH/easytier" 0 0 0644 0755
set_perm "$MODPATH/run.sh" 0 0 0755
# set_perm "$MODPATH/action.sh" 0 0 0755
# set_perm "$MODPATH/service.sh" 0 0 0755
# set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print "当前架构为: $ARCH"
ui_print "当前系统版本为: $API"
ui_print "安装目录为: /data/adb/modules/easytier-magisk"
ui_print "配置文件位置: /data/adb/easytier-magisk/config.conf"
ui_print "修改后配置文件后在magisk app点击操作按钮即可生效"
