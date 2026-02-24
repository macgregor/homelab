# Jellyfin: Migrate Config Storage from NFS to iSCSI

## Context

Jellyfin's SQLite database crashes frequently on NFS due to NFS's lack of proper file locking semantics. SQLite requires POSIX advisory locks which NFS doesn't reliably support. The config volume (which contains the database, metadata cache, and application settings) needs to move to block storage (iSCSI) where SQLite works correctly. Media files remain on NFS (read-heavy, no locking issues). The arr apps have the same problem and will follow the same pattern when redeployed.

## Approach: Manual iSCSI LUN with Static PV

**Why not dynamic provisioning:** Both the official Synology CSI driver and democratic-csi's synology-iscsi driver were tried ~4 years ago and abandoned. The official driver (v1.2.1, Oct 2025) still lacks native ARM64 images. Democratic-csi's synology-iscsi remains marked "experimental." For a handful of apps, manually creating LUNs in DSM and static PV/PVC in Kubernetes is simpler and more reliable.

## Verified Access

| Target | Access | Method |
|--------|--------|--------|
| kubectl / k8s cluster | Yes | Direct (KUBECONFIG via .envrc) |
| k3-m1 (192.168.1.210) | Yes, passwordless sudo | SSH |
| k3-n1 (192.168.1.211) | Yes, passwordless sudo | SSH |
| Synology (192.168.1.200) | SSH yes, sudo requires password | SSH |
| Synology DSM web UI | No (cannot automate) | **User must do this** |
| Ansible | Yes | ansible-playbook from local |

---

## Phase 1: Safe Work (Jellyfin stays running on NFS, no downtime)

Everything in this phase can be done while Jellyfin is running normally. Nothing here touches the running deployment.

### Step 1: Install `iscsi-initiator-utils` on nodes

**Claude does this.** Neither node has `iscsi-initiator-utils` installed.

**a)** Edit `ansible/roles/sys/tasks/main.yml` -- two changes using existing patterns:
- Add `"iscsi-initiator-utils"` to the "Install system packages" dnf task (in the `name:` list alongside `nfs-utils`)
- Add `{name: iscsid.service}` to the "Manage systemd services" loop (alongside the other services)

**b)** Run ansible to apply the changes to all nodes:
```bash
cd ansible/
ansible-playbook k3-install.yml --tags slow
```
Note: `--tags slow` runs all `slow`-tagged tasks across all roles (sys, k3s/common, k3s/master, k3s/node), not just the sys role. The other tasks are idempotent (check k3s binary, verify service state) and safe to re-run.

**c)** Verify via SSH that the package is installed, `iscsid` is running on each node, and each has a unique initiator name in `/etc/iscsi/initiatorname.iscsi`.

**Files modified:** `ansible/roles/sys/tasks/main.yml`

---

### Step 2: Check current NFS usage and create iSCSI Target/LUN

**Claude does this (usage check):** SSH to Synology and check current config volume size:
```bash
ssh macgregor@192.168.1.200 "du -sh /volume2/kube-nfs/v/jellyfin-config"
```
Confirm it fits within 10 GiB. If not, adjust the LUN size.

**DONE (LUN creation)** -- created manually in DSM SAN Manager.

- Target/LUN: `jellyfin-config` on Volume 2, 10 GiB, thin provisioned
- IQN: `iqn.2000-01.com.synology:synology.default-target.7d1c64e1219`
- Portal: `192.168.1.200:3260`
- LUN ID: 1 (DSM shows as LUN 0 but iSCSI protocol reports lun-1 in `/dev/disk/by-path/`)
- No CHAP authentication

---

### Step 3: Test iSCSI connectivity

**Claude does this** after receiving the IQN. Test from both nodes via SSH to confirm either can attach the volume (pod could be scheduled on either):

On each node (k3-m1 and k3-n1):
```bash
sudo iscsiadm -m discovery -t sendtargets -p 192.168.1.200:3260
sudo iscsiadm -m node --targetname iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 --portal 192.168.1.200:3260 --login
# verify block device appears at /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-1
lsblk
ls -la /dev/disk/by-path/ | grep iscsi
sudo iscsiadm -m node --targetname iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 --portal 192.168.1.200:3260 --logout
```
Test one node at a time (ReadWriteOnce -- only one node can attach at once).

---

### Step 4: Update tracked reference files

**Claude does this.** Update the reference copies in `kube/media/jellyfin/conf/` -- these are tracked copies for documentation, not consumed by the running deployment:

- `conf/database.xml`: Change `<LockingBehavior>Optimistic</LockingBehavior>` to `<LockingBehavior>Default</LockingBehavior>`
- `conf/NOTE.md`: Update the "Database Locking" section to note the workaround is no longer needed on iSCSI/ext4

**Files modified:** `kube/media/jellyfin/conf/database.xml`, `kube/media/jellyfin/conf/NOTE.md`

---

### Step 5: Update `docs/02-persistence.md`

**Claude does this.** The current doc has minimal storage info. Add a comprehensive storage section documenting:

**Storage patterns in use:**
- **NFS (democratic-csi dynamic provisioning)** -- StorageClasses `synology-nfs-app-data-retain` / `synology-nfs-app-data-delete` via democratic-csi `nfs-client` driver. Auto-creates subdirectories under `/volume2/kube-nfs`. Mount options: `noatime,nolock,nfsvers=3`. Limitation: no volume expansion, no snapshots, not suitable for SQLite or other databases that need POSIX file locking.
- **NFS (static PV)** -- Manually created PV/PVC pointing to pre-existing NFS paths (e.g., `/volume2/kube-nfs/v/<app>-config`). Same locking limitations. StorageClassName `""` to prevent dynamic provisioner matching.
- **NFS (direct volume mount)** -- Media files mounted directly in pod spec, no PV/PVC. Read-heavy workloads where locking isn't an issue.
- **iSCSI (static PV)** -- Block storage for apps with SQLite databases. Manually provisioned LUNs on Synology Volume 2 via DSM SAN Manager. Supports proper POSIX locking, volume expansion, and snapshots. Used by Jellyfin and arr apps.
- **local-path** -- Node-local storage via k3s default StorageClass. Volatile/cache data (e.g., transcode temp files). Not persistent across nodes.

**How to create a new iSCSI volume:**
1. DSM > SAN Manager > create target + thin-provisioned LUN on Volume 2
2. Note the IQN, portal is `192.168.1.200:3260`
3. A fresh target with a single LUN is always LUN ID 0
4. Add static PV to app's `storage.yml` with `iscsi:` volume source
5. Requires `iscsi-initiator-utils` on all nodes (installed via ansible `sys` role)

**How to resize an iSCSI volume:**
1. DSM > SAN Manager > expand the LUN
2. Delete/recreate the pod (Kubernetes re-mounts and runs `resize2fs` automatically)

**Why not dynamic iSCSI provisioning:**
Both official Synology CSI (lacks ARM64) and democratic-csi synology-iscsi (experimental) were evaluated and abandoned. Manual provisioning is adequate for this cluster's scale.

Keep existing LetsEncrypt and MariaDB sections intact. Add the new storage section at the top of the document (before the LetsEncrypt section), since storage architecture is the primary topic. The existing line 44 NFS note ("setting up nfs, dont squash permissions...") can stay where it is -- it's operational detail, not architecture. Match the document's existing informal tone.

**Files modified:** `docs/02-persistence.md`

---

### Phase 1 Checkpoint

At this point:
- Nodes have `iscsi-initiator-utils` installed and `iscsid` running
- iSCSI LUN exists on Synology and connectivity is verified from both nodes
- Reference files and documentation are updated

**Jellyfin is still running on NFS, completely unaffected.** Stop here and wait for explicit go-ahead before proceeding to Phase 2.

---

## Phase 2: Migration (Jellyfin downtime required)

**Point of no return.** Everything from here requires Jellyfin to be stopped. The migration is: stop Jellyfin, copy data from NFS to iSCSI LUN, swap the PV definition, redeploy. NFS data is preserved as a rollback path.

### Step 6: Stop Jellyfin and migrate config data

**Claude does this.** The mount path is unchanged: PVC `jellyfin-config` mounts at `/config` in the container (`jellyfin.yml:116-117`). Only the PV backing changes from `nfs:` to `iscsi:`. The `cp -a` preserves directory structure and permissions, so Jellyfin finds its files in the same place.

```bash
# stop jellyfin using existing make target
make jellyfin-stop

# on a node via SSH: login to iSCSI, format, mount, copy from NFS
sudo iscsiadm -m node --targetname iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 --portal 192.168.1.200:3260 --login
# use deterministic device path to avoid formatting the wrong device
sudo mkfs.ext4 /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-1
sudo mkdir -p /mnt/jellyfin-iscsi /mnt/jellyfin-nfs
sudo mount /dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-1 /mnt/jellyfin-iscsi
sudo mount -t nfs 192.168.1.200:/volume2/kube-nfs/v/jellyfin-config /mnt/jellyfin-nfs
sudo cp -a /mnt/jellyfin-nfs/* /mnt/jellyfin-iscsi/

# verify copy integrity
sudo du -sh /mnt/jellyfin-nfs /mnt/jellyfin-iscsi

# find and update database.xml locking behavior
# verify the actual path first (expected under data/ subdirectory)
sudo find /mnt/jellyfin-iscsi -name "database.xml" -type f
# then update -- remove Optimistic locking workaround, no longer needed on block storage
# SQLite can use proper filesystem-level locks on ext4
sudo sed -i 's|<LockingBehavior>Optimistic</LockingBehavior>|<LockingBehavior>Default</LockingBehavior>|' /mnt/jellyfin-iscsi/<path-from-find>/database.xml

# cleanup
sudo umount /mnt/jellyfin-nfs /mnt/jellyfin-iscsi
sudo iscsiadm -m node --targetname iqn.2000-01.com.synology:synology.default-target.7d1c64e1219 --portal 192.168.1.200:3260 --logout
```

Note: NFS data is preserved untouched as a fallback.

---

### Step 7: Update `kube/media/jellyfin/storage.yml`

**Claude does this.** Replace ONLY the first YAML document (the PV) -- change `nfs:` to `iscsi:`. The two PVC documents remain unchanged. The complete file should be:

```yaml
---
apiVersion: v1
kind: PersistentVolume
metadata:
  labels:
    app.kubernetes.io/name: jellyfin
  name: jellyfin-config
spec:
  storageClassName: ""
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  iscsi:
    targetPortal: 192.168.1.200:3260
    iqn: iqn.2000-01.com.synology:synology.default-target.7d1c64e1219
    lun: 1
    fsType: ext4
    readOnly: false
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app.kubernetes.io/name: jellyfin
  name: jellyfin-config
  namespace: media
spec:
  storageClassName: ""
  volumeName: jellyfin-config
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    app.kubernetes.io/name: jellyfin
  name: jellyfin-volitile
  namespace: media
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
  volumeMode: Filesystem
```

`jellyfin.yml` requires **no changes**.

**Files modified:** `kube/media/jellyfin/storage.yml`

---

### Step 8: Redeploy Jellyfin

**Claude does this.**
```bash
cd kube/
# jellyfin-remove runs kubectl delete -f storage.yml (which contains both PV and PVC).
# The -kubectl prefix in the Makefile ignores errors. The PV with Retain policy
# may linger in Released state. Clean up explicitly to be safe.
make jellyfin-remove
kubectl delete pv jellyfin-config --ignore-not-found
make jellyfin-deploy
```

---

### Step 9: Verify

**Claude does this** (user verifies web UI separately).
- `make jellyfin-status` -- PVC Bound, pod Running
- `make jellyfin-logs` -- no SQLite locking errors
- SSH to the node running the pod, `lsblk` shows iSCSI device
- **User:** open Jellyfin web UI, confirm library and settings intact

---

## Files Modified Summary

| File | Phase | Change |
|------|-------|--------|
| `ansible/roles/sys/tasks/main.yml` | 1 | Add `iscsi-initiator-utils` package + `iscsid.service` |
| `kube/media/jellyfin/conf/database.xml` | 1 | Change LockingBehavior from Optimistic to Default |
| `kube/media/jellyfin/conf/NOTE.md` | 1 | Update Database Locking section |
| `docs/02-persistence.md` | 1 | Add storage architecture documentation |
| `kube/media/jellyfin/storage.yml` | 2 | Replace NFS PV with iSCSI PV |

## User Actions Required

1. ~~**Step 2 (Phase 1):** Create iSCSI target + LUN in Synology DSM web UI, provide the IQN~~ **DONE**
2. **Step 9 (Phase 2):** Verify Jellyfin web UI works after migration

## Future: Arr Apps

When redeploying sonarr/radarr/prowlarr, repeat steps 2, 7, 8 for each app:
- User creates a LUN per app in DSM
- Claude updates each app's `storage.yml` with iSCSI PV

---

## Work Log

### Phase 1 (2026-02-17)

**Step 1 -- DONE.** Added `iscsi-initiator-utils` and `iscsid.service` to `ansible/roles/sys/tasks/main.yml`. Ran `ansible-playbook k3-install.yml --tags slow` successfully. Both nodes show package installed, iscsid active, unique initiator names:
- k3-m1: `iqn.1994-05.com.redhat:c98b344a5e85`
- k3-n1: `iqn.1994-05.com.redhat:b75dcd58d254`

Note: the `--tags slow` run also triggered `k3s/common` tasks which restarted k3s on both nodes (idempotent, no issues).

**Step 2 -- DONE.** NFS volume is 4.7 GiB, fits within 10 GiB LUN. LUN was already created by user in DSM.

**Step 3 -- DONE.** iSCSI discovery and login/logout tested on both nodes. Both can see and attach the LUN.

**Finding: LUN ID mismatch.** DSM shows LUN 0, but the iSCSI device path on both nodes reports `lun-1`: `/dev/disk/by-path/ip-192.168.1.200:3260-iscsi-iqn.2000-01.com.synology:synology.default-target.7d1c64e1219-lun-1`. Updated the plan's Phase 2 PV spec and device paths from `lun: 0` / `lun-0` to `lun: 1` / `lun-1`.

**Step 4 -- DONE.** Updated `kube/media/jellyfin/conf/database.xml` (LockingBehavior -> Default) and `kube/media/jellyfin/conf/NOTE.md` (added note about iSCSI making the workaround unnecessary).

**Step 5 -- DONE.** Added storage architecture section to `docs/02-persistence.md` covering all storage patterns, iSCSI provisioning/resizing procedures, and rationale for manual provisioning.

**Phase 1 complete.** All infrastructure prep done. Jellyfin remains running on NFS, unaffected. Awaiting go/no-go decision for Phase 2.

### Phase 2 (2026-02-17)

**Step 6 -- DONE.** Stopped Jellyfin (`make jellyfin-stop`). On k3-m1: logged into iSCSI, formatted LUN as ext4 (UUID: `a0bfcfe5-e3a6-4a24-bf98-bfac73ee55d4`), mounted both iSCSI and NFS, copied data with `cp -a`. Verified both sides at 4.7 GiB. Updated `database.xml` on the iSCSI volume (LockingBehavior Optimistic -> Default). Unmounted and logged out cleanly. NFS data preserved as fallback.

Note: `database.xml` was at `/mnt/jellyfin-iscsi/database.xml` (root of config volume, not in a subdirectory as the plan speculated).

**Step 7 -- DONE.** Updated `kube/media/jellyfin/storage.yml`: replaced NFS PV with iSCSI PV (`lun: 1`, `fsType: ext4`). PVCs unchanged.

**Step 8 -- DONE.** Ran `make jellyfin-remove`, confirmed PV deleted, ran `make jellyfin-deploy`. All resources created cleanly.

**Step 9 -- DONE (Claude's part).** Verification results:
- PVCs: both Bound (`jellyfin-config` -> PV `jellyfin-config`, `jellyfin-volitile` -> local-path)
- Pod: 1/1 Ready, Running, 0 restarts, scheduled on k3-n1
- Logs: clean startup, no SQLite locking errors. Database locking mode reported as `NoLock` (Jellyfin's name for the "Default" setting -- uses SQLite native locking)
- iSCSI device: `sda` (10G) visible on k3-n1, mounted at kubelet volume path for `jellyfin-config`
- Startup completed in ~43 seconds

**Awaiting user verification:** Jellyfin web UI (library, settings, playback).
