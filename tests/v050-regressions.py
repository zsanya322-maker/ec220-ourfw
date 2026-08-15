#!/usr/bin/env python3
from pathlib import Path
import re, sys
R=Path(__file__).resolve().parents[1]
errs=[]
def need(c,m):
    if not c: errs.append(m)
def text(p): return (R/p).read_text(errors='replace')

wf=text('.github/workflows/build-ourfw.yml')
rom=text('ci/verify-built-romfs.sh')
img=text('ci/verify-built-image.py')
app=text('tools/apply-to-padavan.py')
transfer=text('ourfw/runtime/ourfw-transfer.sh')
update=text('ourfw/runtime/ourfw-update.sh')
apply=text('ourfw/runtime/ourfw-apply.sh')
api=text('ourfw/runtime/ourfw-api.sh')
backup=text('ourfw/runtime/ourfw-backup.sh')
ui=text('ourfw/www/index.asp')
js=text('ourfw/www/assets/ourfw.js')

need('Verify final firmware image' in wf and 'verify-built-image.py' in wf, 'workflow does not inspect final firmware image')
need('IMAGE-VERIFY.txt' in wf, 'final image report is not uploaded')
need("romfs_exists" in rom and 'readlink' in rom, 'ROMFS symlink resolver missing')
need("'./runtime/ourfw-ui.sh'" in rom, 'ROMFS verifier does not require mutable UI helper')
need('/bin/base64' in img and 'ourfw_api.cgi' in img, 'final image verifier misses v0.5 immutable requirements')
need('ourfw-transfer.sh' in img and 'ourfw-backup.sh' in img and 'ourfw-ui.sh' in img, 'final image verifier misses mutable v0.5 runtime')
need('ourfw_api_blob_ok' in app and re.search(r'n > 1024',app), 'C bridge does not bound chunk size')
need('file-chunk' in app and 'ourfw_api_blob_ok(p2)' in app, 'file chunks are not routed through blob validator')
need('CONFIG_BASE64' in app, 'base64 applet is not enabled')
need('section-commit' in transfer and 'OURFW_CANDIDATE_PATCH' in apply, 'atomic multi-file editor transaction missing')
need('backup-export' in transfer and 'diagnostics-export' in transfer, 'browser export endpoints missing')
need('webui)' in update and 'ourfw-ui.sh' in update and 'TYPE' in update, 'independent WebUI component updater missing')
need('shell scripts are not allowed in webui packages' in update, 'WebUI package shell guard missing')
need('validate_archive' in backup and 'OURFW_CANDIDATE_BACKUP' in apply, 'backup restore transaction missing')
for action in ('file-get','file-begin','file-chunk','file-commit','file-stage','section-commit','backup-export','diagnostics-export'):
    need(action in api, f'mutable API action missing: {action}')
for token in ('Backup Center','component-package','vpn-profile','nfqws-strategy','dns-servers','watchdog-config'):
    need(token in ui or token in js, f'WebUI capability missing: {token}')
need("call({action:name,p1,p2},'POST')" in js, 'mutating generic UI actions are not POST')
need("body.set('csrf',csrf)" in js, 'WebUI does not attach CSRF token to POST')
need("i+=960" in js, 'browser upload chunks exceed intended safe size')
need('crypto.subtle' in js and '0x428a2f98' in js, 'HTTP-safe JS SHA256 fallback missing')
need('candidate_conf_set' in text('packages/example/payload/api.sh'), 'example module package bypasses candidate transaction')
need('Canonical staging copy' in text('build/make-defaults.sh') and "-name '*.sh'" in text('build/make-defaults.sh'), 'defaults generator is not mode-canonical across Windows/Linux')
need('baseline refused' in text('ourfw/runtime/ourfw-rollback.sh'), 'baseline can overwrite rollback point during pending transaction')
need('ourfw.disabled' in api, 'rescue disable flag does not block mutable WebUI operations')
need('$STATE/update-history' in update and '$OURFW/history/${MODULE}' not in update, 'component rollback history still wastes persistent Storage')

if errs:
    for e in errs: print('ERROR:',e,file=sys.stderr)
    raise SystemExit(1)
print('V0.5 REGRESSIONS: OK')
