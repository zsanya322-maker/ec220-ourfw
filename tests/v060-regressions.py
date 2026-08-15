#!/usr/bin/env python3
from pathlib import Path
import re, sys
R=Path(__file__).resolve().parents[1]
errs=[]
def t(p): return (R/p).read_text(errors='replace')
def need(c,m):
    if not c: errs.append(m)

cfg=t('build.config'); vpn=t('ourfw/modules/vpn/apply.sh'); transfer=t('ourfw/runtime/ourfw-transfer.sh')
common=t('ourfw/runtime/ourfw-common.sh'); wd=t('ourfw/modules/watchdog/watchdog.sh'); wdev=t('ourfw/modules/watchdog/event.sh')
adb=t('ourfw/modules/adblock/update.sh')+t('ourfw/modules/adblock/apply.sh'); zram=t('ourfw/modules/zram/apply.sh')
ui=t('ourfw/www/index.asp')+t('ourfw/www/assets/ourfw.js'); img=t('ci/verify-built-image.py'); rom=t('ci/verify-built-romfs.sh')
wf=t('.github/workflows/build-ourfw.yml'); prep=t('ci/prepare-artifacts.sh')

for k in ('CONFIG_FIRMWARE_INCLUDE_HTTPS=y','CONFIG_FIRMWARE_INCLUDE_SFTP=y','CONFIG_FIRMWARE_INCLUDE_OPENVPN=y','CONFIG_FIRMWARE_INCLUDE_OPENSSL_EC=y','CONFIG_FIRMWARE_INCLUDE_OPENSSL_EXE=y','CONFIG_FIRMWARE_INCLUDE_ZRAM=y','CONFIG_FIRMWARE_INCLUDE_CURL=y'):
    need(k in cfg, f'missing v0.6 builtin: {k}')
for k in ('CONFIG_FIRMWARE_INCLUDE_SSWAN=y','CONFIG_FIRMWARE_INCLUDE_DNSCRYPT=y','CONFIG_FIRMWARE_INCLUDE_STUBBY=y','CONFIG_FIRMWARE_INCLUDE_DOH=y'):
    need(k not in cfg, f'unplanned heavy feature enabled: {k}')
need('VPN_FAILOVER_ENABLED' in vpn and 'vpn-override-type' in vpn and 'start_openvpn' in vpn and 'resolve6' in vpn and 'vpn-endpoint6' in vpn, 'OpenVPN/failover orchestration incomplete')
need('route-noexec' in vpn and 'script-security 0' in vpn and 'unsafe OpenVPN directive rejected' in vpn and 'unsupported OpenVPN inline block rejected' in vpn, 'OpenVPN safety restrictions missing')
need('AWG I1 too long' in vpn and 'MTU out of range' in vpn, 'WG/AWG validation regressed')
for x in ('openvpn-profile','openvpn-auth','adblock-config','adblock-sources','adblock-allow','adblock-deny','zram-config'):
    need(x in transfer, f'Web transfer target missing: {x}')
need('validate_openvpn' in transfer and 'validate_auth' in transfer and 'validate_urls' in transfer and "<connection>" in transfer, 'v0.6 upload validation missing')
need('/etc/storage/inet_state_script.sh' in common and 'link_internet' in common, 'Padavan InetDetect hook missing')
need('check_native_inetdetect' in wd and 'failover.sh' in wd, 'Watchdog does not consume InetDetect/failover')
need('rollback' in wdev and 'sleep 3' in wdev, 'InetDetect early rollback missing')
need('adblock-runtime.conf' in adb and 'mount -o bind' in adb and 'ADBLOCK_MAX_DOMAINS' in adb, 'RAM-backed AdBlock design missing')
need('curl -fsSL' in adb and '--max-filesize 2097152' in adb and 'https://*' in adb and 'http://*|https://*' not in adb, 'bounded HTTPS-only AdBlock updater missing')
need('/dev/zram0' in zram and 'comp_algorithm' in zram and 'swapon -p 32767 /dev/zram0' in zram and 'swapon -p 32767 -d' not in zram, 'ZRAM manager incomplete/uses nonportable swapon flags')
for token in ('OpenVPN профиль','AdBlock Lite','ZRAM','Internet Detect','HTTPS WebUI','SFTP'):
    need(token in ui, f'v0.6 UI token missing: {token}')
for token in ('/usr/sbin/openvpn','/usr/libexec/sftp-server','/usr/bin/openssl','zram.ko'):
    need(token in img or token.replace('/','',1) in rom or token in rom, f'final verifier does not require {token}')
need('curl' in img and 'curl' in rom, 'curl is not checked in final build')
need('OURFW_VERSION=$(cat ourfw/VERSION)' in wf and 'OURFW_VERSION=$(cat ourfw/VERSION)' in prep and '${OURFW_VERSION}' in wf and '${OURFW_VERSION}' in prep, 'CI artifact/report version is not derived from ourfw/VERSION')
if errs:
    for e in errs: print('ERROR:',e,file=sys.stderr)
    raise SystemExit(1)
print('V0.6 REGRESSIONS: OK')
