#!/bin/sh
# Re-apply split DNS routing for homelab services when on the home network.
# systemd-resolved can lose the DNS scope on the underlying link when a VPN
# reconnects with a catch-all (~.) routing domain. This restores it.
#
# Runs on every NM connection event. Probes the router to determine if the home
# network is reachable -- works regardless of interface type (wifi, ethernet,
# thunderbolt dock, etc.).
#
# Install: copy to /etc/NetworkManager/dispatcher.d/ and chmod 755

export LC_ALL=C

IFACE="$1"
DNS_SERVER="192.168.1.1"

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

# Probe the router's DNS with a short timeout
if dig +short +time=1 +tries=1 @"$DNS_SERVER" jellyfin.matthew-stratton.me A >/dev/null 2>&1; then
    # systemd-resolved turns a link's DefaultRoute implicitly off as soon as it
    # carries a route-only domain other than '~.'. With a VPN up that is
    # exactly right: homelab names come here, everything else goes to the
    # tunnel. With no VPN it would strand general DNS -- no link would be a
    # default route, and this build has no fallback servers (FallbackDNS= is
    # empty and none are compiled in), so every other lookup fails outright.
    #
    # So only surrender the default route when another link has claimed the
    # catch-all. Word splitting on $DOMAINS is intended.
    # '~homelab' is not optional. The router answers matthew-stratton.me names
    # with a CNAME to <ingress>.homelab, and resolved resolves that target as a
    # fresh query. Without a route for '.homelab' that second lookup goes to
    # the VPN, which NXDOMAINs it and negative-caches the result -- so homelab
    # names work only until something poisons the target, then fail at random.
    DOMAINS='~matthew-stratton.me ~homelab'
    if ! resolvectl domain 2>/dev/null | grep -v "($IFACE)" | grep -q '~\.'; then
        DOMAINS="$DOMAINS ~."
    fi

    resolvectl dns "$IFACE" "$DNS_SERVER"
    # shellcheck disable=SC2086
    resolvectl domain "$IFACE" $DOMAINS
fi

exit 0
