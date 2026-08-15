#!/usr/bin/env python3
"""Independent final-image check for OURFW v0.6.2 mutable payload/safety fixes."""
from __future__ import annotations
import argparse, importlib.util, io, tarfile
from pathlib import Path

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('ourfw_image_verify', HERE/'verify-built-image.py')
mod=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(mod)

ap=argparse.ArgumentParser(); ap.add_argument('image'); ap.add_argument('report',nargs='?',default='PAYLOAD-VERIFY.txt'); a=ap.parse_args()
sq=mod.Squash(Path(a.image).read_bytes())
errs=[]
def need(c,m):
    if not c: errs.append(m)
need('/usr/bin/ourfw-loader.sh' in sq.paths,'immutable loader missing')
need('/usr/share/ourfw/defaults.tar.bz2' in sq.paths,'defaults archive missing')
if '/usr/bin/ourfw-loader.sh' in sq.paths:
    loader=sq.read('/usr/bin/ourfw-loader.sh')
    need(b'refresh_defaults_if_needed' in loader,'loader lacks firmware-to-mutable refresh')
    need(b'config profiles rules' in loader,'loader lacks user-data preservation contract')
    need(b'firmware OURFW refresh failed preflight' in loader,'loader lacks preflight rollback')
    need(b'firmware OURFW refresh storage save failed' in loader,'loader lacks Storage-save rollback')
    need(b'if ! persist_storage' in loader,'loader does not gate upgrade on persistent Storage save')
if '/usr/share/ourfw/defaults.tar.bz2' in sq.paths:
    try:
        arc=sq.read('/usr/share/ourfw/defaults.tar.bz2')
        with tarfile.open(fileobj=io.BytesIO(arc),mode='r:bz2') as tf:
            names=set(tf.getnames())
            def read(name):
                f=tf.extractfile(name); return f.read() if f else b''
            version=read('./VERSION').decode().strip() if './VERSION' in names else ''
            smart=read('./modules/smart-routing/apply.sh') if './modules/smart-routing/apply.sh' in names else b''
            watchdog=read('./modules/watchdog/watchdog.sh') if './modules/watchdog/watchdog.sh' in names else b''
            dns=read('./modules/dns/apply.sh') if './modules/dns/apply.sh' in names else b''
            rollback=read('./runtime/ourfw-rollback.sh') if './runtime/ourfw-rollback.sh' in names else b''
            updater=read('./runtime/ourfw-update.sh') if './runtime/ourfw-update.sh' in names else b''
        need(version=='v0.6.2',f'defaults VERSION is {version!r}, expected v0.6.2')
        for n in ['./modules/vpn/module-handoff.sh','./modules/vpn/apply.sh','./modules/vpn/failover.sh','./modules/smart-routing/apply.sh','./modules/watchdog/watchdog.sh','./modules/dns/apply.sh','./runtime/ourfw-rollback.sh','./runtime/ourfw-update.sh']:
            need(n in names,f'defaults missing {n}')
        for token in [b'routing: critical rule failed:',b'IPv4 kill-switch reject',b'IPv6 output reject',b'policy ip rule']:
            need(token in smart,f'smart-routing payload lacks {token!r}')
        for token in [b'OURFW_WATCHDOG_ONESHOT',b'[ "$type" = openvpn ] && return 1',b'[ "$age" -ge 0 ]']:
            need(token in watchdog,f'watchdog payload lacks {token!r}')
        for token in [b'no-resolv',b'dns: fail-closed:',b'IPv6 peer DNS $s unsupported',b'upstreams are deliberately IPv4-only']:
            need(token in dns,f'dns payload lacks {token!r}')
        for token in [b'if reapply; then',b'pending retained for retry']:
            need(token in rollback,f'rollback payload lacks {token!r}')
        need(b'special archive members are not allowed' in updater,'updater payload lacks special-file archive guard')
    except Exception as e:
        errs.append(f'defaults archive unreadable: {e}')
lines=['PAYLOAD_VERIFY='+('FAILED' if errs else 'OK')]
lines += ['ERROR='+e for e in errs]
Path(a.report).write_text('\n'.join(lines)+'\n')
print(Path(a.report).read_text(),end='')
raise SystemExit(64 if errs else 0)
