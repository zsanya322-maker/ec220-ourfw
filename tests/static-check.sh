#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

find "$ROOT/ourfw" "$ROOT/bootstrap" "$ROOT/build" -type f -name '*.sh' | while IFS= read -r f; do
  sh -n "$f" || exit 20
done
find "$ROOT/ci" -type f -name '*.sh' | while IFS= read -r f; do
  bash -n "$f" || exit 20
done
python3 -m py_compile "$ROOT/tools/apply-to-padavan.py" "$ROOT/tools/verify-padavan-tree.py" "$ROOT/tools/inspect-images.py" "$ROOT/ci/verify-built-image.py" "$ROOT/tests/integration-mock.py" "$ROOT/tests/reference-recovery.py" "$ROOT/tests/audit-regressions.py" "$ROOT/tests/v050-regressions.py"
python3 "$ROOT/tests/integration-mock.py"
python3 "$ROOT/tests/audit-regressions.py"
python3 "$ROOT/tests/v050-regressions.py"
sh "$ROOT/tests/romfs-verifier-mock.sh"
bash "$ROOT/tests/runtime-mock.sh"
sh "$ROOT/build/make-defaults.sh" >/dev/null
sh "$ROOT/tools/storage-budget.sh"

# Mutable configuration is parsed as data, never sourced as shell.
if grep -R -nE '^[[:space:]]*\.[[:space:]]+.*config/|source[[:space:]].*config/' "$ROOT/ourfw"; then
  echo 'unsafe mutable config sourcing found' >&2; exit 21
fi

# The immutable API bridge must execute only the fixed mutable dispatcher.
if grep -nE 'get_cgi\("cmd"\)|SystemCmd|system\([^\n]*get_cgi' "$ROOT/tools/apply-to-padavan.py"; then
  echo 'generic web command bridge found' >&2; exit 22
fi
grep -q 'eval("/etc/storage/ourfw/runtime/ourfw-api.sh"' "$ROOT/tools/apply-to-padavan.py" || {
  echo 'fixed OURFW API dispatcher missing' >&2; exit 23;
}

# Keep OURFW independent from Padavan native WG policy-routing scripts.
if grep -R -nE '/usr/bin/(a?wgc)\.sh|[[:space:]](a?wgc)\.sh' "$ROOT/ourfw" --include='*.sh'; then
  echo 'OURFW must not call Padavan wgc/awgc orchestration' >&2; exit 24
fi
if grep -R -nE 'zapret\.sh[[:space:]]+status' "$ROOT/ourfw"; then
  echo 'stale zapret.sh status call found' >&2; exit 25
fi
if grep -nE '(^|[^A-Za-z0-9_])restart_dns([^A-Za-z0-9_]|$)' "$ROOT/ourfw/modules/dns/apply.sh"; then
  echo 'DNS apply must use restart_dhcpd, not restart_dns' >&2; exit 26
fi

# Smart-routing mark must use a mask so it can coexist with other marks.
grep -q 'fwmark "$FWMARK/$FWMASK"' "$ROOT/ourfw/modules/smart-routing/apply.sh" || {
  echo 'masked fwmark rule missing' >&2; exit 27;
}

# Build is pinned to the exact known-good Padavan source commit.
grep -q 'PADAVAN_COMMIT="0e6caa2749a8814345c8a0d496a2fde2e6746a7d"' "$ROOT/variables" || {
  echo 'Padavan commit is not pinned' >&2; exit 28;
}

# No accidental heavy packages in the v0.5 firmware config.
for k in CONFIG_FIRMWARE_INCLUDE_OPENVPN CONFIG_FIRMWARE_INCLUDE_SSWAN CONFIG_FIRMWARE_INCLUDE_HTTPS CONFIG_FIRMWARE_INCLUDE_SFTP CONFIG_FIRMWARE_INCLUDE_DNSCRYPT CONFIG_FIRMWARE_INCLUDE_STUBBY CONFIG_FIRMWARE_INCLUDE_DOH CONFIG_FIRMWARE_INCLUDE_ZRAM CONFIG_FIRMWARE_INCLUDE_LUA; do
  if grep -q "^${k}=y$" "$ROOT/build.config"; then echo "heavy feature unexpectedly enabled: $k" >&2; exit 29; fi
done
for k in CONFIG_FIRMWARE_INCLUDE_WIREGUARD CONFIG_FIRMWARE_INCLUDE_AMNEZIAWG CONFIG_FIRMWARE_INCLUDE_NFQWS CONFIG_FIRMWARE_INCLUDE_IPSET CONFIG_FIRMWARE_INCLUDE_DROPBEAR; do
  grep -q "^${k}=y$" "$ROOT/build.config" || { echo "required feature missing: $k" >&2; exit 30; }
done


# Generated runtime state must stay in /tmp; 128 KiB persistent Storage is precious.
grep -q 'GEN="$STATE/generated"' "$ROOT/ourfw/runtime/ourfw-common.sh" || {
  echo 'generated files are not volatile' >&2; exit 31;
}
# Default Smart Routing must prevent IPv6 from silently bypassing an IPv4 VPN policy.
grep -q '^IPV6_POLICY=block$' "$ROOT/ourfw/config/routing.conf" || {
  echo 'IPv6 no-leak policy missing' >&2; exit 32;
}
grep -q 'OURFW6_FWD' "$ROOT/ourfw/modules/smart-routing/apply.sh" && grep -q 'OURFW6_OUT' "$ROOT/ourfw/modules/smart-routing/apply.sh" || {
  echo 'IPv6 leak guard chains missing' >&2; exit 33;
}

# Real-build regression: immutable OURFW package must create its plain-file parent,
# and CI must inspect the built ROMFS instead of trusting Padavan's outer make loop.
grep -q 'mkdir -p $(ROMFSDIR)/usr/share/ourfw' "$ROOT/integration/padavan-user-ourfw/Makefile" || {
  echo 'OURFW ROMFS parent mkdir missing' >&2; exit 34;
}
[ -f "$ROOT/ci/verify-built-romfs.sh" ] || { echo 'built-ROMFS verifier missing' >&2; exit 35; }
grep -q 'Verify built ROMFS' "$ROOT/.github/workflows/build-ourfw.yml" || {
  echo 'workflow does not verify built ROMFS' >&2; exit 36;
}

# v0.5 one-shot WebUI / transfer layer.
grep -q 'CONFIG_BASE64' "$ROOT/tools/apply-to-padavan.py" || { echo 'BusyBox base64 is not enabled' >&2; exit 37; }
for f in "$ROOT/ourfw/runtime/ourfw-transfer.sh" "$ROOT/ourfw/runtime/ourfw-backup.sh" "$ROOT/ourfw/runtime/ourfw-ui.sh"; do [ -f "$f" ] || { echo "missing runtime source $f" >&2; exit 38; }; done
grep -q "find.*-name '\*.sh'.*chmod 0755" "$ROOT/bootstrap/ourfw-loader.sh" || { echo 'loader does not normalize mutable script permissions' >&2; exit 38; }
grep -q 'ourfw_api_blob_ok' "$ROOT/tools/apply-to-padavan.py" || { echo 'chunk-safe immutable bridge missing' >&2; exit 39; }
grep -q 'section-commit' "$ROOT/ourfw/runtime/ourfw-transfer.sh" || { echo 'atomic WebUI section commit missing' >&2; exit 40; }
grep -q 'OURFW_CANDIDATE_PATCH' "$ROOT/ourfw/runtime/ourfw-apply.sh" || { echo 'candidate patch transaction missing' >&2; exit 41; }
grep -q 'romfs_exists' "$ROOT/ci/verify-built-romfs.sh" && grep -q 'readlink' "$ROOT/ci/verify-built-romfs.sh" || { echo 'ROMFS verifier is not symlink-aware' >&2; exit 42; }
for token in 'Backup Center' 'vpn-profile' 'nfqws-strategy' 'dns-servers' 'watchdog-config' 'component-package' 'diagnostics-export'; do
  grep -R -q "$token" "$ROOT/ourfw/www" "$ROOT/ourfw/runtime" || { echo "WebUI feature missing: $token" >&2; exit 43; }
done
if command -v node >/dev/null 2>&1; then node --check "$ROOT/ourfw/www/assets/ourfw.js"; fi

echo 'STATIC CHECKS: OK'
