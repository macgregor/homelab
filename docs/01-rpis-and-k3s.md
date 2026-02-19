# RPis and k3s

This document covers the foundational layers of the homelab: the Raspberry Pi hardware, the k3s Kubernetes distribution, and the Ansible playbooks that provision both. For the hardware bill of materials and project goals, see [Getting Started](00-getting-started.md).

## Cluster Topology

The cluster consists of two Raspberry Pi 4B nodes running Rocky Linux 9 (ARM):

| Hostname | Role | RAM | IP | Scheduling |
| -------- | ---- | --- | -- | ---------- |
| `k3-m1` | control-plane (server) | 4 GB | 192.168.1.210 | Tainted `CriticalAddonsOnly=true:NoSchedule` -- runs only system components |
| `k3-n1` | worker (agent) | 8 GB | 192.168.1.211 | Schedules all application workloads |

The Ansible inventory (`ansible/inventory/hosts.ini`) defines these two groups (`master` and `node`), combined under a `cluster` parent group for tasks that apply to all nodes.

## Why k3s

[k3s](https://k3s.io/) was chosen for its low resource footprint on ARM hardware. It ships as a single binary that bundles the Kubernetes API server, scheduler, controller-manager, and kubelet.

Several of the bundled components are disabled in favor of separately managed replacements:

| Disabled Component | Replacement | Why |
| ------------------- | ----------- | --- |
| CoreDNS | (re-deployed manually) | More control over configuration |
| Traefik | ingress-nginx | Dual ingress controller setup needed (see [Networking](03-networking.md)) |
| ServiceLB | MetalLB | L2 mode with a dedicated IP pool (see [Networking](03-networking.md)) |
| Cloud controller | None | No cloud provider |
| Helm controller | Helmfile | Prefer Helmfile for chart management |

The single-binary packaging can make debugging lower-level issues less straightforward since components aren't separate processes with individual logs.

## Provisioning with Ansible

All Ansible playbooks and roles live in `ansible/`. Provisioning is a two-phase process:

1. **`rpi-bootstrap.yml`** -- One-time system user setup (run once per fresh OS install)
2. **`k3-install.yml`** -- OS configuration, package installation, and k3s deployment (idempotent, safe to re-run)

### Prerequisites

- Rocky Linux 9 ARM flashed onto SD cards and booted
- Static IPs and hostnames assigned on the router (the Pis must be resolvable by hostname)
- SSH key generated locally
- Ansible installed on the control machine (also `sshpass` for the bootstrap step)
- Galaxy dependencies installed: `ansible-galaxy install -r requirements.yml`

### Phase 1: Bootstrap (`rpi-bootstrap.yml`)

Creates a dedicated user account with SSH key auth and passwordless sudo, then removes the default `rocky` user. This playbook authenticates using the distro's default credentials (`rocky`/`rockylinux`), so it only needs to run once per fresh install.

Also expands the root filesystem to fill the SD card.

```bash
cd ansible/
ssh-add ~/.ssh/macgregor.id_rsa
ansible-playbook -i inventory/hosts.ini rpi-bootstrap.yml
```

The default credentials (`default_user` and `default_password`) are configured in `ansible/inventory/group_vars/all.yaml`. These vary by distro -- for Rocky Linux 9 the defaults are `rocky`/`rockylinux` (see the [Rocky Linux ARM image readme](https://dl.rockylinux.org/pub/sig/9/altarch/aarch64/images/README.txt)).

### Phase 2: Install (`k3-install.yml`)

This is the main provisioning playbook. It applies three role layers in sequence:

**`sys` role** (all nodes) -- Base OS configuration:
- Locale and timezone (`America/New_York`)
- System packages: `nfs-utils`, `iscsi-initiator-utils`, `dnf-automatic`, diagnostics tools
- Automatic OS updates via `dnf-automatic` with a reboot timer
- Raspberry Pi boot config: CPU overclock (2 GHz), GPU overclock, boot speed optimizations, PoE HAT fan curves
- Firewall disabled (k3s manages its own iptables rules)

**`k3s/common` role** (all nodes) -- Shared k3s setup:
- Enables cgroups via kernel boot parameters (required for container resource limits)
- Kernel sysctl tuning (`ip_forward`, `vm.max_map_count`)
- Downloads the k3s binary (version pinned in `ansible/inventory/group_vars/all.yaml`)
- Deploys a cgroup cleanup service for faster shutdown (addresses [k3s#2400](https://github.com/k3s-io/k3s/issues/2400))
- Configures container image garbage collection and log rotation via kubelet args
- Sets up a private container registry config (`registries.yaml`)

**`k3s/master` role** (master only) -- Starts the k3s server, waits for the agent token to be generated, stores it as an Ansible fact for the node role, and copies the kubeconfig to the user's home directory.

**`k3s/node` role** (workers only) -- Writes the agent token (received from the master role) and starts the k3s agent, pointed at the master's API server.

```bash
cd ansible/
ssh-add ~/.ssh/macgregor.id_rsa
ansible-playbook -i inventory/hosts.ini k3-install.yml

# for development, skip slow tasks like package installs and service restarts
ansible-playbook -i inventory/hosts.ini k3-install.yml --skip-tags=slow
```

Key configuration files:
- **`ansible/inventory/hosts.ini`** -- Cluster hostnames and group membership
- **`ansible/inventory/group_vars/all.yaml`** -- SSH user, key paths, sudo group, k3s version, and all secret variable lookups

### Retrieving Kubeconfig

After the install playbook completes, copy the kubeconfig from the master node:

```bash
scp macgregor@k3-m1:~/.kube/config ~/.kube/homelab_config
```

The kubeconfig is loaded via `.envrc` (direnv) -- see [Getting Started](00-getting-started.md).

## k3s Server Configuration

The master node's k3s service (`ansible/roles/k3s/master/templates/k3s.service`) runs `k3s server` with these flags:

**External datastore**: Cluster state is persisted to a MySQL database on the Synology NAS (`--datastore-endpoint`) rather than the default embedded etcd. This avoids wearing out the SD card with etcd writes and allows the cluster to be rebuilt from scratch without losing state.

**Node taint**: `--node-taint CriticalAddonsOnly=true:NoSchedule` prevents application workloads from scheduling on the 4 GB master node, reserving it for control-plane components.

**Kubelet tuning** (applied to both master and agent):
- Image garbage collection at 70%/50% thresholds
- Container logs capped at 5 files, 10 MB each
- Extended runtime request timeout (10 minutes)

## Hardware Tuning

The `sys` role deploys a custom `/boot/config.txt` with:

- **CPU overclock**: 2 GHz (up from 1.5 GHz default), `over_voltage=6`
- **GPU overclock**: 750 MHz
- **Boot speed**: Zero boot delay, Wi-Fi and Bluetooth disabled, splash screen disabled
- **PoE HAT fan curves**: Fans ramp up starting at 65C, reaching full speed at 80C

## Server Token and Cluster Recovery

k3s uses tokens for nodes to join the cluster. The master generates these on first start. Ansible handles passing the agent token from master to worker nodes automatically.

On a fresh cluster install (no existing MySQL state), `KUBE_SERVER_TOKEN` can be left empty for the first run. After the master starts, grab the generated token for future use:

```bash
sudo cat /var/lib/rancher/k3s/server/token | rev | cut -d':' -f1 | rev
```

When reinstalling k3s on the master against an existing datastore (e.g., during upgrades), it must reconnect using the original server token. This token is stored in the `KUBE_SERVER_TOKEN` environment variable and injected via Ansible. Without it, k3s fails with:

```
level=fatal msg="starting kubernetes: preparing server: bootstrap data already found and encrypted with different token"
```

When recovering a lost worker node (fresh OS install), you may also need to delete the old node secret from the master:

```bash
kubectl -n kube-system delete secrets k3-n1.node-password.k3s
```

## Secrets and Configuration

Ansible variables are defined in `ansible/inventory/group_vars/all.yaml`. Sensitive values (user password, k3s server token, MySQL credentials, Docker registry credentials) are read from environment variables via `lookup('env', ...)`, sourced from `.envrc` (gitignored).

## References

- [k3s-ansible](https://github.com/k3s-io/k3s-ansible) -- The upstream project this Ansible setup was originally based on

## Related Documentation

- [Getting Started](00-getting-started.md) -- Hardware details, software stack overview
- [Persistence](02-persistence.md) -- Synology NAS and Kubernetes storage
- [Networking](03-networking.md) -- MetalLB, ingress, DNS, TLS
- [Maintenance](06-maintenance.md) -- k3s upgrade procedures
- [Saving Your SD Cards](07-saving-your-sdcards.md) -- Reducing SD card wear
