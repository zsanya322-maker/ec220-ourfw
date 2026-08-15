#!/usr/bin/env python3
"""Enable the minimal stock Linux 3.4 TPROXY/socket pieces for EC220 research.

This helper is intentionally separate from the stable OURFW integrator until
hardware qualification proves the Hysteria2 TPROXY path is worth keeping.
"""
from pathlib import Path
import re, sys

EXPECTED = "configs/boards/TPLINK/TL_EC220_G5-V2/kernel-3.4.x.config"


def set_kconfig(path: Path, key: str, value: str) -> None:
    text = path.read_text(errors="replace")
    line = f"{key}={value}"
    pat = re.compile(
        rf"^(?:{re.escape(key)}=.*|#[ \t]*{re.escape(key)}(?:=.*|[ \t]+is[ \t]+not[ \t]+set))$",
        re.M,
    )
    m = pat.search(text)
    if m:
        text = text[: m.start()] + line + text[m.end() :]
    else:
        if text and not text.endswith("\n"):
            text += "\n"
        text += line + "\n"
    path.write_text(text)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: enable-tproxy.py PADAVAN_TRUNK", file=sys.stderr)
        return 2
    trunk = Path(sys.argv[1]).resolve()
    cfg = trunk / EXPECTED
    if not cfg.is_file():
        print(f"missing EC220 kernel config: {cfg}", file=sys.stderr)
        return 3

    # Both xt_TPROXY and xt_socket are hidden behind NETFILTER_ADVANCED in the
    # pinned Linux 3.4 Kconfig.  EC220's stock config keeps that menu disabled,
    # so merely appending the two module symbols is silently discarded by
    # olddefconfig.  Enable the shared prerequisite explicitly, then only the
    # two modules needed by the transparent Hysteria2 path.
    set_kconfig(cfg, "CONFIG_NETFILTER_ADVANCED", "y")
    set_kconfig(cfg, "CONFIG_NETFILTER_XT_TARGET_TPROXY", "m")
    set_kconfig(cfg, "CONFIG_NETFILTER_XT_MATCH_SOCKET", "m")

    final = cfg.read_text(errors="replace")
    for expected in (
        "CONFIG_NETFILTER_ADVANCED=y",
        "CONFIG_NETFILTER_XT_TARGET_TPROXY=m",
        "CONFIG_NETFILTER_XT_MATCH_SOCKET=m",
        "CONFIG_IP_MULTIPLE_TABLES=y",
    ):
        if expected not in final:
            print(f"TPROXY prerequisite/config missing after edit: {expected}", file=sys.stderr)
            return 4

    print("EC220 TPROXY research config enabled: NETFILTER_ADVANCED=y, xt_TPROXY=m, xt_socket=m")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
