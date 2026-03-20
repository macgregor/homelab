---
name: syncthing-hub
description: >
  Load this document when working with the Syncthing hub deployment, relay server,
  client configuration, or troubleshooting sync connectivity.
categories: [syncthing, networking, kubernetes]
tags: [syncthing, relay, file-sync, strelaysrv]
related_docs:
  - docs/appendix/syncthing.md
  - docs/04-networking.md
  - docs/05-security.md
  - docs/03-persistence.md
complexity: intermediate
---

# Syncthing Hub

A private Syncthing relay server and always-on sync node deployed on the k3s cluster. The hub serves two roles: a centralized sync point that ensures data propagates between devices even when they're not online simultaneously, and a private relay that eliminates dependence on public relay pools.

For Syncthing protocol and technology details, see [Syncthing Appendix](appendix/syncthing.md).

## Architecture

Single pod with two containers in namespace `syncthing-relay`:

| Container | Image | Role | Ports |
|-----------|-------|------|-------|
| `syncthing` | `syncthing/syncthing` | Always-on sync node (hub) | 8384 (GUI), 22000 (sync) |
| `relaysrv` | `ghcr.io/syncthing/relaysrv` | Private relay server | 22067 (relay data), 22070 (status) |

Both containers share a single 50 GB iSCSI volume (LUN 6) with `subPath` isolation (`syncthing/` and `relay-keys/`). The pod runs with `securityContext.fsGroup: 1000` to match the Syncthing image's UID.

## Networking

### Services

| Service | Type | Address | Ports |
|---------|------|---------|-------|
| `syncthing-relay-lan` | LoadBalancer | `192.168.1.233` | 22067/TCP (relay), 22000/TCP (sync), 21027/UDP (discovery), 22070/TCP (relay status) |
| `syncthing-relay` | ClusterIP | (internal) | 8384/TCP (GUI) |
| Ingress | nginx-internal | `syncthing.matthew-stratton.me` | HTTPS (GUI) |

### WAN Exposure

Only port 22067 (relay) is forwarded from WAN via DST-NAT. Port 22000 (sync) is intentionally NOT forwarded -- off-network clients connect through the relay exclusively. This minimizes attack surface while the relay provides token + mTLS authentication.

Split-horizon DNS resolves `relay.matthew-stratton.me` to `192.168.1.233` on LAN (router static DNS) and to the WAN IP off-network (Cloudflare DDNS). This allows the same relay URL to work in both contexts without hairpin NAT issues.

### Connectivity by Location

| Client location | Sync connection | How |
|----------------|----------------|-----|
| LAN (WiFi/ethernet) | Direct TCP | `192.168.1.233:22000` |
| VPN (WireGuard) | Direct TCP or relay | LAN access through tunnel |
| Off-network (cellular/remote) | Relay | `relay.matthew-stratton.me:22067` via DST-NAT |

### Known Limitations

- **Local discovery does not work.** The pod is on the flannel pod subnet (`10.42.x.0/24`), not the LAN (`192.168.1.0/24`). UDP broadcast announcements on port 21027 don't cross subnets. Clients must add the hub manually by device ID. Global discovery works for address resolution after pairing.
- **Symmetric NAT.** kube-proxy DNAT presents as symmetric NAT to Syncthing, preventing QUIC hole-punching. This is irrelevant since off-network traffic uses the relay.
- **Relay DNS.** `relay.matthew-stratton.me` resolves to `192.168.1.233` on LAN (split-horizon) and the WAN IP off-network (Cloudflare DDNS). The DDNS record is maintained by the router alongside the other DDNS records.

## Hub Configuration

The hub's Syncthing settings are applied via `just syncthing-relay-configure`, which uses the REST API. This recipe is idempotent and should be re-run after a fresh deployment or if settings drift. See the justfile for the specific settings it applies.

## Client Setup

### Adding the Hub

On the client device:

1. Add remote device with the hub's device ID (visible at `syncthing.matthew-stratton.me` or in pod logs)
2. Set address to `dynamic`
3. Enable **Introducer** (the hub introduces other devices to this client)
4. Enable **Auto Accept** (auto-accept folders the hub shares)

On the hub, approve the new device when prompted. The hub's default device config has `autoAcceptFolders: true`, so shared folders are accepted automatically.

### Client Listen Addresses

Replace the default `default` with explicit entries to use the private relay instead of the public pool:

```
tcp://0.0.0.0:22000, quic://0.0.0.0:22000, relay://relay.matthew-stratton.me:22067/?id=<RELAY_DEVICE_ID>&token=<RELAY_TOKEN>
```

The relay device ID is in the relaysrv container logs (`just syncthing-relay-logs`). The token is `SYNCTHING_RELAY_TOKEN` from `.envrc`.

### Client Settings

- **Global discovery**: enabled (default servers)
- **Local discovery**: enabled (works between LAN clients, just not with the hub)
- **Relaying**: enabled
- **Compression**: metadata (hub is on low-power ARM hardware)
- **Introducer**: set on the hub device entry (client tells Syncthing "the hub will introduce me to other devices")
- **Auto Accept**: set on the hub device entry (client auto-accepts folders the hub shares)

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `SYNCTHING_RELAY_TOKEN` | Token for relay server authentication |
| `SYNCTHING_API_KEY` | Syncthing REST API key (generated on first run, stored in `.envrc`) |
| `SYNCTHING_GUI_USER` | GUI username |
| `SYNCTHING_GUI_PASSWORD` | GUI password (plaintext, API hashes it with bcrypt) |

## Deployment from Scratch

1. Create iSCSI LUN on Synology (LUN 6 on default-target)
2. Add `SYNCTHING_RELAY_TOKEN`, `SYNCTHING_API_KEY`, `SYNCTHING_GUI_USER`, `SYNCTHING_GUI_PASSWORD` to `.envrc`
3. `just syncthing-relay-deploy`
4. `just syncthing-relay-configure`
5. `./scripts/homelab-sync-dns.sh` then `cd ansible && ansible-playbook mikrotik-configure.yml`
6. Add clients by device ID, configure listen addresses with private relay URL

The API key is generated by Syncthing on first run. After initial deploy, retrieve it from the pod: `kubectl -n syncthing-relay exec deploy/syncthing-relay -c syncthing -- grep apikey /var/syncthing/config/config.xml`

## Troubleshooting

**Client can't connect off-network:** Check that the client's listen addresses include the private relay URL with correct device ID and token. Verify relay is reachable: `nc -zv relay.matthew-stratton.me 22067`.

**Slow reconnect after client network change:** Syncthing and the relay detect dead connections within a couple of minutes via application-level keepalives. The client reconnects automatically. The kernel TCP keepalive is much longer (2 hours default) but is not the bottleneck -- Syncthing's own detection is faster.

**Relay status shows zero connections:** All devices are on LAN using direct TCP. The relay is only active when a client is off-network and can't reach the hub directly.

**"Unexpected device ID" errors on clients:** Normal when multiple Syncthing devices share the same WAN IP. Global discovery returns the WAN IP for all LAN devices, but only the hub is reachable via the relay. The errors resolve as Syncthing settles on the correct connection path.

**GUI "disconnected" popups:** The ingress has 1-hour WebSocket timeouts (`proxy-read-timeout: 3600`). If popups persist, check ingress-nginx logs.

## Related Documentation

- [Syncthing Appendix](appendix/syncthing.md) -- Protocol and technology reference
- [Networking](04-networking.md) -- MetalLB, ingress, DNS, traffic flow
- [Security](05-security.md) -- WAN exposure, threat-intel port exclusion
- [Persistence](03-persistence.md) -- iSCSI LUN configuration
- [Infrastructure Provisioning](01-infrastructure-provisioning.md) -- Router DST-NAT and firewall rules
