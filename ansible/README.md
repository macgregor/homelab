# Initialize a Raspberry Pi k3's Cluster with Ansible

**Prereqs**:
1. Ubuntu Server flashed onto flashcards for the Raspberry Pi's
2. Make sure you can resolve hosts from where you are running Ansible
  * simply assigning each node a static IP w/ hostname on my FreshTomato router was enough for me
3. Log into each host once to set a new password for the `ubuntu` user
4. Have an SSH key generated to connect to hosts with
5. Ansible installed (will also need sshpass for bootstrapping: `brew install hudochenkov/sshpass/sshpass`)

**Config points**:
1. cluster hostnames in ansible inventory: [hosts.ini](./ansible/inventory/hosts.ini)
2. remote user name and ssh key paths: [all.yaml](./ansible/inventory/group_vars/all.yaml)

**Resources**:
1. https://github.com/k3s-io/k3s-ansible

**tl;dr**:
```
$ ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml --ask-pass
$ ansible-playbook -i inventory/hosts.ini k3-install.yml
```

### Initial System Config
You should only need to run this once. It sets up some basic user accounts
on the hosts and removes the defaults.

```
$ ssh-add ~/.ssh/macgregor.id_rsa
$ ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml --ask-pass
```

### Installing k3s
This will update the packages on the host and install k3s. The host may be
rebooted once. After running this you can ssh to the master node and try out
kubectl

```
$ ssh-add ~/.ssh/macgregor.id_rsa
$ ansible-playbook -i inventory/hosts.ini k3-install.yml
$ mv ~/.kube/config ~/.kube/config.backup; scp macgregor@k3-m1:/home/macgregor/.kube/config ~/.kube/homelab_config
$ kubectl get nodes -o wide
NAME    STATUS   ROLES                  AGE   VERSION        INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
k3-m1   Ready    control-plane,master   23h   v1.23.5+k3s1   192.168.1.210   <none>        Ubuntu 20.04.4 LTS   5.4.0-1059-raspi   containerd://1.5.10-k3s1
k3-n1   Ready    <none>                 81s   v1.23.5+k3s1   192.168.1.211   <none>        Ubuntu 20.04.4 LTS   5.4.0-1059-raspi   containerd://1.5.10-k3s1
```

# Resources
https://rene.jochum.dev/rancher-k3s-with-galera/