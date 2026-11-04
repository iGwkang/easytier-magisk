#!/data/adb/magisk/busybox sh
# Magisk 安装脚本：校验架构、初始化数据目录与默认配置。

DATA_DIR=/data/adb/easytier-magisk

case "$ARCH" in
    x86_64) ARCH=x64 ;;
esac

case "$ARCH" in
    arm|arm64|x64) ;;
    *)
        abort "不支持的架构: $ARCH（仅支持 arm / arm64 / x64）"
        ;;
esac

if [ ! -x "$MODPATH/easytier/$ARCH/easytier-core" ]; then
    abort "模块包缺少 $ARCH 二进制: easytier/$ARCH/easytier-core"
fi

# 只保留当前设备架构，减少 /data 占用。
for arch_dir in arm arm64 x64; do
    [ "$arch_dir" = "$ARCH" ] || rm -rf "$MODPATH/easytier/$arch_dir"
done

mkdir -p "$DATA_DIR"

# 兼容旧版 yaml 配置文件。
if [ -f "$DATA_DIR/config.yaml" ] && [ ! -f "$DATA_DIR/config.toml" ]; then
    mv "$DATA_DIR/config.yaml" "$DATA_DIR/config.toml"
fi

[ -f "$DATA_DIR/config.toml" ] || cp -f "$MODPATH/config/config.toml" "$DATA_DIR/config.toml"
[ -f "$DATA_DIR/module.conf" ] || cp -f "$MODPATH/config/module.conf" "$DATA_DIR/module.conf"
[ -f "$DATA_DIR/command_args.sample" ] || cp -f "$MODPATH/config/command_args.sample" "$DATA_DIR/command_args.sample"

set_perm_recursive "$MODPATH/easytier" 0 0 0755 0755
set_perm "$MODPATH/run.sh" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/hotspot_nat.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$DATA_DIR/config.toml" 0 0 0600
set_perm "$DATA_DIR/module.conf" 0 0 0600

ui_print "当前架构: $ARCH"
ui_print "系统版本: $API"
ui_print "安装目录: /data/adb/modules/easytier-magisk"
ui_print "配置文件: $DATA_DIR/config.toml"
ui_print "运行配置: $DATA_DIR/module.conf"
ui_print "日志目录: $DATA_DIR/log"
ui_print "----------------------------------------"
ui_print "默认 config.toml 只有组网身份，未设置虚拟 IP："
ui_print "  请填写 ipv4 或把 dhcp 改为 true，否则只做转发、不创建 TUN"
ui_print "Web 管理界面默认关闭且只监听 127.0.0.1；局域网访问需改 WEB_ADDR"
ui_print "自定义启动参数：把 $DATA_DIR/command_args.sample 重命名为"
ui_print "  command_args 并写入 easytier-core 官方参数（如 --config-server）"
ui_print "热点共享 NAT 默认关闭，可在 module.conf 中设置 HOTSPOT_NAT=1"
ui_print "修改配置后点击 Magisk 模块的“操作”按钮即可重启生效"
