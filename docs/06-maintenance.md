# k3s Upgrades

1. pick a new version from https://github.com/k3s-io/k3s/releases (probably look for "Latest")
2. update the k3s version in `ansible/inventory/group_vars/all.yaml`:
```
k3s_version: v1.27.2+k3s1
```
3. Run `ansible-playbook k3-install.yml`.

## Agent Error rejoining cluster

https://github.com/k3s-io/k3s/issues/802#issuecomment-841748960

```
Jun 02 20:15:03 k3-n1 k3s[2335]: time="2024-06-02T20:15:03-04:00" level=info msg="Waiting to retrieve agent configuration; server is not ready: Node password rejected, duplicate hostname or contents of '/etc/rancher/node/password' may not match server passwd entry
```

Solution: from the master node (or any connected kubectl) run `kubectl -n kube-system delete secret <agent-node-name>.node-password.k3s`

# Server OS Upgrade

DONT DO IT. Its not worth the pain. Start with a fresh install instead.

# Rotating k3s Certs

https://docs.k3s.io/cli/certificate#rotating-self-signed-ca-certificates

```
wget https://raw.githubusercontent.com/k3s-io/k3s/master/contrib/util/rotate-default-ca-certs.sh
sudo bash rotate-default-ca-certs.sh
sudo k3s certificate rotate-ca --path=/var/lib/rancher/k3s/server/rotate-ca
sudo systemctl restart k3s
```

## Cert Weirdness recreating master node

```
Dec 28 11:43:36 k3-m1 k3s[9577]: time="2023-12-28T11:43:36-05:00" level=fatal msg="/var/lib/rancher/k3s/server/tls/etcd/peer-ca.crt, /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt, /var/lib/rancher/k3s/server/cred/ipsec.psk, /var/lib/rancher/k3s/server/tls/request-header-ca.crt, /var/lib/rancher/k3s/server/tls/server-ca.crt, /var/lib/rancher/k3s/server/tls/client-ca.crt, /var/lib/rancher/k3s/server/tls/client-ca.key, /var/lib/rancher/k3s/server/tls/etcd/peer-ca.key, /var/lib/rancher/k3s/server/tls/etcd/server-ca.key, /var/lib/rancher/k3s/server/tls/request-header-ca.key, /var/lib/rancher/k3s/server/tls/server-ca.key, /var/lib/rancher/k3s/server/tls/service.key newer than datastore and could cause a cluster outage. Remove the file(s) from disk and restart to be recreated from datastore."
```

```
> sudo rm /var/lib/rancher/k3s/server/tls/etcd/peer-ca.crt /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt /var/lib/rancher/k3s/server/cred/ipsec.psk /var/lib/rancher/k3s/server/tls/request-header-ca.crt /var/lib/rancher/k3s/server/tls/server-ca.crt /var/lib/rancher/k3s/server/tls/client-ca.crt /var/lib/rancher/k3s/server/tls/client-ca.key /var/lib/rancher/k3s/server/tls/etcd/peer-ca.key /var/lib/rancher/k3s/server/tls/etcd/server-ca.key /var/lib/rancher/k3s/server/tls/request-header-ca.key /var/lib/rancher/k3s/server/tls/server-ca.key /var/lib/rancher/k3s/server/tls/service.key
> sudo systemctl restart k3s
```
# Image Cleanup

kubernetes nodes automatically perform image garbage collection. You can find documentation on the default thresholds here:
https://kubernetes.io/docs/concepts/cluster-administration/kubelet-garbage-collection/#user-configuration

You can tune these thresholds on your k3s nodes by adding arguments to the service command line:
```
--kubelet-arg=image-gc-high-threshold=70 --kubelet-arg=image-gc-low-threshold=50
```

## Manual
```
sudo k3s crictl images
sudo k3s crictl rmi --prune
```

# Helm Delete Fails - policy/v1beta1 PodSecurityPolicy

https://www.suse.com/support/kb/doc/?id=000021053

```
> helmfile --debug --file app/teleport/helmfile.yaml delete
...
helm:HGbUj> uninstall.go:95: [debug] uninstall: Deleting teleport-cluster
helm:HGbUj> uninstall.go:117: [debug] uninstall: Failed to delete release: [unable to build kubernetes objects for delete: unable to recognize "": no matches for kind "PodSecurityPolicy" in version "policy/v1beta1"]
Error: failed to delete release: teleport-cluster
...
> helm plugin install https://github.com/helm/helm-mapkubeapis
> helm mapkubeapis teleport-cluster --namespace teleport

# should work now
> helmfile --file ./app/teleport/helmfile.yaml delete
```

helm mapkubeapis metallb --namespace metallb

# dnf/dnf-automatic Failures

Check the dnf-automatic update logs with `systemctl status dnf-automatic-install.service`:
```
# note you can 
[macgregor@k3-n1 ~]$ systemctl status dnf-automatic-install.service
× dnf-automatic-install.service - dnf automatic install updates
     Loaded: loaded (/usr/lib/systemd/system/dnf-automatic-install.service; static)
     Active: failed (Result: exit-code) since Sun 2024-06-02 06:21:36 EDT; 10h ago
TriggeredBy: ● dnf-automatic-install.timer
   Main PID: 476157 (code=exited, status=1/FAILURE)
        CPU: 30.754s

Jun 02 06:20:56 k3-n1 dnf-automatic[476157]: Last metadata expiration check: 4:07:16 ago on Sun 02 Jun 2024 02:13:40 AM EDT.
Jun 02 06:21:02 k3-n1 dnf-automatic[476157]: Public key for raspberrypi2-kernel4-6.1.31-v8.1.el9.altarch.aarch64.rpm is not installed
Jun 02 06:21:03 k3-n1 dnf-automatic[476157]: Public key for raspberrypi2-firmware-6.1.31-v8.1.el9.altarch.aarch64.rpm is not installed
Jun 02 06:21:36 k3-n1 dnf-automatic[476157]: The downloaded packages were saved in cache until the next successful transaction.
Jun 02 06:21:36 k3-n1 dnf-automatic[476157]: You can remove cached packages by executing 'dnf clean packages'.
Jun 02 06:21:36 k3-n1 dnf-automatic[476157]: Error: GPG check FAILED
Jun 02 06:21:36 k3-n1 systemd[1]: dnf-automatic-install.service: Main process exited, code=exited, status=1/FAILURE
Jun 02 06:21:36 k3-n1 systemd[1]: dnf-automatic-install.service: Failed with result 'exit-code'.
```

Unfortunately, dnf-automatic does not automatically import new GPG keys when they change. Normally if this happens DNF will prompt you if you want to import the key for not, but I have not found a way to make this happen easily when dnf-automatic is piloting things. So you need to grab and import the new GPG key so dnf-automatic can start running again. In my case, this meant updating a rocky linux package that provides the new gpg key, then updating one of the failing packages to import the key:

```
sudo dnf update --disablerepo=* --enablerepo=extras
sudo dnf update -y raspberrypi2-kernel4 raspberrypi2-firmware
```