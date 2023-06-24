# Initialize a Raspberry Pi k3's Cluster with Ansible

**Prereqs**:
1. Linux OS flashed onto flashcards for the Raspberry Pi's
    * I am using Rocky Linux 9 ([rpi readme](https://dl.rockylinux.org/pub/sig/9/altarch/aarch64/images/README.txt)) as of 6/23/2023
2. Make sure you can resolve hosts from where you are running Ansible
    * simply assigning each node a static IP w/ hostname on my FreshTomato router was enough for me
3. Depending on distro, you may need to SSH into each host once to set a new password for the default user
    * not required for Rock Linux 9
4. Have an SSH key generated to connect to hosts with
5. Ansible installed (will also need sshpass for bootstrapping: `brew install hudochenkov/sshpass/sshpass`)

**Config points**:
1. cluster hostnames in ansible inventory: [hosts.ini](./ansible/inventory/hosts.ini)
2. default SSH user name (varies by distro, e.g. "rocky" or "ubuntu") and local ssh key paths and sudo group name: [all.yaml](./ansible/inventory/group_vars/all.yaml)

**Resources**:
1. https://github.com/k3s-io/k3s-ansible

**tl;dr**:
```
$ ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml --ask-pass --ask-become-pass
$ ansible-playbook -i inventory/hosts.ini k3-install.yml

# for development, skip slow tasks like app installs
$ ansible-playbook -i inventory/hosts.ini k3-install.yml --skip-tags=slow
```

### Initial System Config
You should only need to run this once. It sets up some basic user accounts
on the hosts and removes the defaults.

```
$ ssh-add ~/.ssh/macgregor.id_rsa
$ ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml --ask-pass --ask-become-pass
```

### Installing k3s
This will update the packages on the host and install k3s. The host may be
rebooted once. After running this you can ssh to the master node and try out
kubectl

```
$ ssh-add ~/.ssh/macgregor.id_rsa
$ ansible-playbook -i inventory/hosts.ini k3-install.yml
$ mv ~/.kube/config ~/.kube/config.backup; scp macgregor@k3-m1:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab_config
$ kubectl get nodes -o wide
NAME    STATUS   ROLES                  AGE   VERSION        INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
k3-m1   Ready    control-plane,master   23h   v1.23.5+k3s1   192.168.1.210   <none>        Ubuntu 20.04.4 LTS   5.4.0-1059-raspi   containerd://1.5.10-k3s1
k3-n1   Ready    <none>                 81s   v1.23.5+k3s1   192.168.1.211   <none>        Ubuntu 20.04.4 LTS   5.4.0-1059-raspi   containerd://1.5.10-k3s1
```

# Resources
https://rene.jochum.dev/rancher-k3s-with-galera/