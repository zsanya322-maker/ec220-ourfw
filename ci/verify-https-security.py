#!/usr/bin/env python3
"""Verify HTTPS/curl security invariants in the final firmware image."""
from pathlib import Path
import argparse, runpy, sys
HERE=Path(__file__).resolve().parent
Squash=runpy.run_path(str(HERE/'verify-built-image.py'))['Squash']

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('image'); ap.add_argument('report',nargs='?',default='HTTPS-VERIFY.txt'); a=ap.parse_args()
    image=Path(a.image); report=Path(a.report); sq=Squash(image.read_bytes()); errs=[]
    def need(c,m):
        if not c: errs.append(m)
    for p in ['/usr/bin/https-cert.sh','/www/Advanced_Services_Content.asp','/etc_ro/ca-certificates.crt','/sbin/dev_init.sh','/usr/bin/curl']:
        need(p in sq.paths,f'missing {p}')
    cert=sq.read('/usr/bin/https-cert.sh') if '/usr/bin/https-cert.sh' in sq.paths else b''
    ui=sq.read('/www/Advanced_Services_Content.asp') if '/www/Advanced_Services_Content.asp' in sq.paths else b''
    ca=sq.read('/etc_ro/ca-certificates.crt') if '/etc_ro/ca-certificates.crt' in sq.paths else b''
    init=sq.read('/sbin/dev_init.sh') if '/sbin/dev_init.sh' in sq.paths else b''
    need(b'RSA_BITS=2048' in cert and b'RSA_BITS=1024' not in cert,'https-cert.sh default is not RSA-2048')
    need(b'value="2048" selected="selected">RSA 2048 (*)' in ui,'WebUI does not select RSA-2048 by default')
    need(b'<option value="1024">RSA 1024</option>' in ui,'legacy RSA-1024 explicit option unexpectedly removed/marked default')
    certs=ca.count(b'-----BEGIN CERTIFICATE-----')
    need(certs >= 100,f'CA bundle unexpectedly small: {certs} certificates')
    need(b'ln -sf /etc_ro/ca-certificates.crt /etc/ssl/cert.pem' in init,'boot does not install curl/OpenSSL CA bundle path')
    lines=[f'IMAGE={image.name}','HTTPS_DEFAULT_RSA_BITS=2048',f'CA_CERTIFICATES={certs}','CA_RUNTIME_PATH=/etc/ssl/cert.pem']
    if errs:
        lines.insert(0,'HTTPS_VERIFY=FAILED'); lines += ['ERROR='+e for e in errs]
        report.write_text('\n'.join(lines)+'\n'); print(report.read_text(),end='',file=sys.stderr); return 60
    lines.insert(0,'HTTPS_VERIFY=OK'); report.write_text('\n'.join(lines)+'\n'); print(report.read_text(),end=''); return 0
if __name__=='__main__': raise SystemExit(main())
