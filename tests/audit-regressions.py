#!/usr/bin/env python3
from pathlib import Path
import hashlib, subprocess, tempfile, tarfile, bz2, io, re, shutil
R=Path(__file__).resolve().parents[1]

def must(cond,msg):
    if not cond: raise AssertionError(msg)

def txt(rel): return (R/rel).read_text(errors='replace')

# 1-2 exact partition and exact image name
pa=txt('ci/prepare-artifacts.sh')
must('expected_partition_max=$((0x780000))' in pa, 'firmware partition must be 0x780000')
must('TL_EC220_G5-V2_3.4.3.9L-102-${short}.bin' in pa, 'exact build image selection missing')
must("-printf '%T@" not in pa and 'sort -n | tail -1' not in pa, 'mtime image selection remains')
# 3 portable sh invocation
ap=txt('tools/apply-to-padavan.py')
must('subprocess.run(["sh", str(HERE / "build/make-defaults.sh")], check=True)' in ap, 'make-defaults lacks explicit sh')
# 4 updater overlays and preserves required hooks
up=txt('ourfw/runtime/ourfw-update.sh')
a=up.index('cp -a "$DEST/." "$NEW/"'); b=up.index('cp -a "$STAGE/payload/." "$NEW/"')
must(a < b, 'payload not overlaid on existing module')
must('[ -x "$NEW/apply.sh" ] && [ -x "$NEW/start.sh" ]' in up, 'required module hooks not enforced')
for f in ['apply.sh','start.sh']:
    must((R/'packages/example/payload'/f).exists(), f'example missing {f}')
# 5 DNS path is persistent, loader creates it before early exits
dns=txt('ourfw/modules/dns/apply.sh'); loader=txt('bootstrap/ourfw-loader.sh')
must('OUT="$OURFW/dnsmasq-ourfw.conf"' in dns and '/tmp/ourfw/generated' not in dns, 'dnsmasq include remains volatile')
must('ensure_dns_safe' in loader and loader.index('ensure_dns_safe || true') < loader.index('[ -e "$DISABLE" ]'), 'loader DNS safety happens too late')
must((R/'ourfw/dnsmasq-ourfw.conf').exists(), 'persistent empty dns include not seeded')
# 6 CSRF token
must('ourfw_api_csrf_ok' in ap and 'get_cgi("csrf")' in ap, 'C CSRF enforcement missing')
js=txt('ourfw/www/assets/ourfw.js'); must("body.set('csrf',csrf)" in js and "method==='POST'" in js, 'WebUI does not attach CSRF to POST')
must('/tmp/ourfw-csrf.token' in loader, 'per-boot CSRF generation missing')
# 7 IPv6 no leak gating, prepend, output guard
sr=txt('ourfw/modules/smart-routing/apply.sh')
must('[ "$IPV6_POLICY" = "block" ] && [ "$VPN_ENABLED" = "1" ]' in sr, 'IPv6 guard not gated on VPN_ENABLED')
must('ip6tables -t filter -I FORWARD 1 -j OURFW6_FWD' in sr, 'IPv6 FORWARD guard not first')
must('ip6tables -t filter -I OUTPUT 1 -j OURFW6_OUT' in sr, 'IPv6 OUTPUT guard missing/not first')
must('vpn-endpoint6' in sr and (R/'docs/IPV6-POLICY.md').exists(), 'IPv6 endpoint/RA policy documentation missing')
# 8-9 guard before apply and atomic mkdir lock
apply=txt('ourfw/runtime/ourfw-apply.sh')
must(apply.index('rollback-guard.pid') < apply.index('apply_modules()'), 'rollback guard armed after apply starts')
common=txt('ourfw/runtime/ourfw-common.sh')
must('mkdir "$TXN_LOCK"' in common and 'txn_lock_acquire' in apply and 'txn_lock_acquire' in up, 'atomic transaction lock missing')
must('stale pending detected' in apply, 'stale pending recovery missing')
# 10 known-good hashes
refs=txt('reference/SHA256SUMS.txt')
for h in ['3f3a42989b6b63128f12a56927f59254b93bcae389259e59438af28b71de5e02','4803b92bf10c15b8a41bf3ed93b30584bd2af13ade4a647dd53e2c81dbb48d47']:
    must(h in refs, f'missing known-good hash {h}')
# 11 stock zapret arbitration
nf=txt('ourfw/modules/nfqws/apply.sh'); must('zapret_' in nf and '*autostart*' in nf and 'nvram set "$k=0"' in nf, 'stock zapret autostart not neutralized')
# 12 nonexistent symbol absent everywhere relevant
for rel in ['build.config','build/kernel-ec220-v0.4.fragment','build/ec220-v0.4.config.fragment','tools/apply-to-padavan.py']:
    must('CONFIG_IP6_NF_QUEUE' not in txt(rel), f'inert CONFIG_IP6_NF_QUEUE remains in {rel}')
# 13/16 deterministic defaults and no generated
md=txt('build/make-defaults.sh')
for token in ['--sort=name',"--mtime='@0'",'--owner=0','--group=0','--numeric-owner',"--exclude='./generated'"]:
    must(token in md, f'deterministic tar option missing: {token}')
must(not (R/'ourfw/generated').exists(), 'source generated directory remains')
with tempfile.TemporaryDirectory() as td:
    a=Path(td)/'a.bz2'; b=Path(td)/'b.bz2'
    subprocess.run(['sh',str(R/'build/make-defaults.sh'),str(a)],check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['sh',str(R/'build/make-defaults.sh'),str(b)],check=True,stdout=subprocess.DEVNULL)
    ha=hashlib.sha256(a.read_bytes()).hexdigest(); hb=hashlib.sha256(b.read_bytes()).hexdigest()
    must(ha==hb, f'defaults archive not reproducible: {ha} != {hb}')
    names=subprocess.check_output(['bash','-lc',f"bzcat {a} | tar -tf -"],text=True).splitlines()
    must(not any(n.rstrip('/').endswith('generated') for n in names), 'generated directory stored in defaults')
# 14 exact toolchain content pin
v=txt('variables'); wf=txt('.github/workflows/build-ourfw.yml')
must('PADAVAN_TOOLCHAIN_SHA256="cd6e8635765e706f8cfb6212a7d286be245f5e943c356006bff998845eeee3e7"' in v, 'toolchain SHA pin missing')
must('PADAVAN_TOOLCHAIN_SIZE="33636652"' in v, 'toolchain size pin missing')
must('sha256sum -c -' in wf and 'PADAVAN_TOOLCHAIN_SIZE' in wf, 'CI does not enforce toolchain pin')
# 15 actual tunnel liveness
wd=txt('ourfw/modules/watchdog/watchdog.sh')
must('ping -I "$VPN_INTERFACE"' in wd and 'latest-handshakes' in wd, 'watchdog still checks only interface existence')
print('AUDIT REGRESSIONS: OK')
