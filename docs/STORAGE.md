# OURFW Storage

EC220 Storage partition stays stock: 128 KiB (`0x20000`). We do not repartition flash.

Padavan stores `/etc/storage` compressed. OURFW defaults are generated deterministically with sorted paths, uid/gid 0 and fixed mtime; runtime `/tmp` data is excluded.

v0.6 mutable defaults are ~36 KiB compressed before user data (~27% of Storage). Large binaries (OpenSSL/OpenVPN/SFTP/WG/AWG/nfqws) remain in SquashFS BUILTINS. AdBlock's generated domain config is RAM-only; only its small settings/source/allow/deny files live in Storage.

Unconfirmed config/module/WebUI rollback copies live only in `/tmp/ourfw`; they are not committed into the 128 KiB Storage until confirmation. A reboot before confirmation naturally reloads the previous flash state.
