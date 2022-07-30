# Part 1 - Initialize a Raspberry Pi k3's Cluster with Ansible


## Improving Startup and Shutdown Times
* remove snap - ubuntu server comes with it by default not, just having it adds heavy startup times even if you dont have any deps installed via snap
* kill cgroup processes (i.e. crio container processes) on shutdown
    * https://github.com/k3s-io/k3s/issues/2400#issuecomment-1013798094
* overclock cpu

For full details see the [Ansible readme](./ansible/README.md)

```
# after flashing Ubuntu server onto SD cards and logging in once to set a password
$ ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml --ask-pass
$ ansible-playbook -i inventory/hosts.ini k3-install.yml
$ kubectl get nodes -o wide
NAME    STATUS   ROLES                  AGE   VERSION        INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
k3-m1   Ready    control-plane,master   23h   v1.23.5+k3s1   192.168.1.210   <none>        Ubuntu 20.04.4 LTS   5.4.0-1059-raspi   containerd://1.5.10-k3s1
k3-n1   Ready    <none>                 81s   v1.23.5+k3s1   192.168.1.211   <none>        Ubuntu 20.04.4 LTS   5.4.0-1059-raspi   containerd://1.5.10-k3s1
```
