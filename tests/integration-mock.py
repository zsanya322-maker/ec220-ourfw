#!/usr/bin/env python3
"""Exercise the OURFW Padavan integrator against a minimal upstream-shaped tree.

This is not a firmware compilation. It catches path/anchor/idempotency regressions
in our own patching logic before CI touches the real pinned Padavan checkout.
"""
from pathlib import Path
import shutil, subprocess, tempfile, sys

ROOT = Path(__file__).resolve().parents[1]
APPLY = ROOT / "tools/apply-to-padavan.py"
VERIFY = ROOT / "tools/verify-padavan-tree.py"


def write(p: Path, text: str):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def main():
    with tempfile.TemporaryDirectory(prefix="ourfw-padavan-mock-") as td:
        tree = Path(td) / "padavan-ng"
        trunk = tree / "trunk"
        shutil.copy2(ROOT / "build.config", trunk / ".config") if trunk.exists() else None
        trunk.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "build.config", trunk / ".config")

        write(trunk / "configs/boards/TPLINK/TL_EC220_G5-V2/kernel-3.4.x.config", "# CONFIG_NETFILTER_NETLINK_QUEUE is not set\n")
        write(trunk / "configs/boards/busybox.config", "# CONFIG_SHA256SUM is not set\n# CONFIG_MOUNT is not set\n# CONFIG_FEATURE_MOUNT_FLAGS is not set\n")
        write(trunk / "user/Makefile", "dir_y += shared\n\tdir_y     += scripts\ndir_y += httpd\n")
        write(trunk / "user/scripts/autostart.sh", "#!/bin/sh\necho base-start\n")
        write(trunk / "user/httpd/web_ex.c", r'''#include <stdio.h>
struct mime_handler { const char *pat; const char *mime; void *cache; void *input; void *output; int auth; };
static const char *get_cgi(const char *x) { return x; }
static void do_html_apply_post(void) {}
static void no_cache_IE(void) {}
static int eval(const char *p, ...) { (void)p; return 0; }
struct mime_handler mime_handlers[] = {
    { "apply.cgi*", "text/html", no_cache_IE, do_html_apply_post, 0, 1 },
};
''')

        # First application must succeed, and verifier must see all deltas.
        subprocess.run([sys.executable, str(APPLY), str(tree)], check=True)
        subprocess.run([sys.executable, str(VERIFY), str(tree)], check=True)

        # Second application must be idempotent: no duplicated bridge/hooks.
        subprocess.run([sys.executable, str(APPLY), str(tree)], check=True)
        subprocess.run([sys.executable, str(VERIFY), str(tree)], check=True)

        mk = (trunk / "user/Makefile").read_text()
        auto = (trunk / "user/scripts/autostart.sh").read_text()
        web = (trunk / "user/httpd/web_ex.c").read_text()
        assert mk.count("OURFW_USERDIR_V03") == 1
        assert auto.count("OURFW_LOADER_V03") == 1
        assert web.count('"ourfw_api.cgi*"') == 1
        assert "isalnum(" not in web and "access(" not in web and "unlink(" not in web
        assert 'remove("/tmp/ourfw-api.json")' in web

        # At least compile the generated bridge as ordinary C in the mock. The
        # real MIPS build remains the authoritative ABI check.
        if shutil.which("gcc"):
            subprocess.run(["gcc", "-fsyntax-only", str(trunk / "user/httpd/web_ex.c")], check=True)
        print("MOCK INTEGRATION: OK")


if __name__ == "__main__":
    main()
