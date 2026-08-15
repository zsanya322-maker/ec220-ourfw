# После v0.5 one-shot source

1. Один CI tag-build.
2. Требовать `ROMFS_VERIFY=OK` и `IMAGE_VERIFY=OK`.
3. Скачать весь Artifact и повторно разобрать `.bin`/recovery/hashes.
4. Только после этого решать момент первой TFTP-заливки.
5. После первого железного теста: selective IPv6 routing, multi-VPN/failover и performance/CAKE tuning — если реально нужны.
