# Upstream reference

Base: `hadzhioglu/padavan-ng`.

Pinned commit for OURFW v0.4:
`0e6caa2749a8814345c8a0d496a2fde2e6746a7d`

Important paths:

- `trunk/configs/boards/TPLINK/TL_EC220_G5-V2/`
- `trunk/configs/boards/busybox.config`
- `trunk/user/httpd/`
- `trunk/user/Makefile`
- existing `autostart.sh` under `trunk/user`

Our `build.config` is the source of truth for the firmware feature set; we do not copy a floating current template during a release build.
