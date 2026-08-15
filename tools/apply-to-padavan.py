#!/usr/bin/env python3
"""Apply OURFW v0.5.0-one-shot to an exact hadzhioglu/padavan-ng checkout.

Design goals:
- do not modify board flash layout or radio data
- keep immutable changes minimal
- keep WebUI files and policy logic mutable in /etc/storage/ourfw
- fail closed if expected upstream anchors are missing
"""
from pathlib import Path
import argparse, shutil, re, subprocess, sys

HERE = Path(__file__).resolve().parents[1]
PINNED = "0e6caa2749a8814345c8a0d496a2fde2e6746a7d"


def verify_git_commit(root: Path):
    """Reject a git checkout at any commit except the known-good EC220 base.

    Exported source trees have no .git metadata and are allowed; the separate
    verifier/build wrapper requires an explicit source-commit assertion there.
    """
    if not (root / ".git").exists():
        return
    try:
        rev = subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception as exc:
        raise RuntimeError(f"cannot determine upstream git commit: {exc}")
    if rev != PINNED:
        raise RuntimeError(f"upstream commit mismatch: {rev} != {PINNED}")


def insert_user_makefile(umk: Path):
    """Insert OURFW immediately after the existing scripts directory entry.

    Whitespace differs between Padavan forks, so match semantics rather than a
    tab-exact line. The marker makes repeated integration idempotent.
    """
    s = umk.read_text(errors="replace")
    marker = "# OURFW_USERDIR_V04"
    if marker in s:
        return
    pat = re.compile(r"^(?P<indent>\s*)dir_y\s*\+=\s*scripts\s*$", re.M)
    matches = list(pat.finditer(s))
    if len(matches) != 1:
        raise RuntimeError(f"user Makefile: expected exactly one scripts entry in {umk}, got {len(matches)}")
    m = matches[0]
    block = (
        m.group(0) + "\n"
        + marker + "\n"
        + "ifneq (,$(findstring TL_EC220_G5-V2,$(CONFIG_FIRMWARE_PRODUCT_ID)))\n"
        + m.group("indent") + "dir_y\t\t\t\t\t\t+= ourfw\n"
        + "endif"
    )
    umk.write_text(s[:m.start()] + block + s[m.end():])


def set_kconfig(path: Path, key: str, value: str):
    s = path.read_text(errors="replace")
    line = f"{key}={value}"
    pat = re.compile(rf'^(?:{re.escape(key)}=.*|#[ \t]*{re.escape(key)}(?:=.*|[ \t]+is[ \t]+not[ \t]+set))$', re.M)
    m = pat.search(s)
    if m:
        s = s[:m.start()] + line + s[m.end():]
    else:
        s += ("\n" if not s.endswith("\n") else "") + line + "\n"
    path.write_text(s)


def replace_once(path: Path, old: str, new: str, label: str):
    s = path.read_text(errors="replace")
    if new in s:
        return
    n = s.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor in {path}, got {n}")
    path.write_text(s.replace(old, new, 1))


def append_once(path: Path, marker: str, block: str):
    s = path.read_text(errors="replace")
    if marker in s:
        return
    if not s.endswith("\n"):
        s += "\n"
    path.write_text(s + block)


def locate_mime_source(httpd_dir: Path) -> Path:
    hits = []
    for p in httpd_dir.glob("*.c"):
        txt = p.read_text(errors="replace")
        if "struct mime_handler mime_handlers[]" in txt:
            hits.append(p)
    if len(hits) != 1:
        raise RuntimeError(f"httpd mime_handlers source: expected 1 file, found {len(hits)}: {hits}")
    return hits[0]


def patch_http_api(src: Path):
    s = src.read_text(errors="replace")
    if "ourfw_api.cgi" in s and "do_ourfw_api" in s:
        return
    required = ["struct mime_handler mime_handlers[] = {", "get_cgi(", "do_html_apply_post"]
    missing = [x for x in required if x not in s]
    if missing:
        raise RuntimeError(f"OURFW API anchors missing in {src}: {missing}")

    api = r'''
/* OURFW: authenticated fixed bridge to mutable dispatcher.
 * Non-status operations require a per-boot 256-bit CSRF token. No HTTP value
 * becomes shell syntax; only fixed argv are passed to the mutable dispatcher. */
static int
ourfw_api_token_ok(const char *s)
{
    const unsigned char *p = (const unsigned char *)s;
    size_t n = 0;
    if (!s) return 1;
    while (*p) {
        unsigned char c = *p;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-' ||
              c == '.' || c == ':')) return 0;
        if (++n > 64) return 0;
        ++p;
    }
    return 1;
}

static int
ourfw_api_blob_ok(const char *s)
{
    const unsigned char *p = (const unsigned char *)s;
    size_t n = 0;
    if (!s || !*s) return 0;
    while (*p) {
        unsigned char c = *p;
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
              (c >= '0' && c <= '9') || c == '_' || c == '-')) return 0;
        if (++n > 1024) return 0;
        ++p;
    }
    return 1;
}

static int
ourfw_api_streq(const char *a, const char *b)
{
    if (!a || !b) return 0;
    while (*a && *b && *a == *b) { ++a; ++b; }
    return *a == '\0' && *b == '\0';
}

static int
ourfw_api_csrf_ok(const char *action, const char *supplied)
{
    FILE *fp; char expected[80]; size_t i = 0; int c;
    if (ourfw_api_streq(action, "status")) return 1;
    if (!supplied || !*supplied || !ourfw_api_token_ok(supplied)) return 0;
    fp = fopen("/tmp/ourfw-csrf.token", "r");
    if (!fp) return 0;
    while (i + 1 < sizeof(expected) && (c = fgetc(fp)) != EOF && c != '\n' && c != '\r')
        expected[i++] = (char)c;
    expected[i] = '\0'; fclose(fp);
    if (i != 64) return 0;
    return ourfw_api_streq(expected, supplied);
}

static void
ourfw_api_emit(FILE *stream)
{
    FILE *fp; char buf[512]; size_t n;
    fp = fopen("/tmp/ourfw-api.json", "r");
    if (!fp) { fputs("{\"ok\":false,\"error\":\"no response\"}\n", stream); return; }
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) fwrite(buf, 1, n, stream);
    fclose(fp);
}

static void
do_ourfw_api(const char *url, FILE *stream)
{
    const char *action = get_cgi("action");
    const char *p1 = get_cgi("p1");
    const char *p2 = get_cgi("p2");
    const char *csrf = get_cgi("csrf");
    int rc;
    (void)url;
    if (!action || !*action) action = "status";
    if (!p1) p1 = "";
    if (!p2) p2 = "";
    if (!ourfw_api_token_ok(action) || !ourfw_api_token_ok(p1) ||
        (ourfw_api_streq(action, "file-chunk") ? !ourfw_api_blob_ok(p2) : !ourfw_api_token_ok(p2))) {
        fputs("{\"ok\":false,\"error\":\"invalid request\"}\n", stream); return;
    }
    if (!ourfw_api_csrf_ok(action, csrf)) {
        fputs("{\"ok\":false,\"error\":\"csrf\"}\n", stream); return;
    }
    remove("/tmp/ourfw-api.json");
    rc = eval("/etc/storage/ourfw/runtime/ourfw-api.sh", (char *)action, (char *)p1, (char *)p2);
    if (rc != 0) fprintf(stderr, "OURFW API dispatcher rc=%d\n", rc);
    ourfw_api_emit(stream);
}

'''
    anchor = "struct mime_handler mime_handlers[] = {\n"
    s = s.replace(anchor, api + anchor + '\t{ "ourfw_api.cgi*", "application/json", no_cache_IE, do_html_apply_post, do_ourfw_api, 1 },\n', 1)
    src.write_text(s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("padavan_tree")
    args = ap.parse_args()
    root = Path(args.padavan_tree).resolve()
    trunk = root / "trunk"
    cfg = trunk / ".config"
    kernel = trunk / "configs/boards/TPLINK/TL_EC220_G5-V2/kernel-3.4.x.config"
    busy = trunk / "configs/boards/busybox.config"
    umk = trunk / "user/Makefile"
    httpd_dir = trunk / "user/httpd"

    for p in [cfg, kernel, busy, umk, httpd_dir]:
        if not p.exists():
            raise RuntimeError(f"missing expected upstream path: {p}")

    c = cfg.read_text(errors="replace")
    if 'CONFIG_VENDOR=TPLINK' not in c or 'CONFIG_FIRMWARE_PRODUCT_ID="TL_EC220_G5-V2"' not in c:
        raise RuntimeError("trunk/.config is not our EC220-G5 v2 build config")

    verify_git_commit(root)

    # Build immutable rescue payload from the exact mutable source tree.
    subprocess.run(["sh", str(HERE / "build/make-defaults.sh")], check=True)
    dst = trunk / "user/ourfw"
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(HERE / "integration/padavan-user-ourfw", dst)

    # Build OURFW package only for this target.
    insert_user_makefile(umk)

    # Start immutable loader from Padavan's existing autostart path instead of
    # changing rc.c. Locate the source defensively because forks move scripts.
    autostarts = [p for p in (trunk / "user").rglob("autostart.sh") if p.is_file()]
    if len(autostarts) != 1:
        raise RuntimeError(f"expected one autostart.sh source, found {autostarts}")
    append_once(
        autostarts[0],
        "# OURFW_LOADER_V04",
        "\n# OURFW_LOADER_V04\n[ -x /usr/bin/ourfw-loader.sh ] && /usr/bin/ourfw-loader.sh >/dev/null 2>&1 &\n",
    )

    # Tiny authenticated API bridge. UI files themselves are overlaid later via
    # bind mount, so httpd static file handling remains untouched.
    patch_http_api(locate_mime_source(httpd_dir))

    # Kernel / BusyBox capabilities required by mutable OURFW logic.
    for k, v in [
        ("CONFIG_NETFILTER_NETLINK_QUEUE", "m"),
        ("CONFIG_NETFILTER_XT_TARGET_NFQUEUE", "m"),
        ("CONFIG_IP_NF_QUEUE", "m"),
        ("CONFIG_IP6_NF_FILTER", "y"),
        ("CONFIG_IP6_NF_TARGET_REJECT", "y"),
        ("CONFIG_IP6_NF_MANGLE", "m"),
        ("CONFIG_BRIDGE_NF_EBTABLES", "m"),
    ]:
        set_kconfig(kernel, k, v)
    for k, v in [
        ("CONFIG_SHA256SUM", "y"),
        ("CONFIG_BASE64", "y"),
        ("CONFIG_MOUNT", "y"),
        ("CONFIG_FEATURE_MOUNT_FLAGS", "y"),
    ]:
        set_kconfig(busy, k, v)

    print("OURFW v0.5 integration applied successfully")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("ERROR:", e, file=sys.stderr)
        sys.exit(1)
