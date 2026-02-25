---
name: rpis-and-k3s
description: >
  Load this document when working with k3s configuration, cluster topology,
  control-plane settings, node roles, or understanding the compute layer architecture.
categories: [kubernetes, infrastructure]
tags: [k3s, cluster-topology, control-plane, compute, configuration]
related_docs:
  - docs/00-getting-started.md
  - docs/01-infrastructure-provisioning.md
  - docs/03-persistence.md
complexity: intermediate
---

# RPis and k3s

This document covers the Kubernetes cluster topology, k3s configuration, and compute-layer provisioning. For hardware details and project overview, see [Getting Started](00-getting-started.md). For how the MikroTik router and Raspberry Pis are provisioned with Ansible, see [Infrastructure Provisioning](01-infrastructure-provisioning.md).

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
| Traefik | ingress-nginx | Dual ingress controller setup needed (see [Networking](04-networking.md)) |
| ServiceLB | MetalLB | L2 mode with a dedicated IP pool (see [Networking](04-networking.md)) |
| Cloud controller | None | No cloud provider |
| Helm controller | Helmfile | Prefer Helmfile for chart management |

The single-binary packaging can make debugging lower-level issues less straightforward since components aren't separate processes with individual logs.

## Provisioning

Raspberry Pi provisioning is handled by Ansible playbooks in `ansible/`. See [Infrastructure Provisioning](01-infrastructure-provisioning.md) for setup prerequisites, bootstrap process, and troubleshooting.

In brief: `rpi-bootstrap.yml` creates a secure SSH user (one-time), then `k3-install.yml` applies OS configuration, installs k3s, and deploys the cluster (idempotent).

See [Infrastructure Provisioning](01-infrastructure-provisioning.md) for detailed provisioning steps, prerequisites, and troubleshooting. Key configuration files:

- **`ansible/inventory/hosts.ini`** -- Cluster hostnames and group membership
- **`ansible/inventory/group_vars/all.yaml`** -- SSH user, key paths, k3s version, and environment variable lookups

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
- [Infrastructure Provisioning](01-infrastructure-provisioning.md) -- Ansible provisioning of MikroTik and Pis
- [Persistence](03-persistence.md) -- Synology NAS and Kubernetes storage
- [Networking](04-networking.md) -- MetalLB, ingress, DNS, TLS
- [Maintenance](07-maintenance.md) -- k3s upgrade procedures
