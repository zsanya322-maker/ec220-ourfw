# Первый CI OURFW v0.5.0

Нужен один tag-build после применения v0.5 overlay.

Успех означает, что зелёные все этапы:
- Static checks
- Integrate OURFW
- Build firmware
- Verify built ROMFS
- Validate and prepare artifacts
- Verify final firmware image
- Upload firmware

Artifact: `EC220-G5-v2-OURFW-v0.5.0`.

В нём должны быть web `.bin`, `tp_recovery.bin`, `SHA256SUMS.txt`, `BUILD-REPORT.txt`, `ROMFS-VERIFY.txt`, `IMAGE-VERIFY.txt`, `build.log`, pinned commit/toolchain proof.

Не прошивать роутер сразу после CI: сначала разобрать полученный Artifact и сверить финальный образ.
