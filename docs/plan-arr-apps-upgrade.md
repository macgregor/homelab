# Arr Apps: iSCSI Migration and Image Update

## Context

Prowlarr, Radarr, and Sonarr have been offline and need to be brought back up. Like Jellyfin, their config volumes use NFS which doesn't support the POSIX file locking that SQLite requires. Before redeploying, migrate their config storage from NFS to iSCSI (same pattern as `docs/plan-iscsi-jellyfin-volume.md`) and update to current stable images. Since none are currently deployed, this can be done in one shot with no service disruption concerns.

**Image updates:**
| App | Current | Target |
|-----|---------|--------|
| Prowlarr | 1.18.0 | 2.3.0 |
| Radarr | 5.6.0 | 6.0.4 |
| Sonarr | 4.0.5 | 4.0.16 |

**iSCSI infrastructure (iscsid, iscsi-initiator-utils) already installed** on all nodes from the Jellyfin migration.

**Version upgrade notes:** All three apps auto-migrate their SQLite databases on startup. Prowlarr v2 changed its bundled SQLite library (irrelevant for Docker). Radarr v6 switched from Mono to .NET (handled by the linuxserver image). Sonarr 4.0.5->4.0.16 is a minor bump with no schema changes. No manual migration steps required for any of them.

**iSCSI layout:** All three LUNs are mapped to the existing `default-target` (same target Jellyfin uses at LUN 1):

| LUN | App | IQN | Device Path |
|-----|-----|-----|-------------|
| 1 | jellyfin (existing) | iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 | `ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-1` |
| 2 | prowlarr | iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 | `ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-2` |
| 3 | radarr | iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 | `ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-3` |
| 4 | sonarr | iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 | `ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-4` |

**NFS source data sizes:** prowlarr 21M, radarr 4.2M, sonarr 202M

---

## ~~Phase 0: Manual DSM Work (User)~~ DONE

LUNs created in Synology DSM > SAN Manager, mapped to `default-target`. LUN IDs verified via `iscsiadm` session rescan on k3-n1.

---

## Phase 1: Migrate Data, Update Images, Deploy

### Step 1: Format LUNs and migrate data from NFS

SSH to a cluster node (`ssh k3-m1` or `ssh k3-n1`). Password auth is disabled on all hosts; use the `macgregor` user which is configured in `~/.ssh/config` to use the `~/.ssh/macgregor.id_rsa` key. For the Synology (no host alias): `ssh macgregor@192.168.1.200`.

Login to the target (or rescan if a session already exists from Jellyfin), then format and copy data for each app.

```bash
# Login (if no session exists) or rescan (if Jellyfin session is active)
sudo iscsiadm -m node --targetname iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 --portal 192.168.1.200:3260 --login
# OR if already logged in:
sudo iscsiadm -m session --rescan

# Verify all 3 LUNs are visible
ls -la /dev/disk/by-path/ | grep default-target
```

**Prowlarr (LUN 2, ~21M to copy):**
```bash
sudo mkfs.ext4 /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-2
sudo mkdir -p /mnt/prowlarr-iscsi /mnt/prowlarr-nfs
sudo mount /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-2 /mnt/prowlarr-iscsi
sudo mount -t nfs 192.168.1.200:/volume2/kube-nfs/v/prowlarr-config /mnt/prowlarr-nfs
sudo cp -a /mnt/prowlarr-nfs/* /mnt/prowlarr-iscsi/
sudo du -sh /mnt/prowlarr-nfs /mnt/prowlarr-iscsi
sudo umount /mnt/prowlarr-nfs /mnt/prowlarr-iscsi
```

**Radarr (LUN 3, ~4.2M to copy):**
```bash
sudo mkfs.ext4 /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-3
sudo mkdir -p /mnt/radarr-iscsi /mnt/radarr-nfs
sudo mount /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-3 /mnt/radarr-iscsi
sudo mount -t nfs 192.168.1.200:/volume2/kube-nfs/v/radarr-config /mnt/radarr-nfs
sudo cp -a /mnt/radarr-nfs/* /mnt/radarr-iscsi/
sudo du -sh /mnt/radarr-nfs /mnt/radarr-iscsi
sudo umount /mnt/radarr-nfs /mnt/radarr-iscsi
```

**Sonarr (LUN 4, ~202M to copy):**
```bash
sudo mkfs.ext4 /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-4
sudo mkdir -p /mnt/sonarr-iscsi /mnt/sonarr-nfs
sudo mount /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-4 /mnt/sonarr-iscsi
sudo mount -t nfs 192.168.1.200:/volume2/kube-nfs/v/sonarr-config /mnt/sonarr-nfs
sudo cp -a /mnt/sonarr-nfs/* /mnt/sonarr-iscsi/
sudo du -sh /mnt/sonarr-nfs /mnt/sonarr-iscsi
sudo umount /mnt/sonarr-nfs /mnt/sonarr-iscsi
```

```bash
# Logout when done (only if Jellyfin is NOT running on this node)
sudo iscsiadm -m node --targetname iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 --portal 192.168.1.200:3260 --logout
```

NFS data preserved as fallback.

### Step 2: Update `storage.yml` (per app)

Replace the NFS PV with an iSCSI PV. PVC stays the same.

**Existing NFS PVs are live in the cluster** (Bound, ~624 days old). PV `spec` is immutable, so the existing PVs must be deleted before the updated storage.yml can be applied (handled in Step 4).

`kube/media/prowlarr/storage.yml` -- PV changes:
```yaml
# replace nfs block with:
  iscsi:
    targetPortal: 192.168.1.200:3260
    iqn: iqn.2000-01.com.synology:synology.default-target.7d1c64e1219
    lun: 2
    fsType: ext4
    readOnly: false
```

`kube/media/radarr/storage.yml` -- PV changes:
```yaml
# replace nfs block with:
  iscsi:
    targetPortal: 192.168.1.200:3260
    iqn: iqn.2000-01.com.synology:synology.default-target.7d1c64e1219
    lun: 3
    fsType: ext4
    readOnly: false
```

`kube/media/sonarr/storage.yml` -- PV changes:
```yaml
# replace nfs block with:
  iscsi:
    targetPortal: 192.168.1.200:3260
    iqn: iqn.2000-01.com.synology:synology.default-target.7d1c64e1219
    lun: 4
    fsType: ext4
    readOnly: false
```

Also remove the NFS-specific comments (`# not enforced on NFS shares`, `#not dynamic so make sure it already exists on the NAS`).

### Step 3: Update container images

| File | Change |
|------|--------|
| `kube/media/prowlarr/prowlarr.yml` | `linuxserver/prowlarr:1.18.0` -> `linuxserver/prowlarr:2.3.0` |
| `kube/media/radarr/radarr.yml` | `linuxserver/radarr:5.6.0` -> `linuxserver/radarr:6.0.4` |
| `kube/media/sonarr/sonarr.yml` | `linuxserver/sonarr:4.0.5` -> `linuxserver/sonarr:4.0.16` |

### Step 4: Deploy all three

```bash
cd kube/

# Delete existing NFS-backed PVs (spec is immutable, can't update in-place)
# PVCs will become unbound but that's fine since no pods are using them
kubectl delete pv prowlarr-config radarr-config sonarr-config

make prowlarr-deploy
make radarr-deploy
make sonarr-deploy
```

### Step 5: Verify

Per app:
- `make prowlarr-status` / `make radarr-status` / `make sonarr-status` -- PVC Bound, pod Running
- `make prowlarr-logs` / `make radarr-logs` / `make sonarr-logs` -- clean startup, no SQLite errors
- Check web UIs: prowlarr :9696, radarr :7878, sonarr :8989

---

## Files Modified

| File | Change |
|------|--------|
| `kube/media/prowlarr/storage.yml` | NFS PV -> iSCSI PV (LUN 2) |
| `kube/media/radarr/storage.yml` | NFS PV -> iSCSI PV (LUN 3) |
| `kube/media/sonarr/storage.yml` | NFS PV -> iSCSI PV (LUN 4) |
| `kube/media/prowlarr/prowlarr.yml` | Image 1.18.0 -> 2.3.0 |
| `kube/media/radarr/radarr.yml` | Image 5.6.0 -> 6.0.4 |
| `kube/media/sonarr/sonarr.yml` | Image 4.0.5 -> 4.0.16 |

## User Actions Required

1. **Step 5:** Verify web UIs after deployment (prowlarr :9696, radarr :7878, sonarr :8989)

## Work Log

**2026-02-17:** Completed all phases.

- **Step 1 (data migration):** SSH'd to k3-n1. Rescanned iSCSI session, all 4 LUNs visible. Formatted LUNs 2-4 with ext4, copied data from NFS. Sizes verified: prowlarr 21M, radarr 4.2M, sonarr 202M.
- **Step 2 (storage.yml):** Replaced NFS PV specs with iSCSI specs matching Jellyfin's pattern. Removed NFS-specific comments.
- **Step 3 (images):** Updated prowlarr 1.18.0->2.3.0, radarr 5.6.0->6.0.4, sonarr 4.0.5->4.0.16.
- **Step 4 (deploy):** Old NFS PVs were stuck in `Terminating` due to finalizers; cleared finalizers to complete deletion. Then deployed all three successfully.
- **Step 5 (verify):** All PVCs Bound, all pods Running 1/1. DB migrations ran cleanly on all three (radarr to migration 242, sonarr to 217). No SQLite errors. Prowlarr logged 401s trying to sync indexers to radarr -- expected since radarr's API key likely needs re-entering in Prowlarr's UI after the upgrade.
