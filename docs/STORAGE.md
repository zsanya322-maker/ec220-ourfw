# Storage strategy

EC220 current target layout keeps:
- Bootloader 0x000000..0x01ffff
- Firmware   0x020000..0x79ffff
- Storage    0x7a0000..0x7bffff (128 KiB)
- Config     0x7c0000..0x7cffff
- Romfile    0x7d0000..0x7dffff
- Rom        0x7e0000..0x7effff
- Factory    0x7f0000..0x7fffff

v0.4 keeps this exactly.

Padavan mtd_storage packs `/etc/storage` to tar and compresses it using bzip2 -9 before writing. Therefore OURFW should favor highly compressible shell/JSON/text/HTML and avoid storing large already-compressed binaries.

A future EC220-specific 256 KiB Storage layout may be researched by shrinking Firmware by 128 KiB while preserving 0x7c0000+ regions, but it is NOT enabled until image geometry, updater, bootloader and recovery are all verified. Generic `pt_ralink_8m_bigstor.config` is NOT drop-in compatible with EC220 because its partition map is different.
