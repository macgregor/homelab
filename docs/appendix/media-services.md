---
name: media-services
description: >
  Load this document when working with Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent,
  Seerr, Tdarr, Decluttarr, Gluetun VPN, or LinuxServer.io containers. Covers architecture,
  APIs, integration patterns, folder structure, permissions, and troubleshooting.
categories: [media, automation]
tags: [jellyfin, sonarr, radarr, prowlarr, qbittorrent, seerr, tdarr, decluttarr, gluetun, linuxserver, servarr]
related_docs:
  - docs/03-persistence.md
  - docs/04-networking.md
complexity: intermediate
---

# Media Services Reference

Reference for self-hosted media automation: Jellyfin (playback), *arr suite (Sonarr/Radarr/Prowlarr), qBittorrent, Gluetun VPN, Tdarr, Seerr, Decluttarr. Concise working reference with links to official docs.

**Community resource root:** https://wiki.servarr.com/ and https://trash-guides.info/

---

## Table of Contents

1. [Critical Gotchas](#1-critical-gotchas)
2. [Ecosystem Overview](#2-ecosystem-overview)
3. [LinuxServer.io Containers](#3-linuxserverio-containers)
4. [Folder Structure and Hardlinks](#4-folder-structure-and-hardlinks)
5. [Jellyfin](#5-jellyfin)
6. [Sonarr and Radarr](#6-sonarr-and-radarr)
7. [Prowlarr](#7-prowlarr)
8. [qBittorrent and Gluetun](#8-qbittorrent-and-gluetun)
9. [Seerr](#9-seerr)
10. [Tdarr](#10-tdarr)
11. [Decluttarr](#11-decluttarr)
12. [Common Troubleshooting Patterns](#12-common-troubleshooting-patterns)
13. [Documentation Links](#13-documentation-links)

---

## 1. Critical Gotchas

### SQLite databases must be on local storage

All *arr apps and Jellyfin use SQLite. NFS/SMB causes "database locked" errors and corruption. iSCSI works because it presents as a local block device, but the volume must only be mounted by one node at a time (or use a cluster-aware filesystem like Ceph). Network file shares (NFS/SMB) for media only — never for config/data directories.

### Folder structure determines hardlink support

Download and media directories on different filesystems (or separate Docker volumes) force slow copy-and-delete instead of instant hardlinks. See [Folder Structure and Hardlinks](#4-folder-structure-and-hardlinks).

### Inconsistent PUID/PGID across containers breaks imports

All media pipeline containers must share a common group. Mismatched ownership causes "folder not writable" errors and failed imports.

### Reverse proxies must support WebSockets

*arr apps and Jellyfin require WebSocket support (`Upgrade` and `Connection` headers). Jellyfin also needs reverse proxy IPs in "Known Proxies" network setting.

### Jellyfin Base URL breaks integrations

Setting a Base URL (subpath like `/jellyfin`) breaks DLNA, HDHomeRun, Sonarr/Radarr connections, and some clients. Use subdomain access instead.

### qBittorrent category paths must match *arr expectations

Path mismatches between download client and *arr apps are the most common cause of failed imports. qBittorrent categories must have save paths the *arr apps can access.

### Gluetun DNS breaks container name resolution

Gluetun's built-in Unbound replaces Docker DNS. Fix with `DNS_ADDRESS=127.0.0.11` or `DNS_SERVER=on`.

### VPN port forwarding is not router port forwarding

Behind VPN, the listening port must be forwarded by the VPN provider, not the home router. Disable UPnP/NAT-PMP in qBittorrent.

---

## 2. Ecosystem Overview

### Data flow

```
User Request (Seerr)
    → Media Manager (Sonarr/Radarr)
        → Indexer Search (Prowlarr → trackers/indexers)
        → Download (qBittorrent via Gluetun VPN)
        → Import (Sonarr/Radarr move/hardlink to library)
    → Transcode (Tdarr processes library files)
    → Playback (Jellyfin serves to clients)

Queue Cleanup (Decluttarr monitors and removes failed downloads)
```

### Service roles

| Service | Role | Default Port |
|---------|------|-------------|
| Jellyfin | Media server and player | 8096 |
| Sonarr | TV series management and automation | 8989 |
| Radarr | Movie management and automation | 7878 |
| Prowlarr | Indexer aggregation and sync | 9696 |
| qBittorrent | Torrent download client | 8080 |
| Gluetun | VPN sidecar container | 9999 (health) |
| Seerr | Media request UI for users | 5055 |
| Tdarr | Distributed video transcoding | 8265 (UI), 8266 (server) |
| Decluttarr | Download queue cleanup | None (headless) |

### Shared technology

All *arr apps are C#/.NET with SQLite, REST APIs (API key auth), and web UIs. Shared architecture and configuration patterns. Typically deployed via LinuxServer.io images.

---

## 3. LinuxServer.io Containers

**Docs:** https://docs.linuxserver.io/

Most media services use LinuxServer.io (LSIO) Docker images with shared conventions.

### PUID, PGID, and UMASK

| Variable | Purpose | Recommended | Find with |
|----------|---------|-------------|-----------|
| `PUID` | Container user ID | Match host user | `id $USER` |
| `PGID` | Container group ID | Shared group across all media containers | `id $USER` |
| `UMASK` | Permission mask for new files | `002` (775 dirs, 664 files) | — |

### Init system and mods

LSIO containers use s6-overlay. If any init step fails, the container halts — check `docker logs` for errors.

`DOCKER_MODS` injects additional functionality at startup without rebuilding images. Multiple mods are pipe-separated: `mod1|mod2`.

### Logs

Logs go to stdout/stderr (`docker logs -f <container>`) and `/config/logs/` inside the container.

---

## 4. Folder Structure and Hardlinks

**Definitive guide:** https://trash-guides.info/File-and-Folder-Structure/Hardlinks-and-Instant-Moves/

### Recommended structure

```
/data                          # Single mount point
├── torrents/                  # Download client working directory
│   ├── tv/
│   └── movies/
└── media/                     # Organized library (Jellyfin reads this)
    ├── tv/
    └── movies/
```

Mount `/data` as a single volume in all containers. Download and media directories must share a filesystem for hardlinks to work. Separate Docker volumes break hardlinks even on the same physical disk. Hardlinks require a compatible filesystem (ext4, XFS, btrfs — not exFAT) and cannot cross mount points.

---

## 5. Jellyfin

**Docs:** https://jellyfin.org/docs/ | **API:** https://api.jellyfin.org/ | **GitHub:** https://github.com/jellyfin/jellyfin

C#/.NET app, port 8096. Uses jellyfin-ffmpeg (custom FFmpeg build) for transcoding. Plugin-based extensions.

### API authentication

```
Authorization: MediaBrowser Token="<api_key>"    # preferred
X-MediaBrowser-Token: <api_key>                  # alternative
X-Emby-Token: <api_key>                         # legacy fallback
```

Query parameter `?ApiKey=<key>` also works but is unsafe (logged in URLs). Generate keys in Dashboard > Advanced > API Keys. OpenAPI spec at `/openapi/jellyfin-openapi-stable.json`.

### Hardware acceleration

Supports VA-API, QSV (Intel), NVENC (NVIDIA), AMF (AMD), VideoToolbox (macOS). Full pipeline acceleration requires **jellyfin-ffmpeg** specifically — other FFmpeg builds produce partial acceleration only.

### Networking ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 8096 | TCP | HTTP web UI and API |
| 8920 | TCP | HTTPS (when enabled) |
| 7359 | UDP | Client auto-discovery |
| 1900 | UDP | DLNA/SSDP (subnet-only, requires host networking in Docker) |

### Plugins

Install via admin dashboard catalog. DLNA is a separate plugin (not bundled). Notable categories: authentication (LDAP), metadata providers, live TV tuners, subtitle downloaders.

### Troubleshooting

- **Transcode failures:** Check FFmpeg logs first. Subtitle burn-in and filter initialization are common failure points.
- **Database locked:** Reduce parallel library scan tasks.
- **inotify limit:** Large libraries require increasing `fs.inotify.max_user_watches` (524288).

---

## 6. Sonarr and Radarr

**Sonarr:** https://wiki.servarr.com/sonarr | https://sonarr.tv/docs/api/ | https://github.com/Sonarr/Sonarr
**Radarr:** https://wiki.servarr.com/radarr | https://radarr.video/docs/api/ | https://github.com/Radarr/Radarr

Radarr is a Sonarr fork for movies. Shared architecture, divergent media logic.

### Key concepts

| Concept | Notes |
|---------|-------|
| Root Folder | Top-level media directory (e.g., `/data/media/tv`) |
| Quality Profile | Acceptable quality tiers and upgrade path |
| Custom Format | Criteria beyond resolution (HDR, codec, release group) |
| Indexer | Release source (managed centrally via Prowlarr) |
| Download Client | e.g., qBittorrent, SABnzbd |
| Import List | Auto-add from external sources (IMDB, Trakt, Plex watchlist) |

### API (v3)

Authenticated via `X-Api-Key` header or `?apikey=` query parameter. API key found in Settings > General > Security.

**Common endpoints:**

| Endpoint | Sonarr | Radarr |
|----------|--------|--------|
| Content management | `/api/v3/series` | `/api/v3/movie` |
| Search triggers | POST `/api/v3/command` | POST `/api/v3/command` |
| Download queue | `/api/v3/queue` | `/api/v3/queue` |
| Health checks | `/api/v3/health` | `/api/v3/health` |
| System status | `/api/v3/system/status` | `/api/v3/system/status` |

**Search command examples:**

```json
// Sonarr: search for all missing episodes
{"name": "MissingEpisodeSearch"}

// Radarr: search for specific movies by ID
{"name": "MoviesSearch", "movieIds": [20, 42]}

// Radarr: search all missing monitored movies
{"name": "MissingMoviesSearch"}
```

### Download lifecycle

Search indexers → send to download client with category → poll queue → trigger Completed Download Handling → import/rename to library (hardlink or move) → optionally remove from client.

"Completed Download Handling" must be enabled (default) or completed downloads sit in the client indefinitely.

### Logs

Located in `<appdata>/logs/`. Rolling log files:
- `sonarr.txt` / `radarr.txt` — current log (Info level by default)
- `*.debug.txt` — debug level
- `*.trace.txt` — trace level (needed for most troubleshooting)

Log level changed in Settings > General (takes effect immediately, no restart needed).

### Sonarr vs. Radarr differences

| Aspect | Sonarr | Radarr |
|--------|--------|--------|
| Media type | TV series (seasons, episodes) | Movies |
| Monitoring granularity | Per-season and per-episode | Per-movie |
| Quality management | Custom Formats (v4) | Custom Formats (native since earlier) |
| Naming complexity | Season/episode numbering | Year, edition (Director's Cut, etc.) |
| Search commands | `EpisodeSearch`, `MissingEpisodeSearch`, `SeriesSearch` | `MoviesSearch`, `MissingMoviesSearch` |

---

## 7. Prowlarr

**Docs:** https://wiki.servarr.com/prowlarr | **API:** https://prowlarr.com/docs/api/ | **GitHub:** https://github.com/Prowlarr/Prowlarr

Centralized indexer manager. Configure indexers once, Prowlarr pushes to downstream *arr apps.

### App sync

Push-based sync by category compatibility (TV indexers → Sonarr, movie indexers → Radarr). Tag filtering restricts indexer distribution. Full Sync mode overrides remote app indexer settings. Manual sync via "Sync App Indexers" button.

### Indexer types

- **Usenet:** Newznab protocol. Requires URL and API key.
- **Torrent:** Torznab protocol. Supports 500+ trackers natively. Custom YAML definitions (Cardigann) for non-standard sites.

### FlareSolverr

Proxy for bypassing Cloudflare protection on indexers. Increasingly unreliable as Cloudflare evolves countermeasures. Tags must match between the FlareSolverr proxy config and the indexer for it to activate. See [TRaSH Guides FlareSolverr setup](https://trash-guides.info/Prowlarr/prowlarr-setup-flaresolverr/).

### API

REST API (v1) authenticated via `X-Api-Key` header. Default port 9696. OpenAPI spec at the GitHub repo.

---

## 8. qBittorrent and Gluetun

### qBittorrent

**Web API:** https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1) | **GitHub:** https://github.com/qbittorrent/qBittorrent

**API authentication:** Cookie-based. POST `/api/v2/auth/login` with `username`/`password`. Requires `Referer` or `Origin` header matching the host.

**Key API endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v2/torrents/info` | GET | List torrents (filter by state, category, tag) |
| `/api/v2/torrents/add` | POST | Add torrent (URL, magnet, or file upload) |
| `/api/v2/torrents/{pause,resume,delete}` | POST | Torrent control |
| `/api/v2/torrents/categories` | GET | List categories |
| `/api/v2/app/preferences` | GET | Get preferences |
| `/api/v2/app/setPreferences` | POST | Set preferences |

**Integration with *arr apps:** Create categories matching *arr config (e.g., `radarr`, `sonarr`) with save paths under the shared download mount. Enable "Automatic Torrent Management" and "When Torrent Category changed: Relocate torrent."

**Port forwarding:** ISPs often throttle default ports (6881-6889). Use a custom listening port. Behind VPN, disable UPnP/NAT-PMP and use the VPN-provided forwarded port.

**Reference:** [TRaSH Guides qBittorrent setup](https://trash-guides.info/Downloaders/qBittorrent/Basic-Setup/)

### Gluetun

**GitHub:** https://github.com/qdm12/gluetun | **Wiki:** https://github.com/qdm12/gluetun-wiki

Lightweight VPN client container (Go/Alpine) acting as a network gateway. Other containers share its network namespace, routing all traffic through the VPN tunnel.

| Feature | Description |
|---------|-------------|
| Kill switch | iptables blocks all non-VPN traffic. VPN drop = dependent containers lose connectivity. |
| Port forwarding | Dynamic, for providers that support it (ProtonVPN, PIA). Exposed via control server API and `/tmp/gluetun/forwarded_port`. |
| Health check | HTTP on port 9999. Returns 200 (healthy) or 500 (unhealthy). Verifies VPN via TCP/TLS to external target. |
| DNS over TLS | Built-in Unbound resolver. |
| Protocols | OpenVPN and WireGuard (kernel and userspace). |

**Port forwarding:** Set `VPN_PORT_FORWARDING=on`. Applications discover the forwarded port via the control server HTTP API (preferred) or the status file.

**Health check:** Default `127.0.0.1:9999`, configure with `HEALTH_SERVER_ADDRESS`. Use as liveness/readiness probe for dependent containers.

**Container networking:** Containers sharing Gluetun's network must expose ports on the Gluetun container. Built-in DNS replaces Docker DNS — fix with `DNS_ADDRESS=127.0.0.11`.

---

## 9. Seerr

**Docs:** https://docs.seerr.dev/ | **GitHub:** https://github.com/seerr-team/seerr

Media request and discovery platform. TMDB-powered search, approved requests pushed to Sonarr/Radarr. Supports Jellyfin, Plex, Emby for user authentication and library sync.

### TMDB

Powers search, discovery, metadata, and artwork. Rate limit: 50 requests/second per IP.

**TMDB connection failures:** Often ISP-level DNS blocking. Fix with public DNS (1.1.1.1, 8.8.8.8) or HTTP proxy in Settings > Networking.

### Common issues

- **Admin access loss:** If the media server user ID changes, Seerr loses admin permissions. Backup `settings.json`, delete it to retrigger setup, then restore backup.

---

## 10. Tdarr

**Docs:** https://docs.tdarr.io | **GitHub:** https://github.com/HaveAGitGat/Tdarr | **Plugins:** https://github.com/HaveAGitGat/Tdarr_Plugins

Server-node model. `Tdarr_Server` coordinates queue and library scanning. `Tdarr_Node` workers execute transcodes, can run on different machines.

### Key concepts

| Concept | Notes |
|---------|-------|
| Library | Independent transcode config with own filters, plugins, and schedule |
| Plugin/Flow | JavaScript processing pipeline (filter → action) |
| Transcode cache | Staging area for processing. Must be fast local storage (SSD), 2-3x largest file size. NFS causes bottlenecks. |
| Worker | Four types: Transcode CPU, Transcode GPU, Health Check CPU, Health Check GPU |

**Workers:** CPU workers run tasks without GPU terms in FFmpeg/HandBrake args. GPU workers run tasks with GPU terms (nvenc, cuda, vaapi). Workers skip incompatible plugins. Set limits per node.

---

## 11. Decluttarr

**GitHub:** https://github.com/ManiMatter/decluttarr

Monitors *arr queues and download client, removes failed/stalled downloads. Connects via REST APIs, can trigger re-search on removal.

### Strike system

Downloads accumulate strikes per monitoring cycle. At `max_strikes` (default: 3), eligible for removal. Strikes reset on recovery.

### Cleanup jobs

Remove failed downloads, failed imports, missing files, stalled torrents, slow torrents (below speed threshold), low-availability torrents. Distinguishes private vs. public trackers with different removal strategies.

### Configuration

YAML config with environment variable injection (`${API_KEY}`). `TEST_RUN: True` previews without acting. `max_strikes` too low (1) causes premature deletions.

---

## 12. Common Troubleshooting Patterns

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| "Waiting to Import" / "Import Failed" in Sonarr/Radarr | Path mismatch between download client and *arr app | Ensure consistent volume mounts; enable Trace logging to see exact paths |
| "Waiting to Import" | PUID/PGID mismatch — container can't write to target | Match PUID/PGID across all containers |
| Import fails on `.rar` files | Archives need extraction | Use Unpackerr |
| Downloads vanish before import | Download client cleared history too fast | Keep history 14+ days |
| "database is locked" / "disk image is malformed" | SQLite on network storage, or unclean shutdown | Move DB to local/iSCSI storage. Recovery: `sqlite3 app.db ".recover" \| sqlite3 recovered.db`. Remove `*.db-wal`/`*.db-shm`. Or restore from System > Backup. |
| *arr health warnings | Various config problems | Check System > Health page first. Common: indexer auth failures, download client unreachable, root folder missing, disk space low. |
| qBittorrent no connectivity | Gluetun VPN down | Check `curl http://localhost:9999`, Gluetun logs, VPN credentials, firewall rules |
| VPN connected but torrents stall | Port forwarding changed | Verify forwarded port matches qBittorrent listening port |

---

## 13. Documentation Links

### Ecosystem

| Topic | URL |
|-------|-----|
| Servarr Wiki (all *arr apps) | https://wiki.servarr.com/ |
| TRaSH Guides (community best practices) | https://trash-guides.info/ |
| Hardlinks and instant moves | https://trash-guides.info/File-and-Folder-Structure/Hardlinks-and-Instant-Moves/ |
| Docker folder structure | https://trash-guides.info/File-and-Folder-Structure/How-to-set-up/Docker/ |
| Servarr Docker guide | https://wiki.servarr.com/docker-guide |
| LinuxServer.io docs | https://docs.linuxserver.io/ |
| PUID/PGID explained | https://docs.linuxserver.io/general/understanding-puid-and-pgid |

### Jellyfin

| Topic | URL |
|-------|-----|
| Documentation | https://jellyfin.org/docs/ |
| API reference (OpenAPI) | https://api.jellyfin.org/ |
| Hardware acceleration | https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/ |
| HW accel known issues | https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/known-issues/ |
| Networking | https://jellyfin.org/docs/general/post-install/networking/ |
| Reverse proxy | https://jellyfin.org/docs/general/post-install/networking/reverse-proxy/ |
| Plugins | https://jellyfin.org/docs/general/server/plugins/ |
| Troubleshooting | https://jellyfin.org/docs/general/administration/troubleshooting/ |
| GitHub | https://github.com/jellyfin/jellyfin |

### Sonarr

| Topic | URL |
|-------|-----|
| Wiki | https://wiki.servarr.com/sonarr |
| API docs | https://sonarr.tv/docs/api/ |
| Troubleshooting | https://wiki.servarr.com/sonarr/troubleshooting |
| GitHub | https://github.com/Sonarr/Sonarr |

### Radarr

| Topic | URL |
|-------|-----|
| Wiki | https://wiki.servarr.com/radarr |
| API docs | https://radarr.video/docs/api/ |
| Troubleshooting | https://wiki.servarr.com/radarr/troubleshooting |
| GitHub | https://github.com/Radarr/Radarr |

### Prowlarr

| Topic | URL |
|-------|-----|
| Wiki | https://wiki.servarr.com/prowlarr |
| API docs | https://prowlarr.com/docs/api/ |
| FlareSolverr setup (TRaSH) | https://trash-guides.info/Prowlarr/prowlarr-setup-flaresolverr/ |
| Troubleshooting | https://wiki.servarr.com/prowlarr/troubleshooting |
| GitHub | https://github.com/Prowlarr/Prowlarr |

### qBittorrent

| Topic | URL |
|-------|-----|
| WebUI API | https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1) |
| Basic setup (TRaSH) | https://trash-guides.info/Downloaders/qBittorrent/Basic-Setup/ |
| Port forwarding (TRaSH) | https://trash-guides.info/Downloaders/qBittorrent/Port-forwarding/ |
| GitHub | https://github.com/qbittorrent/qBittorrent |

### Gluetun

| Topic | URL |
|-------|-----|
| GitHub | https://github.com/qdm12/gluetun |
| Wiki | https://github.com/qdm12/gluetun-wiki |
| VPN port forwarding | https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/vpn-port-forwarding.md |
| Health check FAQ | https://github.com/qdm12/gluetun-wiki/blob/main/faq/healthcheck.md |

### Seerr

| Topic | URL |
|-------|-----|
| Documentation | https://docs.seerr.dev/ |
| Troubleshooting | https://docs.seerr.dev/troubleshooting |
| GitHub | https://github.com/seerr-team/seerr |
| TMDB rate limiting | https://developer.themoviedb.org/docs/rate-limiting |

### Tdarr

| Topic | URL |
|-------|-----|
| Documentation | https://docs.tdarr.io |
| Workers | https://docs.tdarr.io/docs/nodes/workers |
| Transcode cache | https://docs.tdarr.io/docs/library-setup/transcode-cache |
| Plugins repo | https://github.com/HaveAGitGat/Tdarr_Plugins |
| GitHub | https://github.com/HaveAGitGat/Tdarr |

### Decluttarr

| Topic | URL |
|-------|-----|
| GitHub | https://github.com/ManiMatter/decluttarr |

### Quality and Naming

| Topic | URL |
|-------|-----|
| Sonarr quality profiles (TRaSH) | https://trash-guides.info/Sonarr/sonarr-setup-quality-profiles/ |
| Radarr custom formats (TRaSH) | https://trash-guides.info/Radarr/Radarr-collection-of-custom-formats/ |
| Sonarr naming scheme (TRaSH) | https://trash-guides.info/Sonarr/Sonarr-recommended-naming-scheme/ |
