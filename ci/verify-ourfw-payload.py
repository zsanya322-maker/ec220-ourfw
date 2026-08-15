#!/usr/bin/env python3
"""Independent final-image check for the v0.6.1 mutable payload/upgrade safety."""
from __future__ import annotations
import argparse, bz2, importlib.util, io, tarfile
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
if '/usr/share/ourfw/defaults.tar.bz2' in sq.paths:
    try:
        arc=sq.read('/usr/share/ourfw/defaults.tar.bz2')
        with tarfile.open(fileobj=io.BytesIO(arc),mode='r:bz2') as tf:
            names=set(tf.getnames())
            version=tf.extractfile('./VERSION').read().decode().strip() if './VERSION' in names else ''
        need(version=='v0.6.1',f'defaults VERSION is {version!r}, expected v0.6.1')
        for n in ['./modules/vpn/module-handoff.sh','./modules/vpn/apply.sh','./modules/vpn/failover.sh']:
            need(n in names,f'defaults missing {n}')
    except Exception as e:
        errs.append(f'defaults archive unreadable: {e}')
lines=['PAYLOAD_VERIFY='+('FAILED' if errs else 'OK')]
lines += ['ERROR='+e for e in errs]
Path(a.report).write_text('\n'.join(lines)+'\n')
print(Path(a.report).read_text(),end='')
raise SystemExit(64 if errs else 0)
