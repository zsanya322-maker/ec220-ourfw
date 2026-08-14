#!/usr/bin/env python3
"""Validate a known-good EC220 Padavan web/recovery pair if paths are supplied."""
from pathlib import Path
import argparse, hashlib

PREFIX = 131072
KNOWN_WEB_SHA = "3f3a42989b6b63128f12a56927f59254b93bcae389259e59438af28b71de5e02"
KNOWN_REC_SHA = "4803b92bf10c15b8a41bf3ed93b30584bd2af13ade4a647dd53e2c81dbb48d47"


def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('web'); ap.add_argument('recovery'); a=ap.parse_args()
    web=Path(a.web); rec=Path(a.recovery)
    wb=web.read_bytes(); rb=rec.read_bytes()
    assert len(rb) == len(wb) + PREFIX, (len(wb), len(rb))
    assert rb[:PREFIX] == b'\0' * PREFIX
    assert rb[PREFIX:] == wb
    ws, rs = sha(web), sha(rec)
    print(f"web_size={len(wb)} web_sha256={ws}")
    print(f"recovery_size={len(rb)} recovery_sha256={rs}")
    if ws == KNOWN_WEB_SHA and rs == KNOWN_REC_SHA:
        print("REFERENCE RECOVERY: EXACT KNOWN-GOOD MATCH")
    else:
        print("REFERENCE RECOVERY: STRUCTURE OK (hash differs from recorded pair)")

if __name__=='__main__': main()
