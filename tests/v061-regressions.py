#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
errs=[]
def t(p): return (R/p).read_text(errors='replace')
def need(c,m):
    if not c: errs.append(m)

ver=t('ourfw/VERSION').strip() if (R/'ourfw/VERSION').exists() else ''
apply=t('ourfw/modules/vpn/apply.sh')
hand=t('ourfw/modules/vpn/module-handoff.sh')
loader=t('bootstrap/ourfw-loader.sh')
backup=t('ourfw/runtime/ourfw-backup.sh') if (R/'ourfw/runtime/ourfw-backup.sh').exists() else ''
static=t('tests/static-check.sh') if (R/'tests/static-check.sh').exists() else ''
wf=t('.github/workflows/build-ourfw.yml') if (R/'.github/workflows/build-ourfw.yml').exists() else ''
payload=t('ci/verify-ourfw-payload.py') if (R/'ci/verify-ourfw-payload.py').exists() else ''
exp=t('ci/check-kernel-export-warnings.sh')

need(ver == 'v0.6.1', f'expected v0.6.1, got {ver!r}')
need('module-handoff.sh' in apply and 'WG/AWG kernel module handoff failed' in apply, 'VPN apply does not enforce WG/AWG module handoff')
need('"$MODPROBE" -r "$other"' in hand, 'handoff does not unload conflicting module')
need('module_loaded "$other" &&' in hand and 'module_loaded "$target" ||' in hand, 'handoff does not verify post-unload/post-load state')
need('OURFW_PROC_MODULES' in hand and 'OURFW_MODPROBE' in hand, 'handoff is not dynamically mockable')
need('old_if="$(cat "$STATE/vpn-interface"' in apply and 'remove_wg_iface "$VPN_INTERFACE"' in apply, 'custom/partial WG interface cleanup missing')
need('refresh_defaults_if_needed' in loader and 'defaults_version' in loader, 'firmware-to-mutable version refresh missing')
need('for d in config profiles rules' in loader and 'cp -a "$old/$d/." "$BASE/$d/"' in loader, 'firmware refresh does not preserve user data contract')
need('config profiles rules' in backup, 'backup/user-data contract changed unexpectedly')
need('mv "$BASE" "$old"' in loader and 'mv "$old" "$BASE"' in loader, 'firmware refresh rollback path missing')
need('v061-module-handoff.sh' in static and 'loader-upgrade-mock.sh' in static, 'new dynamic regressions are not wired into static checks')
need('Check kernel export warnings' in wf and 'MODULE-EXPORTS.txt' in wf, 'real MIPS CI does not gate/report duplicate kernel exports')
need('exported twice' in exp and 'UNEXPECTED=' in exp and 'WG_AWG_MUTUAL_EXCLUSION=ENFORCED' in exp, 'kernel export warning gate incomplete')
need("'./modules/vpn/module-handoff.sh'" in payload, 'final-image payload verifier does not require handoff helper in defaults')
need("b'refresh_defaults_if_needed'" in payload, 'final-image payload verifier does not require loader upgrade logic')
need("branches:\n      - main" in wf, 'main pushes do not trigger the real MIPS CI')

if errs:
    for e in errs: print('ERROR:',e,file=sys.stderr)
    raise SystemExit(1)
print('V0.6.1 REGRESSIONS: OK')
