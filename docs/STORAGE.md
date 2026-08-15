# OURFW Storage

EC220 Storage partition stays stock: 128 KiB (`0x20000`). We do not repartition flash.

Padavan stores `/etc/storage` compressed. OURFW defaults are generated deterministically with sorted paths, uid/gid 0 and fixed mtime; runtime `/tmp` data is excluded.

v0.5 mutable defaults are ~28 KiB compressed before user data. Large binaries remain in SquashFS BUILTINS; Storage is reserved for scripts/config/rules/UI.

Unconfirmed component/WebUI rollback copies live only in `/tmp/ourfw/update-history`; they are not written into the 128 KiB Storage. A reboot before confirmation naturally reloads the previous flash state.
