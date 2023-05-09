# Part 1 - Initialize a Raspberry Pi k3's Cluster with Ansible

If you've ever run Kubernetes on a cloud provider ([Amazon EKS](https://aws.amazon.com/eks/), [GKE](https://cloud.google.com/kubernetes-engine), etc) or using a local method such as [minikube](https://minikube.sigs.k8s.io/docs/), you may take for granted the bootstrapping steps that come with creating a Kubernetes cluster. Kubernetes is just fancy software, and it needs networking and compute resources to do so. So before we can start "just" deploying a bunch of cool containerized applications, we need to install it on some hardware. In this case a couple of Raspberry Pi 4B's.

This document will provide an overview of different decisions that you need to make and then detail bootstrapping the Raspberry Pis to configure the operating system and installing Kubernetes via Ansible. Most of this is basic Linux sys admin stuff, there will be little Kubernetes stuff other than details needed to install it on the nodes.

## Kube Flavors

There are a number of [kubernetes flavors](https://itnext.io/kubernetes-installation-methods-the-complete-guide-1036c860a2b3) to choose from:
* official k8s via [kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
* "lightweight" [K3s](https://k3s.io/)
* [microk8s](https://microk8s.io/)
* [kubespray](https://github.com/kubernetes-sigs/kubespray)
* ...

It can be a bit overwhelming and the Kubernetes landscape changes very quickly. I decided to go with [K3s](https://k3s.io/) since it was designed for low powered devices in particular, though I found myself disabling many of the bundled features that came with it and deploying my own versions (e.g. replacing [Traefik](https://traefik.io/) with [ingress-nginx](https://github.com/kubernetes/ingress-nginx)). k3s also repackages many of the core kubernetes components as a single binary which can be a bit confusing when trying to debug lower level issues. Always do your own research on the most up to date options available to find a solution that works best for your situation.

## Ansible and Server Preparation

Wip





## Improving Startup and Shutdown Times
* remove snap - ubuntu server comes with it by default not, just having it adds heavy startup times even if you dont have any deps installed via snap
* kill cgroup processes (i.e. crio container processes) on shutdown
    * https://github.com/k3s-io/k3s/issues/2400#issuecomment-1013798094
* overclock cpu

For full details see the [Ansible readme](../ansible/README.md)

```
# after flashing Ubuntu server onto SD cards and logging in once to set a password
$ ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml --ask-pass
$ ansible-playbook -i inventory/hosts.ini k3-install.yml
$ kubectl get nodes -o wide
NAME    STATUS   ROLES                  AGE   VERSION        INTERNAL-IP     EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
k3-m1   Ready    control-plane,master   23h   v1.23.5+k3s1   192.168.1.210   <none>        Ubuntu 20.04.4 LTS   5.4.0-1059-raspi   containerd://1.5.10-k3s1
k3-n1   Ready    <none>                 81s   v1.23.5+k3s1   192.168.1.211   <none>        Ubuntu 20.04.4 LTS   5.4.0-1059-raspi   containerd://1.5.10-k3s1
```
