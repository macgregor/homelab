---
name: infrastructure-provisioning
description: >
  Load this document when provisioning or troubleshooting the MikroTik router or
  Raspberry Pi nodes, setting up initial SSH access, or running Ansible bootstrap
  and installation playbooks.
categories: [infrastructure, provisioning, automation]
tags: [ansible, mikrotik, raspberry-pi, ssh, bootstrap, installation]
related_docs:
  - docs/00-getting-started.md
  - docs/02-rpis-and-k3s.md
  - docs/appendix/mikrotik-routeros.md
complexity: intermediate
---

# Infrastructure Provisioning

This document covers automated provisioning of homelab infrastructure: the MikroTik router and Raspberry Pi cluster nodes. Both are managed via Ansible playbooks that handle the foundational setup needed before Kubernetes deployment.

For hardware details and project overview, see [Getting Started](00-getting-started.md).

## Provisioning Overview

Provisioning follows a bootstrap-then-configure pattern:

- **Bootstrap playbooks** (one-time): Handle initial setup with default/factory credentials. They prepare systems to be managed long-term by dedicated SSH users.
- **Configure playbooks** (idempotent): Safe to re-run. They maintain system state, applying configuration and security hardening.

| Target | Bootstrap | Configure | Scope |
|--------|-----------|-----------|-------|
| MikroTik router | `mikrotik-bootstrap.yml` | `mikrotik-configure.yml` | Subnet migration, identity, DHCP, DNS, security, auto-updates |
| Raspberry Pis | `rpi-bootstrap.yml` | `k3-install.yml` | System user, OS tuning, k3s installation |

## Prerequisites

- Ansible installed on control machine
- SSH key generated locally
- Galaxy dependencies: `ansible-galaxy collection install -r collections/requirements.yml`
  - Includes `community.routeros` for MikroTik RouterOS support
  - Also includes `ansible.netcommon` for network device abstractions
- For RouterOS SSH transport: `ansible-pylibssh` and `libssh-devel`
  - Fedora: `sudo dnf install libssh-devel sshpass && pip install ansible-pylibssh`
  - Other distros: consult `libssh` documentation for your package manager
- Configuration: SSH key path and username defined in `ansible/inventory/group_vars/all.yaml`

## MikroTik Router Provisioning

The MikroTik RB5009UPr+S+IN ships with factory defaults (192.168.88.1/24, no secure user). Two playbooks transform it into a managed network appliance.

### Prerequisites: Manual Setup

Before running the bootstrap playbook, the router requires two manual configuration steps:

**1. Enable Advanced Device Mode**

The RB5009 ships in "home" device-mode, which disables the scheduler needed for auto-updates. Switch to "advanced" mode using the factory SSH user:

```bash
ssh -o StrictHostKeyChecking=no admin@192.168.88.1
/system device-mode update mode=advanced
```

The router will respond: `update: please activate by turning power off or pressing reset or mode button in 5m00s`

Within 5 minutes, do ONE of:
- Press the reset/mode button on the front panel (hold 3-5 seconds until LED responds), OR
- Power-cycle the device (unplug, wait 10 seconds, plug back in)

After activation, wait ~2 minutes for the router to reboot. Verify with:

```bash
ssh admin@192.168.88.1
/system device-mode print | grep scheduler
```

Should return: `scheduler: yes`

**2. SSH Once and Set Factory User Password**

RouterOS requires one SSH login to initialize the `admin` user and dismiss startup dialogs. The router will force you to set a password:

```bash
ssh -o StrictHostKeyChecking=no admin@192.168.88.1
```

Set a temporary password when prompted. Record this as `MIKROTIK_DEFAULT_PASSWORD` in `.envrc`. After logout, the bootstrap playbook will use these credentials to connect and set up the long-term SSH user.

### Phase 1: Bootstrap (`mikrotik-bootstrap.yml`)

**One-time setup.** Migrates from factory defaults (192.168.88.1/24) to 192.168.1.0/24 and creates a secure SSH user for ongoing management.

**Running:**
```bash
cd ansible
ansible-playbook mikrotik-bootstrap.yml
```

**Verify:**
```bash
ping 192.168.1.1
ssh 192.168.1.1
```

### Phase 2: Configure (`mikrotik-configure.yml`)

**Idempotent.** Applies system configuration, security hardening, and automation. Safe to re-run.

Covers: system identity and time, DHCP pools and static leases, DNS upstreams, service hardening (disabling insecure protocols, restricting SSH/web UI to LAN), auto-update scheduling.

**Running:**
```bash
cd ansible
ansible-playbook mikrotik-configure.yml
```

For detailed configuration specifics, see the playbook itself in `ansible/mikrotik-configure.yml` — it's the source of truth.

## Raspberry Pi Provisioning

Two playbooks provision Rocky Linux 9 ARM on the Pis: bootstrap for one-time user setup, then the main OS/k3s installation.

### Prerequisites: Manual Image Flashing

Before Ansible provisioning can begin, Rocky Linux 9 ARM must be flashed onto each Raspberry Pi's SD card manually:

1. Download the Rocky Linux 9 ARM image for Raspberry Pi from the [SIGAltArch Pi Images wiki](https://wiki.rockylinux.org/rocky/image/#about-pi-images-maintained-by-sigaltarch)
2. Flash the image to the SD card using [balena Etcher](https://www.balena.io/etcher/) or `dd`
3. Insert the SD card into the Pi and power on
4. Connect the Pi to the network via Ethernet
5. The router assigns it a DHCP IP address (configured in the MikroTik configure step)
6. Verify network connectivity before proceeding to bootstrap playbook

### Phase 1: Bootstrap (`rpi-bootstrap.yml`)

**One-time setup.** Creates a secure SSH user with key auth and passwordless sudo, removes default `rocky` user.

**Running:**
```bash
cd ansible
ssh-add ~/.ssh/id_rsa
ansible-playbook rpi-bootstrap.yml
```

Uses distro default credentials (`rocky`/`rockylinux`), so it only needs to run once per fresh install.

**Verify:**
```bash
ssh k3-m1
ssh k3-n1
```

### Phase 2: Install (`k3-install.yml`)

**Idempotent.** Configures OS, installs k3s, and deploys the cluster. Safe to re-run for updates or configuration changes.

**What it does:**
- **sys role** (all nodes): Locale/timezone, system packages (nfs-utils, iscsi-initiator-utils, dnf-automatic), Raspberry Pi tuning (CPU/GPU overclock, PoE HAT fan curves), firewall disabled
- **k3s/common role** (all nodes): Kernel tuning, cgroup setup, k3s binary, kubelet garbage collection and logging
- **k3s/master role** (control-plane): Starts k3s server, generates agent token, copies kubeconfig
- **k3s/node role** (workers): Joins agents to the cluster using the token from master

**Running:**
```bash
cd ansible
ssh-add ~/.ssh/id_rsa
ansible-playbook k3-install.yml

# Skip slow tasks for faster iteration during development
ansible-playbook k3-install.yml --skip-tags=slow
```

**Retrieve kubeconfig:**
After installation completes, copy the kubeconfig from the master:

```bash
scp k3-m1:~/.kube/config ~/.kube/homelab_config
```

Configure `~/.envrc` or your shell to load it via `export KUBECONFIG=~/.kube/homelab_config` (or direnv if configured).

**Key configuration:**
- k3s version pinned in `ansible/inventory/group_vars/all.yaml`
- Control-plane stores state in MySQL on Synology NAS (not embedded etcd, to reduce SD card wear)
- Control-plane is tainted to run only critical system components; workers run application workloads

## Secrets and Configuration

Ansible reads sensitive values from environment variables via `lookup('env', ...)`, sourced from `.envrc` (gitignored):

- SSH user and key path
- MikroTik factory credentials
- k3s server token (for reinstalls against existing state)
- Database credentials (MySQL)
- Container registry credentials
- MAC addresses for network devices
- Cloudflare API credentials (zone ID, DNS record ID, domain name, DDNS token)

Example `.envrc` structure (not checked in):
```bash
export SSH_USER="username"
export SSH_KEY_PATH="~/.ssh/id_rsa"
export MIKROTIK_DEFAULT_USER="admin"
export MIKROTIK_DEFAULT_PASSWORD=""
export SYNOLOGY_ETH1_MAC="90:09:d0:10:17:53"
export CF_ZONE_ID="<cloudflare-zone-id>"
export CF_DNS_RECORD_ID="<cloudflare-dns-record-id>"
export CF_DNS_RECORD_NAME="example.com"
export CF_MIKROTIK_DDNS_TOKEN="<cloudflare-api-token>"
# ... more variables
```

Ansible configuration lives in:
- **`ansible/inventory/hosts.ini`** -- Device hostnames and group membership (`[router]`, `[master]`, `[node]`)
- **`ansible/inventory/group_vars/all.yaml`** -- Global variables and environment variable lookups
- **`ansible/inventory/group_vars/router.yaml`** -- RouterOS-specific connection settings

## Recovery Scenarios

### MikroTik Factory Reset

If the router becomes misconfigured or unreachable, reset to factory defaults by holding the reset button during power-on (hold until LEDs indicate reset). Then re-run bootstrap and configure playbooks.

### Raspberry Pi Fresh Install

For a fresh Raspberry Pi (corrupt SD card, hardware replacement, etc.):
1. Flash Rocky Linux 9 ARM ISO onto SD card
2. Boot and ensure network/DHCP connectivity
3. Run `rpi-bootstrap.yml`
4. Run `k3-install.yml`

### Lost Master Node

If the k3s master node becomes unavailable:
1. Prepare a fresh Raspberry Pi with Rocky Linux 9 ARM
2. Run `rpi-bootstrap.yml`
3. Run `k3-install.yml` pointing to the new Pi as the master
4. Delete old node secrets if rejoin is needed: `kubectl -n kube-system delete secrets k3-n1.node-password.k3s`

## References

- [MikroTik RouterOS Documentation](https://help.mikrotik.com/)
- [k3s-ansible](https://github.com/k3s-io/k3s-ansible) -- Upstream Ansible k3s project
- [Ansible Community RouterOS Collection](https://github.com/ansible-collections/community.routeros)

## Related Documentation

- [Getting Started](00-getting-started.md) -- Hardware details, software stack overview
- [RPis and k3s](02-rpis-and-k3s.md) -- Kubernetes cluster topology and configuration
- [Persistence](03-persistence.md) -- Storage and persistent volumes
- [Networking](04-networking.md) -- DNS, load balancing, ingress, TLS
- [Security](05-security.md) -- Authentication, network policies
- [Observability](06-observability.md) -- Logging and monitoring
- [Maintenance](07-maintenance.md) -- Cluster operations and upgrades
