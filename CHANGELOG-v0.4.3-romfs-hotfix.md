# v0.4.3 — real-build ROMFS hotfix

The first successful MIPS compile exposed a Padavan build-system trap: `user/ourfw`
failed while copying `defaults.tar.bz2` because `/usr/share/ourfw` did not exist, but
the outer Padavan user build continued and still produced a firmware image.

Fixes:
- create `$(ROMFSDIR)/usr/share/ourfw` before installing the immutable defaults archive;
- add `ci/verify-built-romfs.sh` after every firmware build;
- reject any recursive `make[...] *** Error N` found in build.log;
- assert loader/defaults/fallback WebUI/httpd API/SSH/WG/AWG/nfqws/zapret/sha256sum;
- assert WireGuard, AmneziaWG, NFQUEUE and IPv6 mangle kernel modules;
- assert OURFW autostart and required content inside defaults.tar.bz2;
- publish `ROMFS-VERIFY.txt` with successful artifacts;
- bump produced image/artifact label to v0.4.3.

v0.4.2 firmware MUST NOT be flashed because mutable OURFW defaults were absent from ROMFS.
