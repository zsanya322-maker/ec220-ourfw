# v0.5.1 CI hotfix — BusyBox base64 path

No firmware runtime/feature changes.

The real Padavan ROMFS installs BusyBox base64 as:
`/bin/base64 -> busybox`

v0.5.0 verification incorrectly required `/usr/bin/base64`, causing a false CI failure
after an otherwise successful firmware build.

Changed:
- ROMFS verifier now requires `bin/base64`.
- Final-image verifier now requires `/bin/base64`.
- v0.5 regression test updated to the real Padavan path.
- ROMFS verifier mock now mirrors `/bin/busybox` + `/bin/base64`.

The v0.5.0 failure artifact firmware was independently inspected with the corrected
final-image verifier and passed:
IMAGE_VERIFY=OK
SHA256=5ec11505b30ad0ca14c7cef13616c40b3d5bc1d6216b9976b2403ee723cedff5
IMAGE_BYTES=4456452
