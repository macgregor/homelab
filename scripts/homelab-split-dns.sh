#!/bin/sh
# Re-apply split DNS routing for homelab services when on the home network.
# systemd-resolved can lose the DNS scope on the underlying link when a VPN
# reconnects with a catch-all (~.) routing domain. This restores it.
#
# Runs on every NM connection event. Probes CoreDNS to determine if the home
# network is reachable -- works regardless of interface type (wifi, ethernet,
# thunderbolt dock, etc.).
#
# Install: copy to /etc/NetworkManager/dispatcher.d/ and chmod 755

export LC_ALL=C

IFACE="$1"
COREDNS="192.168.1.223"

# Skip loopback
[ "$IFACE" = "lo" ] && exit 0

# For VPN events, the interface is tun0 but the damage is to the underlying
# link. Find the physical interface that carries the default route.
case "$IFACE" in
    tun*)
        IFACE=$(ip -4 route show default | grep -v tun | awk '{print $5}' | head -1)
        [ -z "$IFACE" ] && exit 0
        ;;
esac

# Probe CoreDNS with a short timeout
if dig +short +time=1 +tries=1 @"$COREDNS" dns.matthew-stratton.me A >/dev/null 2>&1; then
    resolvectl dns "$IFACE" "$COREDNS"
    resolvectl domain "$IFACE" '~matthew-stratton.me'
fi

exit 0
