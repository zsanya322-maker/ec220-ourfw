#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
errs=[]
def t(p): return (R/p).read_text(errors='replace')
def need(c,m):
    if not c: errs.append(m)

ver=t('ourfw/VERSION').strip()
smart=t('ourfw/modules/smart-routing/apply.sh')
wd=t('ourfw/modules/watchdog/watchdog.sh')
dns=t('ourfw/modules/dns/apply.sh')
rollback=t('ourfw/runtime/ourfw-rollback.sh')
updater=t('ourfw/runtime/ourfw-update.sh')
loader=t('bootstrap/ourfw-loader.sh')
budget=t('tools/storage-budget.sh')
static=t('tests/static-check.sh') if (R/'tests/static-check.sh').exists() else ''
payload=t('ci/verify-ourfw-payload.py')

need(ver=='v0.6.2',f'expected v0.6.2, got {ver!r}')
need('route_fail()' in smart and 'routing: critical rule failed:' in smart,'critical routing failure helper missing')
for token in ['IPv4 kill-switch reject','IPv6 output reject','policy ip rule','mangle PREROUTING jump','VPN policy default route']:
    need(token in smart,f'critical routing gate missing: {token}')
need('ip rule add fwmark "$FWMARK/$FWMASK"' in smart and 'ip rule add fwmark "$FWMARK/$FWMASK" table "$ROUTE_TABLE" pref "$RULE_PREF" >/dev/null 2>&1 || true' not in smart,'policy ip rule failure still ignored')
need('[ -n "$line" ] || return 1' in wd,'missing default route still treated healthy')
need('[ "$type" = openvpn ] && return 1' in wd,'OpenVPN explicit target failure can still be masked by daemon liveness')
need('age=$((now-ts)); [ "$age" -ge 0 ]' in wd,'future InetDetect timestamp still accepted')
need('OURFW_WATCHDOG_ONESHOT' in wd,'watchdog dynamic regression hook missing')
need('WATCHDOG_FAILS must be >= 1' in wd,'zero failure threshold still accepted')
need("echo 'no-resolv'" in dns and 'dns: fail-closed:' in dns and 'upstreams are deliberately IPv4-only' in dns,'explicit DNS can still fall back to resolv.conf or accept unsafe IPv6/malformed input')
need('IPv6 peer DNS $s unsupported' in dns,'unsupported VPN IPv6 peer DNS is not rejected')
need('pending retained for retry' in rollback and 'if reapply; then' in rollback,'rollback can still report success after runtime reapply failure')
need('special archive members are not allowed' in updater and 'substr($1,1,1)!="-"' in updater,'component updater still accepts special tar members')
pre=loader.find('if ! preflight_mutable')
persist=loader.find('if ! persist_storage',pre)
remove=loader.find('rm -rf "$old"',persist)
need(pre>=0 and persist>pre and remove>persist,'loader discards old tree before candidate preflight/persistence succeeds')
need('firmware OURFW refresh failed preflight' in loader and 'firmware OURFW refresh storage save failed' in loader,'loader rollback diagnostics missing')
need('OURFW_LIMIT=${OURFW_STORAGE_LIMIT:-65536}' in budget,'OURFW Storage cap is not conservatively limited to 64 KiB')
need('Reserved for Padavan/user storage' in budget,'Storage reserve is not reported')
for f in ['v062-network-faults.sh','v062-watchdog-mock.sh','v062-loader-failure-mock.sh','v062-dns-failclosed.sh','v062-rollback-reapply-mock.sh','v062-update-specialfiles.sh']:
    need(f in static,f'{f} is not wired into static checks')
need('v062-regressions.py' in static,'v0.6.2 static regression is not wired')
need("version=='v0.6.2'" in payload and "b'routing: critical rule failed:'" in payload and "b'OURFW_WATCHDOG_ONESHOT'" in payload and "b'no-resolv'" in payload and "b'pending retained for retry'" in payload and "b'special archive members are not allowed'" in payload,'final payload verifier does not enforce v0.6.2 fixes')

if errs:
    for e in errs: print('ERROR:',e,file=sys.stderr)
    raise SystemExit(1)
print('V0.6.2 REGRESSIONS: OK')
