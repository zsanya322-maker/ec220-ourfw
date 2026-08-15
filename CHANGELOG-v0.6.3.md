# v0.6.3 — HTTPS certificate default hardening

Третий независимый аудит собранного `v0.6.2` artifact подтвердил recovery/flash-разметку, SquashFS, OpenVPN TUN, SFTP subsystem, CA bundle, ELF-зависимости и новые fail-closed механизмы v0.6.2. Найден один новый дефект: штатный Padavan HTTPS certificate generator по умолчанию создавал RSA-1024 сертификат.

## Исправлено

- `https-cert.sh`: default RSA key size повышен с 1024 до 2048 бит.
- WebUI: RSA-2048 теперь явно выбран и помечен как default; RSA-1024 сохранён только как ручной legacy-вариант.
- Build integration применяет HTTPS hardening к pinned Padavan tree до MIPS-компиляции.

## Новые проверки

- Idempotent HTTPS hardening mock: повторное применение не дублирует/не ломает патч.
- Final-image HTTPS verifier читает готовый SquashFS `.bin` и требует RSA-2048 default уже внутри конечной прошивки.
- Final-image verifier одновременно проверяет наличие CA bundle и boot-time `/etc/ssl/cert.pem` link для curl/OpenSSL.
- `HTTPS-VERIFY.txt` включён в firmware artifact и failure diagnostics.

Все fail-closed routing/watchdog/DNS/rollback/updater исправления `v0.6.2` сохраняются без изменения. Padavan source/toolchain остаются pinned.
