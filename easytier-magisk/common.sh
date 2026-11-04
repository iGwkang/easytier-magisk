#!/data/adb/magisk/busybox sh
# 公共运行库，由 run.sh / service.sh / action.sh / hotspot_nat.sh 引用。

MODDIR=${MODDIR:-${0%/*}}
DATA_DIR=${ET_DATA_DIR:-/data/adb/easytier-magisk}
MODULE_CONF="$DATA_DIR/module.conf"
COMMAND_ARGS_FILE="$DATA_DIR/command_args"
CORE_PID_FILE="$DATA_DIR/core.pid"
WEB_PID_FILE="$DATA_DIR/web.pid"
SUPERVISOR_PID_FILE="$DATA_DIR/supervisor.pid"
HOTSPOT_PID_FILE="$DATA_DIR/hotspot.pid"

# 读取 module.conf，未配置项使用默认值。
# module.conf 是普通 shell 文件，只在设备本地生效，升级模块不会被覆盖。
load_module_conf() {
    [ -f "$MODULE_CONF" ] && . "$MODULE_CONF"

    : "${CONFIG_FILE:=$DATA_DIR/config.toml}"
    : "${LOG_DIR:=$DATA_DIR/log}"
    : "${WEB_ENABLE:=0}"
    : "${WEB_ADDR:=127.0.0.1}"
    : "${WEB_PORT:=11211}"
    : "${WEB_CONFIG_PORT:=22020}"
    : "${WEB_CONFIG_PROTOCOL:=udp}"
    : "${WEB_DB:=$DATA_DIR/web/et.db}"
    : "${WEB_ARGS:=}"
    : "${WEB_MANAGE_LOCAL:=0}"
    : "${WEB_MANAGE_TOKEN:=}"
    : "${CUSTOM_HOSTNAME:=}"
    : "${RPC_PORTAL:=127.0.0.1:15888}"
    : "${EASYTIER_LOG_LEVEL:=info}"
    : "${EASYTIER_CONSOLE_LEVEL:=warn}"
    : "${EASYTIER_LOG_SIZE_MB:=10}"
    : "${EASYTIER_LOG_COUNT:=3}"
    : "${LOG_MAX_KB:=1024}"
    : "${HOTSPOT_NAT:=0}"
}

# 输出当前设备应使用的二进制目录名：arm / arm64 / x64。
resolve_arch() {
    _abi=$(getprop ro.product.cpu.abi 2>/dev/null)
    case "$_abi" in
        armeabi-v7a) echo arm ;;
        arm64-v8a) echo arm64 ;;
        x86_64) echo x64 ;;
        x86) echo x86 ;;
        *)
            case "${ARCH:-}" in
                arm|arm64|x64) echo "$ARCH" ;;
                *) echo unknown ;;
            esac
            ;;
    esac
}

log_line() {
    mkdir -p "$LOG_DIR" 2>/dev/null
    rotate_log "$LOG_DIR/module.log"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_DIR/module.log"
}

# 日志超过 LOG_MAX_KB 时保留一份 .1，避免无限增长。
rotate_log() {
    [ -f "$1" ] || return 0
    _size=$(wc -c < "$1" 2>/dev/null || echo 0)
    if [ "$_size" -gt $(( ${2:-$LOG_MAX_KB} * 1024 )) ] 2>/dev/null; then
        mv -f "$1" "$1.1"
    fi
}

# 把状态写进 module.prop 的 description，Magisk 模块列表可见。
set_status() {
    _prop="$MODDIR/module.prop"
    [ -f "$_prop" ] || return 0
    _line=$(sed -n 's/^description=//p' "$_prop" | head -n1)
    case "$_line" in
        *" | 状态: "*)
            [ "${_line##* | 状态: }" = "$*" ] && return 0
            ;;
    esac
    _base=$(printf '%s' "$_line" | sed 's/ | 状态: .*$//')
    _text=$(printf '%s' "$*" | sed 's/[&@\\]/\\&/g')
    sed -i "s@^description=.*@description=${_base} | 状态: ${_text}@" "$_prop" 2>/dev/null
}

# Android 上部分机型只有 /dev/tun，需要补 /dev/net/tun。
ensure_tun() {
    if [ ! -e /dev/net/tun ] && [ -e /dev/tun ]; then
        mkdir -p /dev/net 2>/dev/null
        ln -s /dev/tun /dev/net/tun 2>/dev/null
    fi
}

# Android 启动时会 flush 内核默认的 "32766: from all lookup main"，
# 并在 32000 显式插入 unreachable 规则；EasyTier 的路由写在 main 表，
# 因此 main 查询规则必须插在 32000 之前，否则虚拟网段永远不可达。
ET_RULE_PREF=30000

# $1 为空（IPv4）或 -6（IPv6）；已存在同优先级规则时返回 0。
ip_rule_present() {
    ip $1 rule show 2>/dev/null | awk -v p="$ET_RULE_PREF" '
        { sub(/^[[:space:]]*/, "") }
        $0 ~ "^" p ":[[:space:]]+from all lookup main$" { found = 1 }
        END { exit !found }
    '
}

ensure_ip_rule() {
    if ! ip_rule_present ""; then
        ip rule add pref "$ET_RULE_PREF" from all lookup main 2>/dev/null
    fi
    if ! ip_rule_present "-6"; then
        ip -6 rule add pref "$ET_RULE_PREF" from all lookup main 2>/dev/null
    fi
}

remove_ip_rule() {
    ip rule del pref "$ET_RULE_PREF" from all lookup main 2>/dev/null
    ip -6 rule del pref "$ET_RULE_PREF" from all lookup main 2>/dev/null
}

# 自动主机名：品牌-型号，只保留 ASCII 安全字符。
auto_hostname() {
    _brand=$(getprop ro.product.brand 2>/dev/null)
    _model=$(getprop ro.product.model 2>/dev/null)
    _name=$(printf '%s-%s' "$_brand" "$_model" | tr -s ' ' '-' | tr -cd 'A-Za-z0-9._-')
    _name=${_name#-}
    _name=${_name%-}
    [ -n "$_name" ] || _name=android
    printf '%s' "$_name" | cut -c1-32
}

pid_alive() {
    [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

# 校验 pid 存活且 cmdline 包含指定片段，避免 pid 复用误杀/误判。
pid_cmdline_contains() {
    pid_alive "$1" || return 1
    case "$(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null)" in
        *"$2"*) return 0 ;;
        *) return 1 ;;
    esac
}

# 校验 pid 存活且确实是 easytier 进程，避免 pid 复用误判。
pid_is_easytier() {
    pid_alive "$1" || return 1
    case "$(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null)" in
        *easytier-core*|*easytier-web-embed*|*easytier-web*) return 0 ;;
        *) return 1 ;;
    esac
}

pid_is_supervisor() {
    pid_cmdline_contains "$1" run.sh
}

pid_is_hotspot() {
    pid_cmdline_contains "$1" hotspot_nat.sh
}

pid_from_file() {
    [ -f "$1" ] && cat "$1" 2>/dev/null
}

remove_pidfile_if_pid() {
    if [ "$(pid_from_file "$1")" = "$2" ]; then
        rm -f "$1"
    fi
}

# 终止本进程自己记录的 pid（不依赖可能已被新实例覆盖的 pid 文件）。
stop_pid_checked() {
    _pid=$1
    _pattern=$2
    pid_cmdline_contains "$_pid" "$_pattern" || return 0
    kill -TERM "$_pid" 2>/dev/null
    _i=0
    while pid_alive "$_pid" && [ "$_i" -lt 10 ]; do
        sleep 1
        _i=$((_i + 1))
    done
    pid_alive "$_pid" && kill -KILL "$_pid" 2>/dev/null
}

# 终止 pid 文件记录的进程；先 TERM，最多等 10 秒再 KILL。
# 仅在 pid 文件仍记录该进程时才删除文件，避免误删新实例写入的 pid。
stop_pidfile() {
    _pid=$(pid_from_file "$1")
    if pid_is_easytier "$_pid"; then
        stop_pid_checked "$_pid" easytier
    fi
    remove_pidfile_if_pid "$1" "$_pid"
}

# 不校验进程名的终止逻辑，用于 hotspot_nat.sh 等模块内辅助进程。
# $2 为必须出现在 cmdline 中的片段，防止误杀复用的 pid。
stop_pidfile_any() {
    _pid=$(pid_from_file "$1")
    if pid_cmdline_contains "$_pid" "$2"; then
        stop_pid_checked "$_pid" "$2"
    fi
    remove_pidfile_if_pid "$1" "$_pid"
}

# 在参数列表里精确查找选项，避免值里包含选项名时误判。
args_contain_any() {
    _need=$1
    shift
    for _arg in "$@"; do
        case "$_arg" in
            "$_need"|"$_need"=*) return 0 ;;
        esac
    done
    return 1
}

# command_args 中是否有有效内容（忽略空行与 # 注释行）。
command_args_present() {
    [ -s "$COMMAND_ARGS_FILE" ] || return 1
    awk 'BEGIN { found = 1 } !/^[[:space:]]*#/ && NF { found = 0 } END { exit found }' "$COMMAND_ARGS_FILE"
}

# 把 command_args 解析成"每行一个参数"：空格分隔，支持单/双引号和反斜杠转义，
# 忽略空行与以 # 开头的整行注释。
command_args_tokens() {
    awk '
        {
            line = $0
            sub(/\r$/, "", line)
            if (line ~ /^[ \t]*#/) next
            n = length(line)
            i = 1
            while (i <= n) {
                c = substr(line, i, 1)
                if (c == " " || c == "\t") { i++; continue }
                tok = ""
                q = ""
                while (i <= n) {
                    c = substr(line, i, 1)
                    if (q == "") {
                        if (c == " " || c == "\t") break
                        if (c == "\047" || c == "\"") { q = c; i++; continue }
                        if (c == "\\" && i < n) { i++; tok = tok substr(line, i, 1); i++; continue }
                        tok = tok c
                        i++
                    } else {
                        if (c == q) { q = ""; i++; continue }
                        if (q == "\"" && c == "\\" && i < n) { i++; tok = tok substr(line, i, 1); i++; continue }
                        tok = tok c
                        i++
                    }
                }
                print tok
            }
        }
    ' "${1:-$COMMAND_ARGS_FILE}"
}

# 稳定 machine-id：置于模块数据目录，避免 Linux 构建回退到 /var/lib/easytier。
stable_machine_id() {
    _mid_file="$DATA_DIR/machine-id"
    if [ ! -s "$_mid_file" ]; then
        _mid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null)
        [ -n "$_mid" ] || _mid="android-$(date +%s)-$$"
        printf '%s\n' "$_mid" > "$_mid_file" 2>/dev/null
    fi
    cat "$_mid_file" 2>/dev/null
}

# 运行中的核心进程 pid；优先 pid 文件，其次 pgrep。
running_core_pid() {
    _pid=$(pid_from_file "$CORE_PID_FILE")
    pid_is_easytier "$_pid" && { echo "$_pid"; return 0; }
    pgrep -f "$MODDIR/easytier/.*/easytier-core" 2>/dev/null | head -n1
}

running_web_pid() {
    _pid=$(pid_from_file "$WEB_PID_FILE")
    pid_is_easytier "$_pid" && { echo "$_pid"; return 0; }
    pgrep -f "$MODDIR/easytier/.*/easytier-web-embed" 2>/dev/null | head -n1
}

# 可被 disable 文件或 USR1 打断的睡眠。
sleep_watch() {
    _left=$1
    while [ "$_left" -gt 0 ]; do
        [ -f "$MODDIR/disable" ] && return 0
        [ "${RESTART_REQUEST:-0}" = "1" ] && return 0
        sleep 1
        _left=$((_left - 1))
    done
}
