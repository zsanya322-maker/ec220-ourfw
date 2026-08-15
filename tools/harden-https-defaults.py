#!/usr/bin/env python3
"""Harden Padavan's HTTPS certificate defaults for OURFW.

The pinned upstream EC220 build offers RSA-1024 as the first/default choice and
https-cert.sh also falls back to 1024 bits. Keep RSA-1024 available as an
explicit legacy choice, but make RSA-2048 the default everywhere.
"""
from pathlib import Path
import argparse, sys


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    s = path.read_text(errors="replace")
    if new in s:
        return
    n = s.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor in {path}, got {n}")
    path.write_text(s.replace(old, new, 1))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("padavan_tree")
    a = ap.parse_args()
    trunk = Path(a.padavan_tree).resolve() / "trunk"
    cert = trunk / "user/httpd/https-cert.sh"
    ui = trunk / "user/www/n56u_ribbon_fixed/Advanced_Services_Content.asp"
    if not cert.is_file() or not ui.is_file():
        raise RuntimeError(f"HTTPS hardening paths missing: cert={cert.is_file()} ui={ui.is_file()}")

    replace_once(cert, "RSA_BITS=1024", "RSA_BITS=2048", "HTTPS cert default")
    replace_once(
        ui,
        '                                                    <option value="1024">RSA 1024 (*)</option>\n'
        '                                                    <option value="2048">RSA 2048</option>',
        '                                                    <option value="1024">RSA 1024</option>\n'
        '                                                    <option value="2048" selected="selected">RSA 2048 (*)</option>',
        "HTTPS WebUI RSA default",
    )

    cs = cert.read_text(errors="replace")
    us = ui.read_text(errors="replace")
    if "RSA_BITS=2048" not in cs or 'value="2048" selected="selected">RSA 2048 (*)' not in us:
        raise RuntimeError("HTTPS hardening postcondition failed")
    print("HTTPS HARDENING: RSA-2048 default enforced")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print("ERROR:", e, file=sys.stderr)
        raise SystemExit(1)
