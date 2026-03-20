---
name: syncthing
description: >
  Load this document when working with Syncthing configuration, relay servers,
  device connectivity, discovery, NAT traversal, or file synchronization behavior.
categories: [syncthing, networking]
tags: [syncthing, relay, discovery, bep, nat-traversal, file-sync]
related_docs:
  - docs/04-networking.md
  - docs/05-security.md
complexity: intermediate
---

# Syncthing

Syncthing is a continuous file synchronization program. It synchronizes files between devices in real time using a peer-to-peer model with no central server. This document covers the technology itself -- how the protocols, discovery, relaying, and NAT traversal work -- independent of any specific deployment.

## Core Concepts

### Device Identity

Each Syncthing instance generates a unique **device ID** derived from the SHA-256 hash of its TLS certificate. Device IDs are the primary way devices identify and authenticate each other. They look like `AAGG45L-6XPVTOQ-VFSW2EP-...` (groups of base32-encoded characters separated by dashes).

Two devices must exchange device IDs to communicate. The TLS certificate provides mutual authentication -- no passwords or tokens are needed for the sync protocol itself.

### Folder Types

Folders can operate in three modes:

- **Send & Receive**: Full bidirectional sync. Changes on any device propagate to all others.
- **Send Only**: This device sends changes to others but ignores incoming changes. Useful for a "master" copy.
- **Receive Only**: This device receives changes but doesn't push local modifications. Local changes are flagged as "locally changed items" and can be reverted to the global state.

### Introducer

When device A marks device B as an **introducer**, A automatically adds any devices that B shares folders with (for mutually shared folders). This creates a hub-and-spoke model where the introducer acts as a device directory:

- Introduced devices, their labels, and address settings propagate automatically.
- Devices are removed automatically if the introducer stops sharing folders with them.
- Introducer status cascades: an introducer's introducer becomes yours.
- Avoid bidirectional introducer relationships -- they create loops where removed devices get re-introduced endlessly.

### Auto Accept

When enabled on a device relationship, any folders shared by that device are automatically accepted without manual confirmation. Combined with the introducer feature, this allows fully automatic mesh formation: add a hub as an introducer with auto-accept, share folders with it, and all other devices learn about each other.

## Sync Protocol (BEP)

The **Block Exchange Protocol** operates over TCP and QUIC on **port 22000** (configurable).

### How it works

1. Files are split into blocks (128 KiB to 16 MiB). Each block is SHA-256 hashed.
2. Devices exchange **index updates** listing files and their block hashes.
3. When a file changes, only the modified blocks are transferred.
4. Each file has three tracked versions: local, per-remote-device, and global (desired state). When new index data arrives, Syncthing recalculates the global version and syncs accordingly.

### Change detection

- **Filesystem watcher**: Real-time detection using OS-level filesystem notifications. Events are batched for 10 seconds before triggering a scan.
- **Full scan**: Periodic (hourly by default), checks modification times, sizes, and permissions. Catches changes the watcher missed.

### Conflict handling

When two devices modify the same file simultaneously, one copy is renamed to `<filename>.sync-conflict-<date>-<time>-<modifiedBy>.<ext>`. The file with the older modification time gets the conflict suffix.

### Connections

- **TCP** (`tcp://`): Standard TLS-encrypted connection on port 22000.
- **QUIC** (`quic://`): UDP-based transport on port 22000. Supports multiplexing and is used for NAT traversal (hole-punching). QUIC connections are preferred when both peers support them.

Both inbound and outbound connections must be possible for direct sync. If either direction is blocked, the connection falls back to relay.

## Discovery

Syncthing uses two discovery mechanisms to find peers. Both are optional but improve connectivity.

### Local Discovery

Devices announce themselves on the local network via **UDP port 21027**:

- **IPv4**: Broadcast to the link broadcast address or `255.255.255.255`
- **IPv6**: Multicast to `ff12::8384`
- **Interval**: Every 30-60 seconds

The announcement packet contains the device ID and a list of addresses where the device accepts connections (e.g., `tcp://0.0.0.0:22000`). When the address is unspecified (`0.0.0.0`), receivers substitute the source IP of the announcement.

Local discovery only works within a single broadcast domain. Devices on different subnets, behind different routers, or in isolated network namespaces cannot discover each other this way.

### Global Discovery

Devices register with centralized HTTPS discovery servers:

- **Announce servers** (`discovery-announce-v4.syncthing.net`, `discovery-announce-v6.syncthing.net`): Devices POST their addresses here. Authentication is via the device's TLS client certificate. The server notes the source IP, and unspecified addresses are resolved to that IP.
- **Lookup server** (`discovery-lookup.syncthing.net`): Devices query here by device ID to find a peer's announced addresses.

The `default` keyword in Syncthing's configuration expands to include both v4 and v6 announce servers and the lookup server.

**Behind NAT**: When a device behind NAT announces to the global server, the server sees the NAT's public IP. It records this as the device's address. Other devices looking up this ID get the public IP + port. Whether this is reachable depends on NAT type and port forwarding.

**Address format in announcements**: Devices can advertise TCP, QUIC, and relay addresses. Example: `["tcp://192.0.2.45:22000", "relay://relay.example.com:22067"]`.

## NAT Traversal

Syncthing attempts several methods to establish connections through NAT:

### UPnP / NAT-PMP

Syncthing tries automatic port mapping via UPnP or NAT-PMP if the router supports it. For manual port forwarding, external and internal ports must match (e.g., 22000 -> 22000).

### QUIC Hole-Punching

QUIC (UDP-based) enables NAT hole-punching where both peers send packets to each other's public address simultaneously, creating matching NAT mappings. This works with **full-cone**, **restricted-cone**, and **port-restricted-cone** NAT types.

**Symmetric NAT** defeats hole-punching because the NAT assigns a different external port for each destination, making the port unpredictable. Syncthing reports the detected NAT type in its logs.

### Fallback to Relay

When direct connections (TCP, QUIC, hole-punching) all fail, Syncthing falls back to relay connections. The relay acts as a dumb pipe forwarding encrypted bytes -- it cannot read the data.

## Relaying

### Architecture

- **Relay server** (`strelaysrv`): A standalone service that accepts connections from Syncthing devices and relays encrypted traffic between them. It does not run Syncthing itself and cannot read the data.
- **Relay client** (built into Syncthing): When direct connections fail, Syncthing connects to a relay server and communicates through it.

### Relay Server (`strelaysrv`)

Listens on **port 22067/TCP** (data) and optionally **port 22070/TCP** (status/monitoring).

Key flags:

| Flag | Purpose |
|------|---------|
| `-listen=:22067` | Data listen address |
| `-pools=<urls>` | Comma-separated relay pool URLs to join. Default: `https://relays.syncthing.net/endpoint`. Set to `""` to disable pool registration (private relay). |
| `-token=<secret>` | Require clients to present this token. Implicitly disables pool joining. |
| `-keys=<dir>` | Directory for TLS certificate and key storage |
| `-status-srv=:22070` | Status endpoint. Set to `""` to disable. |
| `-ext-address=<addr>` | Advertise a different external address (for port forwarding scenarios) |

The relay outputs its **device ID** at startup in a URI: `relay://0.0.0.0:22067/?id=<DEVICE_ID>`. Clients need this device ID to connect.

### Public vs Private Relays

- **Public relay pool**: Relay servers register with `relays.syncthing.net` and are available to all Syncthing users. Any device can use them as fallback.
- **Private relay**: A relay with `-pools=""` or `-token=<secret>` that doesn't register with the pool. Only devices that know the relay address, device ID, and token can use it.

### Client Relay Configuration

In Syncthing's `listenAddresses` configuration:

- `default` expands to: `tcp://0.0.0.0:22000`, `quic://0.0.0.0:22000`, `dynamic+https://relays.syncthing.net/endpoint`
- The `dynamic+https://relays.syncthing.net/endpoint` entry causes the client to discover and use public relay pool servers.
- To use only a private relay, replace `default` with explicit entries: `tcp://0.0.0.0:22000`, `quic://0.0.0.0:22000`, and `relay://<host>:<port>/?id=<RELAY_ID>&token=<TOKEN>`.

The `relaysEnabled` option must be `true` for the client to use any relays.

### Performance

Relay connections are significantly slower than direct connections. Syncthing periodically retries direct connections and switches to them when available, dropping the relay.

## Untrusted (Encrypted) Devices

Syncthing supports sharing folders with **untrusted devices** where data is encrypted at rest. The untrusted device stores only ciphertext and cannot read the files.

### How it works

- Trusted devices encrypt data with a password before sending to the untrusted device.
- Encryption uses **XChaCha20-Poly1305** and **AES-SIV** with a key derived from the password and folder ID via scrypt.
- File data, metadata (names, timestamps, hashes), and directory structure are encrypted.
- The untrusted device sees only: folder ID/label, and approximate file sizes.

### Use case

Place an untrusted Syncthing node on a cloud server or remote site. It stores encrypted backups without being able to read them. Any trusted device with the password can sync from it.

### Limitations

- Block reuse between files is disabled on untrusted devices (prevents cross-file analysis).
- File renames trigger full re-downloads (can't reuse blocks when filename is part of the key).
- Folder type on the untrusted device must be set to "Receive Encrypted."

### Recovery

To decrypt data offline: `syncthing decrypt --to <destination> --password <password> <encrypted-folder>`

## File Versioning

Syncthing can archive old file versions when they're replaced or deleted by remote changes. Versioning is per-folder and only applies to changes received from other devices, not local modifications.

### Versioning Types

| Type | Behavior | Key Parameters |
|------|----------|----------------|
| **Trash Can** | Moves replaced/deleted files to `.stversions`. Overwrites previous versions of the same file. | `cleanoutDays`: auto-delete after N days (0 = keep forever) |
| **Simple** | Keeps multiple timestamped copies in `.stversions`. | `keep`: max versions per file. `cleanoutDays`: retention period. |
| **Staggered** | Keeps versions at decreasing frequency as they age: one per 30s for the last hour, one per hour for the last day, one per day for the last month, one per week beyond that. | `maxAge`: max retention in days (0 = forever) |
| **External** | Runs a custom command before file replacement. | `command`: receives `%FOLDER_PATH%` and `%FILE_PATH%` template variables. |

All types store versions in `.stversions` by default (configurable via `fsPath`).

## Network Requirements Summary

| Feature | Protocol | Port | Direction | Required? |
|---------|----------|------|-----------|-----------|
| Sync (BEP) | TCP | 22000 | Both | Yes |
| Sync (QUIC) | UDP | 22000 | Both | Recommended |
| Local discovery | UDP | 21027 | Broadcast/multicast | Optional |
| Global discovery | HTTPS | 443 | Outbound | Optional |
| Relay data | TCP | 22067 | Outbound (or both for relay server) | Fallback |
| Relay status | TCP | 22070 | Inbound | Optional (monitoring) |
| GUI / REST API | TCP | 8384 | Inbound | Management |

For direct connections: open TCP+UDP 22000 inbound, or configure port forwarding with matching external/internal ports.

For relay-only: only outbound TCP to port 22067 is needed (or the relay server's custom port).

## SOCKS5 Proxy Support

Syncthing supports SOCKS5 proxies for all outbound connections, configured via environment variable or GUI settings.

## References

- [Syncthing Documentation](https://docs.syncthing.net/)
- [Firewall Setup](https://docs.syncthing.net/users/firewall.html)
- [Relaying](https://docs.syncthing.net/users/relaying.html)
- [Relay Server](https://docs.syncthing.net/users/strelaysrv.html)
- [Introducer](https://docs.syncthing.net/users/introducer.html)
- [Untrusted Devices](https://docs.syncthing.net/users/untrusted.html)
- [File Versioning](https://docs.syncthing.net/users/versioning.html)
- [Global Discovery Protocol](https://docs.syncthing.net/specs/globaldisco-v3.html)
- [Local Discovery Protocol](https://docs.syncthing.net/specs/localdisco-v4.html)
