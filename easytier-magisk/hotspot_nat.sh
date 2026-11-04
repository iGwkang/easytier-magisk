#!/data/adb/magisk/busybox sh
# 把热点 / USB 网络共享的客户端流量经 EasyTier TUN 转发（IPv4）。
# 用法: hotspot_nat.sh add|del|watch

MODDIR=${0%/*}
. "$MODDIR/common.sh"
load_module_conf

ACTION=${1:-watch}
CHAIN_NAT=ET_NAT
CHAIN_FWD=ET_FWD

log_nat() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

command -v iptables >/dev/null 2>&1 || {
    log_nat "iptables 不存在，热点 NAT 不可用"
    exit 1
}

find_tun() {
    _dev=""
    if [ -f "$CONFIG_FILE" ]; then
        _dev=$(sed -n "s/^[[:space:]]*dev_name[[:space:]]*=[[:space:]]*[\"']\([^\"']*\)[\"'].*/\1/p" "$CONFIG_FILE" 2>/dev/null | head -n1)
    fi
    # command_args 模式（含 --dev-name 覆盖）时按官方参数解析。
    if [ -z "$_dev" ] && command_args_present; then
        _dev=$(command_args_tokens | awk '
            prev == "--dev-name" { print; exit }
            /^--dev-name=/ { sub(/^--dev-name=/, ""); print; exit }
            /^--dev-name$/ { prev = "--dev-name" }
        ')
    fi
    if [ -n "$_dev" ] && ip link show "$_dev" >/dev/null 2>&1; then
        echo "$_dev"
        return 0
    fi
    ip -o link show 2>/dev/null | awk -F': ' '
        {
            name = $2
            sub(/@.*/, "", name)
            if (name ~ /^(tun|easytier)/) { print name; exit }
        }'
}

link_cidr() {
    ip -4 -o addr show dev "$1" 2>/dev/null | awk '
        {
            cidr = ""
            for (i = 1; i <= NF; i++)
                if ($i == "inet" && i < NF) { cidr = $(i + 1); break }
            if (cidr == "") next
            split(cidr, parts, "/")
            split(parts[1], o, ".")
            p = parts[2] + 0
            v = o[1] * 16777216 + o[2] * 65536 + o[3] * 256 + o[4]
            block = 2 ^ (32 - p)
            net = int(v / block) * block
            printf "%d.%d.%d.%d/%d\n", int(net / 16777216) % 256, int(net / 65536) % 256, int(net / 256) % 256, net % 256, p
        }'
}

find_links() {
    _tun=$1
    _default=$(ip route show default 2>/dev/null | awk '{ print $5; exit }')
    for _iface in $(ip -o link show 2>/dev/null | awk -F': ' '{ print $2 }' | cut -d'@' -f1); do
        [ "$_iface" = "$_tun" ] && continue
        [ "$_iface" = "lo" ] && continue
        [ -n "$_default" ] && [ "$_iface" = "$_default" ] && continue
        case "$_iface" in
            wlan*|swlan*|softap*|ap*|p2p-wlan*|rndis*|usb*|bt-pan*|ncm*|eth*)
                _cidr=$(link_cidr "$_iface")
                [ -n "$_cidr" ] && printf '%s %s\n' "$_iface" "$_cidr"
                ;;
        esac
    done
}

set_forwarding() {
    [ -w /proc/sys/net/ipv4/ip_forward ] || return 0
    _cur=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
    if [ "$_cur" = "0" ]; then
        echo 0 > "$DATA_DIR/ip_forward.orig" 2>/dev/null
        echo 1 2>/dev/null > /proc/sys/net/ipv4/ip_forward
    fi
}

restore_forwarding() {
    if [ -f "$DATA_DIR/ip_forward.orig" ] && [ -w /proc/sys/net/ipv4/ip_forward ]; then
        cat "$DATA_DIR/ip_forward.orig" 2>/dev/null > /proc/sys/net/ipv4/ip_forward
        rm -f "$DATA_DIR/ip_forward.orig"
    fi
}

apply_rules() {
    _tun=$1
    _links=$2
    [ -n "$_tun" ] || return 1

    iptables -t nat -N "$CHAIN_NAT" 2>/dev/null
    iptables -N "$CHAIN_FWD" 2>/dev/null
    if ! iptables -t nat -C POSTROUTING -j "$CHAIN_NAT" 2>/dev/null; then
        iptables -t nat -I POSTROUTING 1 -j "$CHAIN_NAT" ||
            { log_nat "NAT 规则插入失败: POSTROUTING -> $CHAIN_NAT"; return 1; }
    fi
    if ! iptables -C FORWARD -j "$CHAIN_FWD" 2>/dev/null; then
        iptables -I FORWARD 1 -j "$CHAIN_FWD" ||
            { log_nat "NAT 规则插入失败: FORWARD -> $CHAIN_FWD"; return 1; }
    fi

    # 每次按当前接口状态重建，避免重复规则。
    iptables -t nat -F "$CHAIN_NAT" 2>/dev/null
    iptables -F "$CHAIN_FWD" 2>/dev/null

    _fail=0
    add_pair() {
        [ -n "$1" ] || return 0
        [ -n "$2" ] || return 0
        iptables -t nat -A "$CHAIN_NAT" -s "$2" -o "$_tun" -j MASQUERADE || _fail=1
        iptables -A "$CHAIN_FWD" -i "$1" -o "$_tun" \
            -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT || _fail=1
        iptables -A "$CHAIN_FWD" -i "$_tun" -o "$1" \
            -m state --state ESTABLISHED,RELATED -j ACCEPT || _fail=1
    }
    while IFS=' ' read -r _iface _cidr; do
        add_pair "$_iface" "$_cidr"
    done <<EOF
$_links
EOF

    set_forwarding
    if [ "$_fail" = "1" ]; then
        log_nat "NAT 规则部分失败: tun=$_tun links=$(printf '%s' "$_links" | tr '\n' ';')"
        return 1
    fi
    log_nat "NAT applied: tun=$_tun links=$(printf '%s' "$_links" | tr '\n' ';')"
}

del_rules() {
    _n=0
    while [ "$_n" -lt 8 ] && iptables -t nat -D POSTROUTING -j "$CHAIN_NAT" 2>/dev/null; do
        _n=$((_n + 1))
    done
    _n=0
    while [ "$_n" -lt 8 ] && iptables -D FORWARD -j "$CHAIN_FWD" 2>/dev/null; do
        _n=$((_n + 1))
    done
    iptables -t nat -F "$CHAIN_NAT" 2>/dev/null
    iptables -F "$CHAIN_FWD" 2>/dev/null
    iptables -t nat -X "$CHAIN_NAT" 2>/dev/null
    iptables -X "$CHAIN_FWD" 2>/dev/null
    restore_forwarding
    log_nat "NAT removed"
}

case "$ACTION" in
    add)
        _tun=$(find_tun)
        [ -n "$_tun" ] || { log_nat "未找到 EasyTier TUN 接口"; exit 1; }
        apply_rules "$_tun" "$(find_links "$_tun")"
        ;;
    del)
        del_rules
        ;;
    watch)
        [ "$HOTSPOT_NAT" = "1" ] || exit 0
        _applied=""
        trap 'del_rules; exit 0' TERM INT
        log_nat "NAT watcher started"
        while :; do
            # module.conf 可能在运行中被修改：关闭热点 NAT 后立即清理规则。
            [ -f "$MODULE_CONF" ] && . "$MODULE_CONF"
            [ "$HOTSPOT_NAT" = "1" ] || break
            [ -f "$MODDIR/disable" ] && break
            pid_is_supervisor "$(pid_from_file "$SUPERVISOR_PID_FILE")" || break
            _tun=$(find_tun)
            if [ -n "$_tun" ]; then
                _links=$(find_links "$_tun")
                _sig="$_tun|$_links"
                if [ "$_sig" != "$_applied" ]; then
                    if apply_rules "$_tun" "$_links"; then
                        _applied="$_sig"
                    fi
                fi
            elif [ -n "$_applied" ]; then
                del_rules
                _applied=""
            fi
            sleep 10
        done
        del_rules
        ;;
    *)
        echo "用法: $0 add|del|watch"
        exit 1
        ;;
esac
