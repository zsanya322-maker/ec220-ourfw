# Upstream snapshot — OURFW v0.4 build-ready

Checked: 2026-08-15

- Repository: `https://gitlab.com/hadzhioglu/padavan-ng.git`
- Pinned build commit: `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`
- Target: `TPLINK / MT7620 / TL_EC220_G5-V2`
- This exact short hash appears in the user's known-good EC220 Padavan filename.

Integration intentionally depends on very few upstream anchors:

- `trunk/user/Makefile`: semantic `dir_y += scripts` anchor.
- exactly one `autostart.sh` under `trunk/user`.
- one httpd C file containing `struct mime_handler mime_handlers[]` + existing CGI/post helpers.
- EC220 board kernel config and common BusyBox config.

The patcher and verifier fail closed if these assumptions do not hold. CI builds from the exact commit; changing it requires re-running all checks and re-pinning.
