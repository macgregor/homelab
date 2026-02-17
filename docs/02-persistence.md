
1. Synology
  * set up lets encrypt cert
  * set up volumes for kubernetes, create kubernetes user for synology-csi
  * setup volume for mariadb, install mariadb, create mariadb kubernetes user and database
2. setup k3s to use mariadb
  * ssl
  * enabling statistics: https://mariadb.com/kb/en/user-statistics/
3. install synology-csi driver
  * synology iscsi driver suuuuucks

## Storage Patterns

The cluster uses several storage patterns depending on the workload:

**NFS (democratic-csi dynamic provisioning)** -- StorageClasses `synology-nfs-app-data-retain` and `synology-nfs-app-data-delete` via the democratic-csi `nfs-client` driver. Auto-creates subdirectories under `/volume2/kube-nfs`. Mount options: `noatime,nolock,nfsvers=3`. No volume expansion or snapshots. Not suitable for SQLite or other databases that need POSIX file locking.

**NFS (static PV)** -- Manually created PV/PVC pointing to pre-existing NFS paths (e.g., `/volume2/kube-nfs/v/<app>-config`). Same locking limitations as dynamic NFS. Uses `storageClassName: ""` to prevent dynamic provisioner matching.

**NFS (direct volume mount)** -- Media files mounted directly in pod spec, no PV/PVC. For read-heavy workloads where locking isn't an issue.

**iSCSI (static PV)** -- Block storage for apps with SQLite databases (Jellyfin, arr apps). Manually provisioned LUNs on Synology Volume 2 via DSM SAN Manager. Supports proper POSIX locking, volume expansion, and snapshots. Formatted ext4.

**local-path** -- Node-local storage via k3s default StorageClass. For volatile/cache data (e.g., transcode temp files). Not persistent across nodes.

### Creating a new iSCSI volume

1. DSM > SAN Manager > create target + thin-provisioned LUN on Volume 2
2. Note the IQN, portal is `192.168.1.200:3260`
3. A fresh target with a single LUN is always LUN ID 0 (verify via `ls /dev/disk/by-path/ | grep iscsi` after login)
4. Add a static PV to the app's `storage.yml` with `iscsi:` volume source
5. Requires `iscsi-initiator-utils` on all nodes (installed via the ansible `sys` role)

### Resizing an iSCSI volume

1. DSM > SAN Manager > expand the LUN
2. Delete/recreate the pod (Kubernetes re-mounts and runs `resize2fs` automatically)

### Why not dynamic iSCSI provisioning?

Both the official Synology CSI driver (lacks ARM64 images) and democratic-csi's synology-iscsi mode (experimental) were evaluated and abandoned. Manual provisioning is adequate for this cluster's scale.

## LetsEncrypt, acme.sh

* there is a user defined task configured in the synology control panel that periodically runs `/var/services/homes/certadmin/cert-renew.sh`
    * this file contains passwords/api tokens
    * if encountering errors, you can edit this script and add `--debug 2` to the commands its running to get the acme script to provide more information
* theres a synology system user called "certadmin" we created in the synology control panel that is used by the script to log into the synology admin panel and update the cert when its renewed
* the scheduled tasks are being run as the root system user, if using ssh you should `sudo su` first
* acme.sh + cloudflare DNS: https://github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_cf
    * in particular `/var/services/homes/certadmin/cert-renew.sh` needs an api token/permissions from cloudflare, if something breaks with renewal its probably this authentication piece 
* upgrade the acme scripts (`sudo su` first): `/usr/local/share/acme.sh/acme.sh --force --upgrade --nocron --home /usr/local/share/acme.sh`


Resources:
* https://dr-b.io/post/Synology-DSM-7-with-Lets-Encrypt-and-DNS-Challenge
* https://www.cyberciti.biz/faq/issue-lets-encrypt-wildcard-certificate-with-acme-sh-and-cloudflare-dns/
* https://github.com/SynologyOpenSource/synology-csi
* https://github.com/christian-schlichtherle/synology-csi-chart
* https://rene.jochum.dev/rancher-k3s-with-galera/ (only somewhat applicable)

```
$ ssh macgregor@synology

# login as root mysql user using the admin password configured in DSM
$ mysql -u root -p
Enter password:

MariaDB [(none)]> CREATE DATABASE `kubernetes`;
MariaDB [(none)]> CREATE user 'kubernetes'@'%' IDENTIFIED BY 'password';
MariaDB [(none)]> GRANT ALL PRIVILEGES ON `kubernetes`.* TO 'kubernetes'@'%';
```

setting up nfs, dont squash permissions and grant "everyone" superduper access
https://kb.synology.com/en-us/DSM/tutorial/allow_delete_in_folder_except_one_file
