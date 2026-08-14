# Padavan integration package

This directory is copied automatically to `trunk/user/ourfw` by `tools/apply-to-padavan.py`; do not copy it manually in the normal build flow.

`build/make-defaults.sh` creates:

- `files/ourfw-loader.sh` — immutable rescue loader;
- `files/defaults.tar.bz2` — seed for `/etc/storage/ourfw`;
- `files/www/` — immutable WebUI fallback/mountpoint.

The integrator also adds the package to `trunk/user/Makefile`, hooks the existing Padavan autostart, adds the fixed OURFW API bridge, and enables required kernel/BusyBox capabilities.
