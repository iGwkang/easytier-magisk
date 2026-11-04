#!/data/adb/magisk/busybox sh
# EasyTier 主守护脚本：启动 easytier-core（可选 easytier-web-embed），
# 崩溃自动重启，模块禁用时停止，重新启用后自动恢复。

MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_module_conf

ARCH=$(resolve_arch)
BIN_DIR="$MODDIR/easytier/$ARCH"

CORE_PID=""
WEB_PID=""
HOTSPOT_PID=""
CORE_STARTED=0
WEB_LAST_START=0
HOTSPOT_LAST_START=0
RESTART_REQUEST=0
RELOAD_REQUEST=0
USER_RESTART=0
STOP_REQUEST=0
cleanup_done=0

mkdir -p "$LOG_DIR" "$(dirname "$WEB_DB")" 2>/dev/null

# 防止 service.sh 与 action.sh 同时拉起多个守护进程。
_old_sup=$(pid_from_file "$SUPERVISOR_PID_FILE")
if pid_is_supervisor "$_old_sup" && [ "$_old_sup" != "$$" ]; then
    log_line "supervisor 已存在 pid=$_old_sup，本实例退出"
    exit 0
fi
echo $$ > "$SUPERVISOR_PID_FILE"

cleanup() {
    [ "$cleanup_done" = "1" ] && return 0
    cleanup_done=1

    # 只停止本实例启动的子进程，避免误杀新实例的同名进程。
    stop_pid_checked "$CORE_PID" easytier-core
    stop_pid_checked "$WEB_PID" easytier-web
    stop_pid_checked "$HOTSPOT_PID" hotspot_nat.sh
    remove_pidfile_if_pid "$CORE_PID_FILE" "$CORE_PID"
    remove_pidfile_if_pid "$WEB_PID_FILE" "$WEB_PID"
    remove_pidfile_if_pid "$HOTSPOT_PID_FILE" "$HOTSPOT_PID"
    remove_pidfile_if_pid "$SUPERVISOR_PID_FILE" "$$"
    "$MODDIR/hotspot_nat.sh" del >/dev/null 2>&1
    log_line "supervisor stopped"
}
trap cleanup EXIT
trap 'STOP_REQUEST=1; exit 0' TERM INT
trap 'RESTART_REQUEST=1; RELOAD_REQUEST=1' USR1

stop_all() {
    _stop_core=$CORE_PID
    stop_pid_checked "$CORE_PID" easytier-core
    stop_pid_checked "$WEB_PID" easytier-web
    stop_pid_checked "$HOTSPOT_PID" hotspot_nat.sh
    stop_pidfile "$CORE_PID_FILE"
    stop_pidfile "$WEB_PID_FILE"
    stop_pidfile_any "$HOTSPOT_PID_FILE" hotspot_nat.sh
    wait "$_stop_core" 2>/dev/null
    CORE_PID=""
    WEB_PID=""
    HOTSPOT_PID=""
}

start_web() {
    [ "$WEB_ENABLE" = "1" ] || return 0
    [ -x "$BIN_DIR/easytier-web-embed" ] || { log_line "web-embed 不存在: $BIN_DIR"; return 1; }
    _web=$(running_web_pid)
    if pid_is_easytier "$_web"; then
        WEB_PID=$_web
        echo "$WEB_PID" > "$WEB_PID_FILE"
        return 0
    fi

    set -- -d "$WEB_DB" \
        -c "$WEB_CONFIG_PORT" -p "$WEB_CONFIG_PROTOCOL" \
        -a "$WEB_PORT" --api-server-addr "$WEB_ADDR" \
        -l "$WEB_PORT" --web-server-addr "$WEB_ADDR"
    args_contain_any --file-log-dir "$@" || set -- "$@" --file-log-dir "$LOG_DIR/web"
    args_contain_any --file-log-level "$@" || set -- "$@" --file-log-level "$EASYTIER_LOG_LEVEL"
    args_contain_any --console-log-level "$@" || set -- "$@" --console-log-level "$EASYTIER_CONSOLE_LEVEL"
    if [ -n "$WEB_ARGS" ]; then
        _wfile="$DATA_DIR/web_args.tokens"
        printf '%s\n' "$WEB_ARGS" > "$_wfile"
        command_args_tokens "$_wfile" > "$_wfile.parsed"
        while IFS= read -r _tok; do
            set -- "$@" "$_tok"
        done < "$_wfile.parsed"
        rm -f "$_wfile" "$_wfile.parsed"
    fi

    "$BIN_DIR/easytier-web-embed" "$@" >> "$LOG_DIR/web.console.log" 2>&1 &
    WEB_PID=$!
    WEB_LAST_START=$(date +%s)
    echo "$WEB_PID" > "$WEB_PID_FILE"
    log_line "easytier-web-embed started pid=$WEB_PID http://$WEB_ADDR:$WEB_PORT"
}

ensure_web() {
    [ "$WEB_ENABLE" = "1" ] || return 0
    _web=$(running_web_pid)
    if pid_is_easytier "$_web"; then
        WEB_PID=$_web
        echo "$WEB_PID" > "$WEB_PID_FILE"
        return 0
    fi
    _now=$(date +%s)
    [ $((_now - WEB_LAST_START)) -lt 30 ] && return 0
    log_line "easytier-web-embed 已退出，重新启动"
    WEB_LAST_START=$_now
    rm -f "$WEB_PID_FILE"
    start_web
}

start_hotspot() {
    [ "$HOTSPOT_NAT" = "1" ] || return 0
    _pid=$(pid_from_file "$HOTSPOT_PID_FILE")
    if pid_is_hotspot "$_pid"; then
        HOTSPOT_PID=$_pid
        return 0
    fi
    _now=$(date +%s)
    [ $((_now - HOTSPOT_LAST_START)) -lt 15 ] && return 0
    HOTSPOT_LAST_START=$_now
    "$MODDIR/hotspot_nat.sh" watch >> "$LOG_DIR/hotspot.log" 2>&1 &
    HOTSPOT_PID=$!
    echo "$HOTSPOT_PID" > "$HOTSPOT_PID_FILE"
}

build_and_start_core() {
    _want_hostname=""

    if command_args_present; then
        CORE_MODE="启动参数"
        _tokens="$DATA_DIR/command_args.tokens"
        set --
        if ! command_args_tokens > "$_tokens"; then
            rm -f "$_tokens"
            log_line "command_args 解析失败: $COMMAND_ARGS_FILE"
            set_status "配置错误：command_args 解析失败"
            return 1
        fi
        while IFS= read -r _tok; do
            set -- "$@" "$_tok"
        done < "$_tokens"
        rm -f "$_tokens"
        if [ $# -eq 0 ]; then
            log_line "command_args 没有有效参数: $COMMAND_ARGS_FILE"
            set_status "配置错误：command_args 为空"
            return 1
        fi

        # 这些参数会让 easytier-core 脱离或绕过本模块的守护模型。
        for _arg in "$@"; do
            case "$_arg" in
                --daemon|--daemon=*)
                    log_line "command_args 不支持 --daemon：守护进程由模块负责"
                    set_status "配置错误：command_args 不能使用 --daemon"
                    return 1
                    ;;
                --check-config|--check-config=*|--gen-autocomplete|--gen-autocomplete=*)
                    log_line "command_args 不支持一次性参数 $_arg，请手动执行 easytier-core"
                    set_status "配置错误：command_args 含一次性参数"
                    return 1
                    ;;
            esac
        done

        # 配置服务器模式下固定 machine-id，避免设备标识随重启变化。
        _has_server=0
        _has_machine_id=0
        for _arg in "$@"; do
            case "$_arg" in
                -w|--config-server|--config-server=*|-w?*) _has_server=1 ;;
                --machine-id|--machine-id=*) _has_machine_id=1 ;;
            esac
        done
        if [ "$_has_server" = "1" ] && [ "$_has_machine_id" = "0" ]; then
            set -- "$@" --machine-id "$(stable_machine_id)"
        fi
    elif [ "$WEB_MANAGE_LOCAL" = "1" ]; then
        CORE_MODE="Web 托管"
        if [ "$WEB_ENABLE" != "1" ]; then
            log_line "WEB_MANAGE_LOCAL=1 需要同时开启 WEB_ENABLE=1"
            set_status "配置错误：Web 托管需要开启 WEB_ENABLE"
            return 1
        fi
        if [ -z "$WEB_MANAGE_TOKEN" ]; then
            log_line "WEB_MANAGE_LOCAL=1 需要设置 WEB_MANAGE_TOKEN（Web 界面的用户名）"
            set_status "配置错误：缺少 WEB_MANAGE_TOKEN"
            return 1
        fi
        set -- -w "${WEB_CONFIG_PROTOCOL}://127.0.0.1:${WEB_CONFIG_PORT}/${WEB_MANAGE_TOKEN}" \
            --machine-id "$(stable_machine_id)"
        _want_hostname=${CUSTOM_HOSTNAME:-$(auto_hostname)}
    else
        CORE_MODE="配置文件"
        if [ ! -f "$CONFIG_FILE" ]; then
            log_line "配置文件不存在: $CONFIG_FILE"
            set_status "配置文件不存在: $CONFIG_FILE"
            return 1
        fi
        set -- -c "$CONFIG_FILE"
        if [ -n "$CUSTOM_HOSTNAME" ]; then
            _want_hostname=$CUSTOM_HOSTNAME
        elif ! grep -Eq '^[[:space:]]*hostname[[:space:]]*=' "$CONFIG_FILE"; then
            _want_hostname=$(auto_hostname)
        fi
    fi

    [ -n "$_want_hostname" ] && set -- "$@" --hostname "$_want_hostname"

    args_contain_any --file-log-dir "$@" || set -- "$@" --file-log-dir "$LOG_DIR/core"
    args_contain_any --file-log-level "$@" || set -- "$@" --file-log-level "$EASYTIER_LOG_LEVEL"
    args_contain_any --file-log-size "$@" || set -- "$@" --file-log-size "$EASYTIER_LOG_SIZE_MB"
    args_contain_any --file-log-count "$@" || set -- "$@" --file-log-count "$EASYTIER_LOG_COUNT"
    args_contain_any --console-log-level "$@" || set -- "$@" --console-log-level "$EASYTIER_CONSOLE_LEVEL"
    if ! args_contain_any --rpc-portal "$@" && ! args_contain_any -r "$@"; then
        set -- "$@" --rpc-portal "$RPC_PORTAL"
    fi

    rotate_log "$LOG_DIR/core.console.log"
    "$BIN_DIR/easytier-core" "$@" >> "$LOG_DIR/core.console.log" 2>&1 &
    CORE_PID=$!
    CORE_STARTED=$(date +%s)
    echo "$CORE_PID" > "$CORE_PID_FILE"
    log_line "easytier-core started pid=$CORE_PID mode=$CORE_MODE arch=$ARCH"
    return 0
}

if [ ! -x "$BIN_DIR/easytier-core" ]; then
    log_line "当前架构 $ARCH 没有可用二进制: $BIN_DIR/easytier-core"
    set_status "不支持的架构: $ARCH"
    exit 1
fi

log_line "supervisor started pid=$$ arch=$ARCH"
ensure_tun
ensure_ip_rule
set_status "运行中（$ARCH）"

# 守护进程被强杀后 core 可能仍在运行，直接接管，避免重复实例争抢端口。
_existing_core=$(running_core_pid)
if pid_is_easytier "$_existing_core"; then
    CORE_PID=$_existing_core
    CORE_STARTED=$(date +%s)
    echo "$CORE_PID" > "$CORE_PID_FILE"
    log_line "接管已有 easytier-core pid=$CORE_PID"
fi

backoff=5
while :; do
    [ "$STOP_REQUEST" = "1" ] && break
    if [ ! -d "$MODDIR" ]; then
        break
    fi

    # 模块被禁用：停止所有子进程并等待重新启用。
    if [ -f "$MODDIR/disable" ]; then
        stop_all
        set_status "已停止（模块已禁用）"
        sleep 5
        continue
    fi

    if [ "$RELOAD_REQUEST" = "1" ]; then
        RELOAD_REQUEST=0
        load_module_conf
        if [ "$WEB_ENABLE" != "1" ]; then
            stop_pidfile "$WEB_PID_FILE"
            WEB_PID=""
        fi
        if [ "$HOTSPOT_NAT" != "1" ]; then
            stop_pidfile_any "$HOTSPOT_PID_FILE" hotspot_nat.sh
            HOTSPOT_PID=""
        fi
    fi

    start_web
    start_hotspot
    RESTART_REQUEST=0

    if ! pid_alive "$CORE_PID"; then
        if ! build_and_start_core; then
            sleep_watch 30
            continue
        fi
        set_status "运行中（$ARCH）"
    fi

    # 监视核心进程；期间保持 Web 与 NAT 守护存活。
    while pid_alive "$CORE_PID"; do
        if [ -f "$MODDIR/disable" ] || [ "$STOP_REQUEST" = "1" ]; then
            break
        fi
        if [ "$RESTART_REQUEST" = "1" ]; then
            RESTART_REQUEST=0
            USER_RESTART=1
            kill -TERM "$CORE_PID" 2>/dev/null
            break
        fi
        rotate_log "$LOG_DIR/core.console.log"
        rotate_log "$LOG_DIR/web.console.log"
        ensure_web
        start_hotspot
        sleep 2
    done

    if [ -f "$MODDIR/disable" ] || [ "$STOP_REQUEST" = "1" ]; then
        continue
    fi

    wait "$CORE_PID" 2>/dev/null
    _runtime=$(( $(date +%s) - CORE_STARTED ))
    remove_pidfile_if_pid "$CORE_PID_FILE" "$CORE_PID"
    CORE_PID=""

    if [ "$_runtime" -lt 10 ] && [ "$USER_RESTART" != "1" ]; then
        log_line "easytier-core 启动失败，$_runtime 秒后退出，详见 $LOG_DIR/core.console.log"
        set_status "启动失败，详见日志 $LOG_DIR/core.console.log"
        backoff=60
    elif [ "$USER_RESTART" = "1" ] || [ "$_runtime" -ge 60 ]; then
        log_line "easytier-core 退出，运行 $_runtime 秒"
        backoff=5
    else
        log_line "easytier-core 退出，运行 $_runtime 秒"
        backoff=$((backoff * 2))
        [ "$backoff" -gt 60 ] && backoff=60
    fi

    if [ "$USER_RESTART" = "1" ]; then
        USER_RESTART=0
        backoff=1
    fi

    set_status "重启中（${backoff}s 后）"
    sleep_watch "$backoff"
done
