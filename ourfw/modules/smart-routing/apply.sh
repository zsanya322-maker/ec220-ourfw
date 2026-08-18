#!/bin/sh
# Dispatcher: native-AWG policy layer, legacy policy engine for other VPNs.
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
VPN_TYPE=wireguard
[ -f "$OURFW/config/vpn.conf" ] && load_conf "$OURFW/config/vpn.conf" || exit 1
if [ "$VPN_TYPE" = amneziawg ]; then
    exec "$OURFW/modules/smart-routing/apply-native-awg.sh"
fi
exec "$OURFW/modules/smart-routing/apply-other-vpn.sh"
