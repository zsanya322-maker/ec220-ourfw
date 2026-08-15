# Следующие шаги после v0.4-audit-fixed build-ready

1. Запустить включённый CI на exact commit `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`.
2. Получить `TL_EC220_G5-V2_OURFW-v0.4-audit-fixed-0e6caa2749.bin`, `tp_recovery.bin`, `SHA256SUMS.txt`, `BUILD-REPORT.txt`, `build.log`.
3. Проверить compile log и состав rootfs/kernel modules: wg, awg, nfqws, NFQUEUE, ipset, SFE, sha256sum, mount bind.
4. Разобрать полученный образ и сравнить geometry/header с известным рабочим EC220 Padavan `0e6caa2749`.
5. До flashing проверить размер и safety margin из BUILD-REPORT; не менять partition table.
6. Держать отдельно точный stock Дом.ру fallback.
7. Первая установка: TFTP recovery по LAN.
8. Первый аппаратный boot — сначала без VPN/nfqws: LAN/WAN, 2.4/5 GHz, switch, DHCP/DNS, SSH, WebUI, Storage save/reboot.
9. Затем по одному: OURFW WebUI/API -> rollback guard -> WG -> AWG -> Smart Routing -> nfqws -> DNS -> watchdog.
10. Только после стабильного теста включать browser component upload/editor. Whitelist API сохраняем; arbitrary shell over HTTP не добавляем.
11. После измерения CPU/RAM/throughput решить, нужен ли CAKE по умолчанию.
