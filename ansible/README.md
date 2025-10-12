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
6. `ansible-galaxy install -r requirements.yml`

**Config points**:
1. cluster hostnames in ansible inventory: [hosts.ini](./ansible/inventory/hosts.ini)
2. default SSH user name (varies by distro, e.g. "rocky" or "ubuntu") and local ssh key paths and sudo group name: [all.yaml](./ansible/inventory/group_vars/all.yaml)

**Resources**:
1. https://github.com/k3s-io/k3s-ansible

**tl;dr**:
```
$ ansible-galaxy install -r requirements.yml
$ ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml
$ ansible-playbook -i inventory/hosts.ini k3-install.yml

# for development, skip slow tasks like app installs
$ ansible-playbook -i inventory/hosts.ini k3-install.yml --skip-tags=slow
```

### Initial System Config
You should only need to run this once. It sets up some basic user accounts
on the hosts and removes the defaults.

You will need to set the `default_user` and `default_password` ansible vars in `inventory/group_vars/all.yaml` based on your distros documentation. For rocky linux 9.2 the user is "rocky" and the password is "rockylinux" ([rocky linux 9.2 rpi image readme](https://dl.rockylinux.org/pub/sig/9/altarch/aarch64/images/README.txt)). This is only used for inital user creation which will create your user with secure ssh access.

```
$ ssh-add ~/.ssh/macgregor.id_rsa
$ ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml
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

Note: server token awkwardness with external cluster state persistence

So k3s uses some token system for masters and agents to join a cluster. The first time the master node gets started it generates these tokens. This ansible script handles providing that token to the non-master nodes, however it does account very well for k3s upgrades or re-installs when you need to reconnect a "new" master node to the existing cluster. In these situations you need to provide `--token ...` to the `k3s server` command invocation or you get errors like this when you try to start the k3s service on the new/updated master node:
```
level=fatal msg="starting kubernetes: preparing server: bootstrap data already found and encrypted with different token"
```

Right now I am always providing the token I received on my first install via the `kube_server_token` ansible var in `inventoy/group_vars/all.yaml` which eventually winds up on the master host in `/etc/systemd/system/k3s.service`. 

If this is a fresh cluster install, it may work by setting that var to an empty string the first run, then grabbing the token from server:
```
sudo cat /var/lib/rancher/k3s/server/token | rev | cut -d':' -f1 | rev
```

This same problem will occur for multi-master setups as well, hopefully I will solve it then.

# Resources
https://rene.jochum.dev/rancher-k3s-with-galera/
