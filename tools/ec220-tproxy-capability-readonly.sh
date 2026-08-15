#!/bin/sh
# EC220-G5 v2 / OURFW read-only TPROXY capability probe.
# It does NOT load modules, add firewall rules, add routes or start a proxy.
set -u

say() { printf '%s\n' "$*"; }
yn() { [ "$1" = 1 ] && printf 'YES' || printf 'NO'; }

say '=== OURFW TPROXY CAPABILITY (READ-ONLY) ==='
say "date=$(date 2>/dev/null || echo unknown)"
say "uname=$(uname -a 2>/dev/null || echo unknown)"
say "path=$PATH"
say ''

have_file() { [ -e "$1" ] && echo 1 || echo 0; }
have_exec_path() {
    name=$1
    oldIFS=$IFS; IFS=:
    for d in $PATH; do
        [ -n "$d" ] || d=.
        if [ -x "$d/$name" ]; then IFS=$oldIFS; printf '%s\n' "$d/$name"; return 0; fi
    done
    IFS=$oldIFS
    return 1
}

say '--- userspace xtables extensions ---'
for p in \
  /usr/lib/xtables/libxt_TPROXY.so /lib/xtables/libxt_TPROXY.so \
  /usr/lib/iptables/libxt_TPROXY.so /lib/iptables/libxt_TPROXY.so \
  /usr/lib/xtables/libxt_socket.so /lib/xtables/libxt_socket.so \
  /usr/lib/iptables/libxt_socket.so /lib/iptables/libxt_socket.so; do
    [ -e "$p" ] && ls -l "$p" 2>/dev/null || true
done

say ''
say '--- loaded kernel targets/matches ---'
for f in /proc/net/ip_tables_targets /proc/net/ip_tables_matches /proc/net/ip_tables_names; do
    if [ -r "$f" ]; then
        say "[$f]"
        cat "$f" 2>/dev/null || true
    else
        say "[$f] unavailable"
    fi
done

say ''
say '--- loaded modules (filtered) ---'
if [ -r /proc/modules ]; then
    grep -Ei '(^|_)(tproxy|socket|nf_defrag|xt_|iptable|ip_tables)' /proc/modules 2>/dev/null || true
else
    lsmod 2>/dev/null | grep -Ei '(^|_)(tproxy|socket|nf_defrag|xt_|iptable|ip_tables)' || true
fi

say ''
say '--- module files on rootfs ---'
KREL=$(uname -r 2>/dev/null || echo '')
for root in "/lib/modules/$KREL" /lib/modules /etc/modules; do
    [ -e "$root" ] || continue
    say "[$root]"
    find "$root" -type f \( -iname '*tproxy*' -o -iname '*socket*.ko*' \) -print 2>/dev/null | head -n 40
 done

say ''
say '--- kernel config evidence ---'
CONFIG_SEEN=0
if [ -r /proc/config.gz ]; then
    ZCAT=$(have_exec_path zcat 2>/dev/null || true)
    if [ -n "$ZCAT" ]; then
        CONFIG_SEEN=1
        "$ZCAT" /proc/config.gz 2>/dev/null | grep -E '^(CONFIG_NETFILTER_XT_TARGET_TPROXY|CONFIG_NETFILTER_XT_MATCH_SOCKET|CONFIG_NETFILTER_XT_MATCH_MARK|CONFIG_IP_ADVANCED_ROUTER|CONFIG_IP_MULTIPLE_TABLES|CONFIG_NETFILTER_XT_TARGET_MARK|CONFIG_NETFILTER_XT_MARK)=' || true
    fi
fi
for cfg in "/boot/config-$KREL" /boot/config /etc/kernel.config; do
    [ -r "$cfg" ] || continue
    CONFIG_SEEN=1
    say "[$cfg]"
    grep -E '^(CONFIG_NETFILTER_XT_TARGET_TPROXY|CONFIG_NETFILTER_XT_MATCH_SOCKET|CONFIG_NETFILTER_XT_MATCH_MARK|CONFIG_IP_ADVANCED_ROUTER|CONFIG_IP_MULTIPLE_TABLES|CONFIG_NETFILTER_XT_TARGET_MARK|CONFIG_NETFILTER_XT_MARK)=' "$cfg" 2>/dev/null || true
done
[ "$CONFIG_SEEN" -eq 1 ] || say 'kernel config not exposed on running system'

say ''
say '--- iproute policy-routing capability (help only) ---'
IP=$(have_exec_path ip 2>/dev/null || true)
if [ -n "$IP" ]; then
    say "ip=$IP"
    "$IP" rule help 2>&1 | sed -n '1,12p' || true
    "$IP" route help 2>&1 | sed -n '1,12p' || true
else
    say 'ip=missing'
fi

say ''
say '--- iptables userspace parser (help only; no rule mutation) ---'
IPT=$(have_exec_path iptables 2>/dev/null || true)
if [ -n "$IPT" ]; then
    say "iptables=$IPT"
    TPH=$($IPT -j TPROXY --help 2>&1 || true)
    SOH=$($IPT -m socket --help 2>&1 || true)
    printf '%s\n' "$TPH" | grep -E 'TPROXY|on-port|on-ip|tproxy-mark' | head -n 12 || true
    printf '%s\n' "$SOH" | grep -Ei 'socket|transparent|nowildcard|restore-skmark' | head -n 12 || true
else
    say 'iptables=missing'
fi

say ''
say '--- summary evidence ---'
userspace_tproxy=0
for p in /usr/lib/xtables/libxt_TPROXY.so /lib/xtables/libxt_TPROXY.so /usr/lib/iptables/libxt_TPROXY.so /lib/iptables/libxt_TPROXY.so; do [ -e "$p" ] && userspace_tproxy=1; done
loaded_tproxy=0
[ -r /proc/net/ip_tables_targets ] && grep -qx 'TPROXY' /proc/net/ip_tables_targets 2>/dev/null && loaded_tproxy=1
module_tproxy=0
for root in "/lib/modules/$KREL" /lib/modules; do
    [ -d "$root" ] && find "$root" -type f -iname '*tproxy*.ko*' -print -quit 2>/dev/null | grep -q . && module_tproxy=1
done
policy=0
[ -n "$IP" ] && policy=1
say "userspace_tproxy=$(yn "$userspace_tproxy")"
say "loaded_tproxy=$(yn "$loaded_tproxy")"
say "module_file_tproxy=$(yn "$module_tproxy")"
say "ip_policy_tool=$(yn "$policy")"
say 'NOTE: NO here does not prove the kernel lacks TPROXY when config/modules are hidden or built-in.'
say 'NOTE: This probe deliberately does not modprobe or install a test rule.'
say '=== END ==='
