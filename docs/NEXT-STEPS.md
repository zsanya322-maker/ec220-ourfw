# Следующие шаги после v0.6

1. Получить зелёный real MIPS CI v0.6.0 и независимо разобрать Artifact.
2. Проверить запас Firmware partition после OpenSSL/OpenVPN/SFTP/ZRAM/curl.
3. Только после аудита Artifact — первый TFTP hardware boot.
4. На железе сначала проверить базу: LAN/WAN, 2.4/5 GHz, Padavan WebUI, OURFW WebUI, SSH/SCP/SFTP, HTTPS, Storage save/reboot.
5. Затем по отдельности: WG, AWG, OpenVPN, Smart Routing, failover, nfqws, AdBlock, ZRAM, InetDetect/Watchdog/rollback.
6. Снять RAM/CPU/throughput/bufferbloat. CAKE/FQ-CoDel рассматривать только после этих измерений.
7. После стабильного boot UI/модули можно улучшать mutable-пакетами без TFTP.
