# Persistence

This document covers the Synology NAS, MariaDB datastore, and Kubernetes storage patterns used by the cluster. For the hardware overview, see [Getting Started](00-getting-started.md). For k3s configuration that references the datastore, see [RPis and k3s](02-rpis-and-k3s.md).

## Synology NAS

The Synology DS720+ (`192.168.1.200`) serves two roles: network storage for the Kubernetes cluster and host for the MariaDB database that backs k3s.

### Volume Layout

| Synology Volume | Path | Purpose |
| --------------- | ---- | ------- |
| Volume 1 | `/volume1/Media` | Media library (movies, TV, music) -- mounted directly into media app pods |
| Volume 2 | `/volume2/kube-nfs` | Kubernetes application data -- both democratic-csi dynamic provisioning and static NFS PVs |
| Volume 2 | (SAN Manager LUNs) | iSCSI block storage for apps that need POSIX file locking |

### NFS Share Setup

NFS shares are configured manually in DSM Control Panel > Shared Folder > NFS Permissions. The key settings: no permission squashing and broad access grants for the cluster subnet. See the [Synology KB on NFS permissions](https://kb.synology.com/en-us/DSM/tutorial/allow_delete_in_folder_except_one_file) for background.

Static NFS volumes follow the naming convention `/volume2/kube-nfs/v/<app>-config` and must be created on the Synology before the corresponding PV/PVC is applied.

## MariaDB (k3s Datastore)

k3s uses a MariaDB database on the Synology instead of embedded etcd. This moves write-heavy cluster state off the Raspberry Pi SD cards and onto the NAS's RAID-backed storage. The database was also useful for diagnosing disk activity on the NAS -- [enabling user statistics](https://mariadb.com/kb/en/user-statistics/) helped identify write patterns that led to adding SSD cache drives.

MariaDB is installed via DSM Package Center. The database and user are created manually:

```
$ ssh macgregor@synology

# log in as root mysql user using the admin password configured in DSM
$ mysql -u root -p

MariaDB [(none)]> CREATE DATABASE `kubernetes`;
MariaDB [(none)]> CREATE user 'kubernetes'@'%' IDENTIFIED BY '<password>';
MariaDB [(none)]> GRANT ALL PRIVILEGES ON `kubernetes`.* TO 'kubernetes'@'%';
```

The password must match the `KUBE_MYSQL_PASSWORD` environment variable in `.envrc`. k3s connects via the `--datastore-endpoint` flag in the server systemd unit -- see [RPis and k3s](01-rpis-and-k3s.md#k3s-server-configuration) for the connection details and Ansible variables.

## Storage Patterns

The cluster uses several storage patterns depending on the workload.

### Choosing a Pattern

| Workload Characteristic | Pattern | Example |
| ----------------------- | ------- | ------- |
| Needs POSIX file locking (SQLite, databases) | iSCSI (static PV) | Jellyfin config, arr app configs |
| General application config/data | NFS (dynamic or static PV) | AdGuard, Tdarr, Diun |
| Read-heavy media files, shared across pods | NFS (direct volume mount) | Media libraries |
| Volatile cache or temp files | local-path | Transcode scratch space |

NFS does not support reliable POSIX advisory locks, which causes SQLite database corruption. Apps that use SQLite (Jellyfin, Sonarr, Radarr, Prowlarr) were migrated from NFS to iSCSI to resolve this.

### NFS -- Dynamic Provisioning (democratic-csi)

StorageClasses `synology-nfs-app-data-retain` and `synology-nfs-app-data-delete` via the democratic-csi `nfs-client` driver. Auto-creates subdirectories under `/volume2/kube-nfs`. Mount options: `noatime,nolock,nfsvers=3`. No volume expansion or snapshots.

Only a PVC is needed -- no PV definition:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: example
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: synology-nfs-app-data-delete
```

Use `synology-nfs-app-data-retain` when data should survive PVC deletion; use `synology-nfs-app-data-delete` for disposable data.

### NFS -- Static PV

Manually created PV/PVC pointing to a pre-existing NFS path. Same locking limitations as dynamic NFS. Uses `storageClassName: ""` to prevent dynamic provisioner matching.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: app-config
spec:
  storageClassName: ""
  capacity:
    storage: 1Gi  # not enforced on NFS
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  nfs:
    path: /volume2/kube-nfs/v/app-config
    server: 192.168.1.200
    readOnly: false
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-config
  namespace: example
spec:
  storageClassName: ""
  volumeName: app-config
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

### NFS -- Direct Volume Mount

Media files mounted directly in the pod spec, no PV/PVC. For read-heavy workloads where locking is not an issue.

```yaml
volumes:
  - name: media
    nfs:
      server: 192.168.1.200
      path: /volume1/Media/media
containers:
  - name: app
    volumeMounts:
      - mountPath: /data
        name: media
```

### iSCSI -- Static PV

Block storage for apps that need POSIX file locking. Manually provisioned LUNs on Synology Volume 2 via DSM SAN Manager. Formatted ext4. Supports volume expansion and snapshots.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: app-config
spec:
  storageClassName: ""
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  iscsi:
    targetPortal: 192.168.1.200:3260
    iqn: iqn.2000-01.com.synology:synology.<target-name>.<id>
    lun: 1
    fsType: ext4
    readOnly: false
```

Requires `iscsi-initiator-utils` on all nodes (installed via the Ansible `sys` role).

**LUN ID numbering:** DSM SAN Manager displays LUN IDs starting at 0, but the iSCSI protocol and Linux kernel report them with an offset (e.g., DSM "LUN 0" appears as `lun-1` in `/dev/disk/by-path/`). Verify the correct ID by logging into the target from a node and checking `ls /dev/disk/by-path/ | grep iscsi`.

**Multiple LUNs per target:** Several apps can share a single iSCSI target with different LUN IDs. Each gets its own static PV pointing to the same IQN but a different `lun:` value.

### local-path

Node-local storage via the k3s default StorageClass. For volatile or cache data (e.g., transcode temp files). Data is not persistent across nodes and is lost if the pod moves.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-volatile
  namespace: example
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: local-path
```

### Creating an iSCSI Volume

1. DSM > SAN Manager > create a target and thin-provisioned LUN on Volume 2
2. Note the IQN and LUN ID (portal is `192.168.1.200:3260`)
3. Verify the LUN ID from a node: `sudo iscsiadm -m node --login` then `ls /dev/disk/by-path/ | grep iscsi`
4. Add a static PV/PVC to the app's `storage.yml` with the `iscsi:` volume source
5. Log out of the test session: `sudo iscsiadm -m node --logout`

### Resizing an iSCSI Volume

1. DSM > SAN Manager > expand the LUN
2. Delete and recreate the pod -- Kubernetes re-mounts and runs `resize2fs` automatically

### Why Not Dynamic iSCSI Provisioning?

Both the official Synology CSI driver and democratic-csi's synology-iscsi mode were evaluated and abandoned. The official Synology CSI driver lacks ARM64 container images. Democratic-csi's synology-iscsi mode remains marked experimental. For a cluster with a handful of stateful apps, manual LUN provisioning is simpler and more reliable.

## References

- [Synology CSI driver](https://github.com/SynologyOpenSource/synology-csi)
- [democratic-csi](https://github.com/democratic-csi/democratic-csi)

## Related Documentation

- [Getting Started](00-getting-started.md) -- Hardware details, software stack overview
- [Infrastructure Provisioning](01-infrastructure-provisioning.md) -- Ansible provisioning
- [RPis and k3s](02-rpis-and-k3s.md) -- k3s datastore configuration
- [Networking](04-networking.md) -- MetalLB, ingress, DNS, TLS (including Synology DSM LetsEncrypt certificates)
- [Saving Your SD Cards](08-saving-your-sdcards.md) -- Reducing SD card wear
