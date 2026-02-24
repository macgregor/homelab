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

### Phase 1: Bootstrap (`mikrotik-bootstrap.yml`)

**One-time setup.** Migrates from factory defaults to 192.168.1.0/24 and creates a secure SSH user. After this, the router is reachable at 192.168.1.1.

**What it does:**
1. Connects to 192.168.88.1 using factory credentials (stored in `.envrc`)
2. Creates SSH user with public key auth (from `ssh_pub_key` in `all.yaml`)
3. Adds 192.168.1.0/24 subnet alongside factory 192.168.88.0/24 (connection stays up during migration)
4. Creates new DHCP server on the 192.168.1.0/24 subnet

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

**Idempotent.** Applies system configuration, security hardening, and auto-update scheduling. Safe to re-run.

**What it does:**
1. System identity, timezone, NTP
2. DHCP tuning: narrow pool to 192.168.1.50-199 (avoids static IP ranges and MetalLB pool)
3. DNS: set upstream to Cloudflare (1.1.1.1)
4. Static DHCP leases: AP (.2), Desktop (.3), Synology LAN 1/2 (.200/.201), k3-m1/k3-n1 (.210/.211)
5. Service hardening: disable insecure services (telnet, ftp, api), restrict SSH/web UI to LAN only
6. Discovery hardening: disable MAC-server ping, neighbor discovery on WAN
7. Auto-update scheduling: daily firmware/package checks with automatic installation on stable channel

MAC addresses for static leases are sourced from `.envrc` environment variables (e.g., `SYNOLOGY_ETH1_MAC`).

**Running:**
```bash
cd ansible
ansible-playbook mikrotik-configure.yml
```

**Manual prerequisite:** The RB5009 ships in "home" device-mode, which disables the scheduler needed for auto-updates. Before running the configure playbook, switch to "advanced" mode:

```bash
ssh 192.168.1.1 '/system device-mode update mode=advanced'
```

The router will request activation via button press or power cycle (within 5 minutes). After activation and reboot, proceed with the configure playbook.

### Troubleshooting

- **Locked out after bootstrap:** Factory 192.168.88.0/24 is left intact. Reconnect to 192.168.88.1 and retry.
- **SSH key auth fails:** Verify the public key in `ansible/inventory/group_vars/all.yaml` matches your private key. RouterOS requires RSA keys.
- **DHCP leases not assigning:** Check that MAC addresses in `.envrc` match actual device MACs. Verify with `ip mac-address print` on the router.
- **Scheduler not available:** Confirm device-mode switch to "advanced" completed successfully (`/system device-mode print`).

## Raspberry Pi Provisioning

Two playbooks provision Rocky Linux 9 ARM on the Pis: bootstrap for one-time user setup, then the main OS/k3s installation.

### Phase 1: Bootstrap (`rpi-bootstrap.yml`)

**One-time setup.** Creates a secure SSH user with key auth and passwordless sudo, removes default `rocky` user.

**Prerequisites:**
- Rocky Linux 9 ARM booted on SD card
- Network connected and DHCP working (or manual IP assigned)

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

Example `.envrc` structure (not checked in):
```bash
export SSH_USER="username"
export SSH_KEY_PATH="~/.ssh/id_rsa"
export MIKROTIK_DEFAULT_USER="admin"
export MIKROTIK_DEFAULT_PASSWORD=""
export SYNOLOGY_ETH1_MAC="90:09:d0:10:17:53"
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
- [Saving Your SD Cards](08-saving-your-sdcards.md) -- Reducing SD card wear
