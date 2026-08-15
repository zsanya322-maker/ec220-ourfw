# Первый CI OURFW v0.6.0

После применения v0.6 overlay нужен один tag-build.

Успех означает, что зелёные все этапы:
- Static checks
- Integrate OURFW
- Build firmware
- Verify built ROMFS
- Validate and prepare artifacts
- Verify final firmware image
- Upload firmware

Artifact должен называться `EC220-G5-v2-OURFW-v0.6.0`.

В нём должны быть web `.bin`, `tp_recovery.bin`, `SHA256SUMS.txt`, `BUILD-REPORT.txt`, `ROMFS-VERIFY.txt`, `IMAGE-VERIFY.txt`, `build.log`, pinned commit/toolchain proof.

v0.6 verifier дополнительно требует в реальном ROMFS/final image OpenVPN, OpenSSL, HTTPS cert helper, SFTP server, curl и zram.ko, а в OURFW defaults — failover, AdBlock, ZRAM и новый WebUI.

Не прошивать роутер сразу после CI: сначала разобрать полученный Artifact и независимо сверить конечный `.bin` и recovery-инвариант.
