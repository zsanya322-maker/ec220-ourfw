#!/usr/bin/env python3
from pathlib import Path
import argparse, re, subprocess, sys

PINNED = "0e6caa2749a8814345c8a0d496a2fde2e6746a7d"

def has(path: Path, key: str, value: str):
    return re.search(rf'^{re.escape(key)}={re.escape(value)}$', path.read_text(errors='replace'), re.M) is not None

def need(cond, msg, errors):
    if not cond: errors.append(msg)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('padavan_tree'); a=ap.parse_args()
    root=Path(a.padavan_tree).resolve(); t=root/'trunk'
    cfg=t/'.config'; kernel=t/'configs/boards/TPLINK/TL_EC220_G5-V2/kernel-3.4.x.config'; busy=t/'configs/boards/busybox.config'
    umk=t/'user/Makefile'; ourfw=t/'user/ourfw'; httpd=t/'user/httpd'
    errors=[]
    for p in [cfg,kernel,busy,umk,ourfw,httpd]: need(p.exists(), f'missing {p}', errors)
    if errors:
        print('\n'.join('ERROR: '+e for e in errors), file=sys.stderr); return 1

    # If this is a git checkout, verify the known-good source commit.
    try:
        rev=subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'], text=True, stderr=subprocess.DEVNULL).strip()
        need(rev == PINNED, f'upstream commit mismatch: {rev} != {PINNED}', errors)
    except Exception:
        pass

    need(has(cfg,'CONFIG_VENDOR','TPLINK'), 'wrong vendor', errors)
    need(has(cfg,'CONFIG_PRODUCT','MT7620'), 'wrong SoC target', errors)
    need(has(cfg,'CONFIG_FIRMWARE_PRODUCT_ID','"TL_EC220_G5-V2"'), 'wrong EC220 product id', errors)
    for k in ['CONFIG_FIRMWARE_ENABLE_IPV6','CONFIG_FIRMWARE_INCLUDE_IPSET','CONFIG_FIRMWARE_INCLUDE_SHORTCUT_FE','CONFIG_FIRMWARE_INCLUDE_DROPBEAR','CONFIG_FIRMWARE_INCLUDE_WIREGUARD','CONFIG_FIRMWARE_INCLUDE_AMNEZIAWG','CONFIG_FIRMWARE_INCLUDE_NFQWS','CONFIG_CC_OPTIMIZE_FOR_SIZE']:
        need(has(cfg,k,'y'), f'{k} not enabled', errors)
    for k in ['CONFIG_NETFILTER_NETLINK_QUEUE','CONFIG_NETFILTER_XT_TARGET_NFQUEUE','CONFIG_IP_NF_QUEUE']:
        need(has(kernel,k,'m'), f'{k} != m', errors)
    for k in ['CONFIG_SHA256SUM','CONFIG_BASE64','CONFIG_MOUNT','CONFIG_FEATURE_MOUNT_FLAGS']:
        need(has(busy,k,'y'), f'BusyBox {k} missing', errors)
    need('+= ourfw' in umk.read_text(errors='replace'), 'OURFW user Makefile entry missing', errors)
    auto=[]
    for p in (t/'user').rglob('autostart.sh'):
        if p.is_file() and 'OURFW_LOADER_V04' in p.read_text(errors='replace'): auto.append(p)
    need(len(auto)==1, f'OURFW autostart hook count={len(auto)}', errors)
    api_hits=[]
    for p in httpd.glob('*.c'):
        txt=p.read_text(errors='replace')
        if 'ourfw_api.cgi' in txt and 'do_ourfw_api' in txt: api_hits.append(p)
    need(len(api_hits)==1, f'OURFW API bridge count={len(api_hits)}', errors)
    if api_hits:
        at=api_hits[0].read_text(errors='replace')
        need('ourfw_api_csrf_ok' in at and 'get_cgi("csrf")' in at, 'OURFW CSRF bridge missing', errors)
        need('ourfw_api_blob_ok' in at and '1024' in at, 'OURFW chunk bridge missing', errors)
    need((ourfw/'files/ourfw-loader.sh').is_file(), 'immutable loader payload missing', errors)
    need((ourfw/'files/defaults.tar.bz2').is_file(), 'OURFW defaults archive missing', errors)
    need((ourfw/'files/www/index.asp').is_file(), 'immutable WebUI fallback missing', errors)
    if errors:
        print('\n'.join('ERROR: '+e for e in errors), file=sys.stderr); return 1
    print('PADAVAN TREE VERIFY: OK')
    return 0

if __name__=='__main__': raise SystemExit(main())
