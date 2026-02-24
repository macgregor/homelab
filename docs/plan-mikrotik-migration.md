# MikroTik RB5009UPr+S+IN Network Migration Plan

## Context

The homelab network hardware has been replaced: NETGEAR Nighthawk R7000 router + GS305EP PoE switch replaced by a single MikroTik RB5009UPr+S+IN (router/switch) plus a TP-Link EAP723 wireless AP. The MikroTik is at factory defaults (192.168.88.1/24). All existing k8s manifests, Ansible inventory, and static IPs expect 192.168.1.0/24. The goal is to configure the MikroTik to restore LAN functionality with the configuration managed by Ansible. External access (Cloudflare, port forwarding) is covered separately in `docs/plan-external-access.md`.

**Physical layout:**
- ether1: WAN (Google Fiber modem, bridge mode)
- ether2: TP-Link EAP723 (PoE from MikroTik, currently 192.168.88.251)
- ether3: Desktop (D8:BB:C1:8E:DF:AA)
- ether4: Synology DS720+ NAS (90:09:D0:10:17:53)
- ether5: Raspberry Pi k3-m1 (E4:5F:01:2C:0C:DE)
- ether6: Raspberry Pi k3-n1 (DC:A6:32:CC:7E:08)

**Synology NIC naming:** The physical box labels the ports "LAN 1" and "LAN 2", but the Synology OS (DSM/Linux) uses 0-indexed names: LAN 1 = `eth0` (90:09:D0:10:17:53), LAN 2 = `eth1` (90:09:D0:10:17:54). This plan and all env vars/CoreDNS entries use the physical 1-indexed convention (ETH1/ETH2, synology-eth1/synology-eth2).

**TP-Link AP management:** Standalone web UI only. CAPsMAN is MikroTik-only.

**Bootstrap status:** Factory default `admin` user (no password). The bootstrap playbook creates the `macgregor` user with SSH key (similar to `rpi-bootstrap.yml`).

**Current MikroTik state (verified via SSH):**
- RouterOS 7.21.3 (stable), firmware upgrade available from 7.19.6 to 7.21.3
- Factory default firewall intact (NAT masquerade, input/forward filter chains - details in `docs/plan-external-access.md`)
- Interface lists already defined: WAN=ether1, LAN=bridge
- DHCP pool `default-dhcp` range 192.168.88.10-254, 11 leases active
- DNS forwarding to Google 8.8.8.8/8.8.4.4 (from ISP DHCP)
- PoE auto-on all ports, NTP disabled, strong-crypto off
- MAC-server already restricted to LAN list (factory default)

**Devices visible on current 192.168.88.x network (verified via SSH and bridge forwarding table):**
- .246 = Synology NAS LAN 1 (90:09:D0:10:17:53, ether4) - got DHCP lease despite static config
- .251 = TP-Link EAP723 (8C:86:DD:1A:3F:3E, ether2)
- .252 = k3-m1 (E4:5F:01:2C:0C:DE, ether5)
- .253 = k3-n1 (DC:A6:32:CC:7E:08, ether6)
- .254 = Desktop (D8:BB:C1:8E:DF:AA, ether3)
- .247 = workstation (92:E6:6C:D6:7E:55)
- Synology NAS LAN 2 (90:09:D0:10:17:54) - currently unplugged, DHCP reservation included so it works when connected

---

## Phase 1: Pre-bootstrap setup

Add to `.envrc`:

```bash
# MikroTik factory defaults (for bootstrap playbook)
export MIKROTIK_DEFAULT_USER="admin"
export MIKROTIK_DEFAULT_PASSWORD=""

# MAC addresses (verified via SSH and bridge forwarding table)
export SYNOLOGY_ETH1_MAC="90:09:D0:10:17:53"
export SYNOLOGY_ETH2_MAC="90:09:D0:10:17:54"
export K3_M1_MAC="E4:5F:01:2C:0C:DE"
export K3_N1_MAC="DC:A6:32:CC:7E:08"
export AP_MAC="8C:86:DD:1A:3F:3E"
export DESKTOP_MAC="D8:BB:C1:8E:DF:AA"
```

The TP-Link AP is already in DHCP mode (Management -> Network -> IP Settings -> Dynamic). No manual AP configuration needed - it will pick up a DHCP lease on the new subnet automatically. A DHCP reservation for .2 is added by `mikrotik-configure.yml`.

---

## Phase 2: Ansible setup

Install the `community.routeros` collection and create the inventory/group_vars for the MikroTik.

### Files to create/modify

1. **`ansible/collections/requirements.yml`** - Add `community.routeros` collection
2. **`ansible/inventory/hosts.ini`** - Add `[router]` group with `edge`
3. **`ansible/inventory/group_vars/router.yaml`** - New file, RouterOS connection settings
4. **`ansible/mikrotik-bootstrap.yml`** - Subnet migration playbook (run once)
5. **`ansible/mikrotik-configure.yml`** - Main configuration playbook (idempotent)

### `ansible/collections/requirements.yml`

Append to the existing file (which currently has only commented-out role entries):

```yaml
collections:
  - name: ansible.netcommon
  - name: community.routeros
```

### `ansible/inventory/hosts.ini`

Note: the existing `hosts.ini` relies on name resolution for k3-m1/k3-n1 (no `ansible_host` set). Adding explicit `ansible_host` values here for all hosts so the inventory is self-contained.

```ini
[router]
edge ansible_host=192.168.1.1

[master]
k3-m1 ansible_host=192.168.1.210

[node]
k3-n1 ansible_host=192.168.1.211

[cluster:children]
master
node
```

### `ansible/inventory/group_vars/router.yaml`

Only settings that differ from global defaults (`ansible_user` and `private_key_file` are already set in `all.yaml` and `ansible.cfg`):

```yaml
ansible_connection: ansible.netcommon.network_cli
ansible_network_os: community.routeros.routeros
ansible_become: no
```

### Install dependencies

The `community.routeros` collection requires `ansible-pylibssh` for SSH transport via `network_cli`. On Fedora/RHEL, `libssh-devel` is needed to build the Python binding. The bootstrap playbook also requires `sshpass` for SCP file upload to the factory-default router:

```bash
sudo dnf install libssh-devel sshpass
pip install ansible-pylibssh
cd ansible && ansible-galaxy collection install -r collections/requirements.yml
```

---

## Phase 3: Ansible bootstrap playbook (`ansible/mikrotik-bootstrap.yml`)

Run once from a factory-default router. Creates the `macgregor` user and sets up 192.168.1.0/24 alongside the factory default 192.168.88.0/24 (which is left intact). Does the absolute minimum to get the router reachable at 192.168.1.1 with working DHCP. All other configuration (pool tuning, static leases, DNS, etc.) is handled by `mikrotik-configure.yml`.

Connects using factory credentials (`MIKROTIK_DEFAULT_USER`/`MIKROTIK_DEFAULT_PASSWORD` from `.envrc`). Files are uploaded via `sshpass scp` (delegated to localhost) and executed via `/import`.

### What the bootstrap playbook does

1. **Create `macgregor` user** - `full` group, SSH public key (from `ssh_pub_key` in `all.yaml`), same pattern as `rpi-bootstrap.yml`
2. **Set up 192.168.1.0/24** via `bootstrap-migrate-subnet.rsc`:
   - Add 192.168.1.1/24 to bridge
   - Create `dhcp-pool` (192.168.1.10-254) and `192.168.1.0/24` DHCP network entry
   - Disable `defconf` DHCP server (factory default, left intact but inactive)
   - Create `dhcp-lan` DHCP server on bridge pointing at `dhcp-pool`

Factory 192.168.88.0/24 config is not removed — `defconf` is only disabled. Both addresses exist on bridge during and after bootstrap; only `dhcp-lan` issues leases. The wide DHCP pool is intentionally simple — `mikrotik-configure.yml` narrows it to .50-.199 and adds static leases. No reboot required.

### How it works

The playbook overrides connection settings for the factory-default router:

```yaml
vars:
  ansible_host: 192.168.88.1
  ansible_user: "{{ lookup('env', 'MIKROTIK_DEFAULT_USER') }}"
  ansible_password: "{{ lookup('env', 'MIKROTIK_DEFAULT_PASSWORD') }}"
```

Note: `network_cli` uses `ansible_password`, not `ansible_ssh_pass` (which is what `rpi-bootstrap.yml` uses for standard SSH connections).

1. Ansible connects to `192.168.88.1` as factory user
2. Creates `macgregor` user with SSH key (uploaded via `scp` from localhost, then imported)
3. Uploads and runs `bootstrap-migrate-subnet.rsc` via `/import` — connection stays up throughout
4. Workstation reconnects to get a 192.168.1.x DHCP lease
5. `mikrotik-configure.yml` connects as `macgregor` on 192.168.1.1

**Recovery after factory reset:** No manual steps needed. Just run the bootstrap playbook again.

### Running

```bash
cd ansible
ansible-playbook mikrotik-bootstrap.yml
nmcli device disconnect wlp0s20f3 && nmcli device connect wlp0s20f3
```

**Verify:**
```bash
ping 192.168.1.1                           # MikroTik reachable
ssh macgregor@192.168.1.1                  # SSH works on new subnet
```

---

## Phase 4: Ansible configuration playbook (`ansible/mikrotik-configure.yml`)

The main deliverable. Idempotent - safe to re-run. Following the same pattern as the RPi provisioning: the bootstrap (Phase 3) gets the subnet right, then this playbook configures everything else.

Uses `community.routeros.command` (SSH-based) since we're disabling the API service for security.

### What the playbook configures

1. **System** - identity (`edge`), timezone, NTP, strong SSH crypto
2. **User cleanup** - remove the factory `admin` user (bootstrap already created `macgregor` with `full` group)
3. **DHCP tuning** - narrow pool to 192.168.1.50-199 (avoids static IPs 200-211 and MetalLB 220-239), set lease time
4. **DNS** - set upstream to `1.1.1.1` (`/ip dns set servers=1.1.1.1`)
5. **Static DHCP leases** - AP (.2), Desktop (.3), NAS LAN 1/LAN 2 (.200/.201), RPi k3-m1/k3-n1 (.210/.211) from `.envrc` env vars
6. **Service hardening** - disable telnet/ftp/api (loop), restrict ssh/www/winbox to LAN (loop)
7. **Discovery hardening** - MAC-server already restricted to LAN (factory default, verified). Disable mac-server ping, neighbor discovery on WAN, bandwidth server
8. **Auto-update scheduler** - upload `auto-update.rsc` (stays on router, called by scheduler daily) and `configure-auto-update.rsc` (setup script: idempotently recreates the scheduler entry, sets `auto-upgrade=yes` for firmware). Uploaded via `scp` with key auth (no sshpass needed post-bootstrap). `configure-auto-update.rsc` is cleaned up after import; `auto-update.rsc` persists.
9. **Cleanup** - remove `bootstrap-migrate-subnet.rsc` and `configure-auto-update.rsc` if present

### Idempotency approach

Remove-then-add for DHCP leases and pool config (with `ignore_errors` on removes for first-run).

### MAC addresses for static leases

Following the existing secrets pattern, MAC addresses are stored in `.envrc` (see Phase 1). The playbook reads these via `lookup('env', ...)` like existing vars in `all.yaml`. Six static leases are configured: AP (.2), Desktop (.3), Synology LAN 1 (.200), Synology LAN 2 (.201), k3-m1 (.210), k3-n1 (.211).

### Running

```bash
cd ansible
ansible-playbook mikrotik-configure.yml
```

---

## Phase 5: Verify k8s cluster

```bash
kubectl get nodes                          # Both nodes Ready
kubectl get pods -A                        # All pods running
make metallb-status                        # MetalLB healthy
make ingress-nginx-internal-status         # Internal ingress up at .221
```

DNS is set to `1.1.1.1` by Phase 4. To chain through the cluster's CoreDNS instead, update the Ansible playbook's DNS servers to `192.168.1.223,1.1.1.1` and re-run.

---

## Phase 5.5: Enable Scheduler in Device-Mode (Manual Step)

The RB5009UPr+S+ ships in "home" device-mode, which disables `/system scheduler`. Before running `mikrotik-configure.yml`, enable scheduler by switching to "advanced" mode:

```bash
ssh -o StrictHostKeyChecking=no -i ~/.ssh/macgregor.id_rsa macgregor@192.168.1.1 \
  '/system device-mode update mode=advanced'
```

RouterOS will respond:
```
update: please activate by turning power off or pressing reset or mode button in 5m00s
```

**Within 5 minutes, do ONE of these:**
- **Press the reset/mode button** on the RB5009 front panel (hold 3-5 seconds until LED response), OR
- **Power-cycle the device** (unplug power for 10 seconds, plug back in)

The router will reboot and apply advanced mode. Wait ~2 minutes for the router to come back online.

**Verify scheduler is enabled:**
```bash
ssh -o StrictHostKeyChecking=no -i ~/.ssh/macgregor.id_rsa macgregor@192.168.1.1 \
  '/system device-mode print | grep scheduler'
```

Should return: `scheduler: yes`

Now proceed to Phase 5 verification, then Phase 6 documentation updates.

**Reference:** [RouterOS Device-mode Documentation](https://help.mikrotik.com/docs/spaces/ROS/pages/93749258/Device-mode)

---

## Phase 6: Documentation and manifest updates

Remove all references to old hardware (Nighthawk R7000, GS305EP, FreshTomato). Docs should describe the current architecture only -- git history preserves the old state.

### `kube/sys/coredns/coredns.yml`

Line 49: rename hostname `switch` to `wifi-ap` (`192.168.1.2` is now the TP-Link AP, not a switch).

### `docs/00-getting-started.md`

- **Hardware table**: Remove NETGEAR Nighthawk R7000 and GS305EP rows. Add MikroTik RB5009UPr+S+IN (router/switch/PoE, replaces both). Add TP-Link EAP723 (wireless AP). PoE HAT rows stay (MikroTik supplies PoE now but the HATs are still needed on the Pis).
- **"Network -- PoE Switch and Router" section**: Rewrite for MikroTik + TP-Link AP. MikroTik is a combined router/managed switch with PoE on all ports. TP-Link EAP723 provides WiFi (standalone management, not CAPsMAN). MikroTik is provisioned by Ansible (`mikrotik-bootstrap.yml` and `mikrotik-configure.yml`). Remove all FreshTomato/VLAN references.
- **"Compute" section** (line 30): Fix pre-existing typo -- says "1GB model" but the hardware table says 4GB.
- **Software Stack table**: Update "Provisioning" row to mention MikroTik alongside Pis.
- **Repository Layout**: Update `ansible/` description to mention router provisioning.

### `docs/01-rpis-and-k3s.md`

- **Ansible inventory** (line 14): Mention the `[router]` group with `edge` now exists alongside `master`, `node`, and `cluster`.
- **Prerequisites** (line 42): "Static IPs and hostnames assigned on the router" -- note this is now managed by `mikrotik-configure.yml` (DHCP reservations), not manual router config.
- **Galaxy dependencies** (line 45): Update install command to `ansible-galaxy collection install -r collections/requirements.yml` (was `ansible-galaxy install -r requirements.yml`). Mention the `community.routeros` collection.
- **Add brief mention** of `mikrotik-bootstrap.yml` and `mikrotik-configure.yml` in the provisioning section, since this doc covers all Ansible provisioning.

### `docs/02-persistence.md`

No changes needed -- no references to old network hardware.

### `docs/03-networking.md`

- **Mermaid diagram**: Remove separate "PoE Switch - GS305EP" node. Replace "Router - FreshTomato" with "MikroTik RB5009UPr+S+IN" (combined router/switch). Add "TP-Link EAP723 (WiFi AP)" node connected to MikroTik ether2. Pis and Synology connect directly to MikroTik ports (ether3-6). PoE comes from MikroTik, not a separate switch.
- **Static IP paragraph** (line 34): Note that static IPs are managed as DHCP reservations by `mikrotik-configure.yml`.
- **"Router Configuration (FreshTomato)" section**: Complete rewrite as "Router Configuration (MikroTik)". Describe Ansible-managed configuration (`mikrotik-bootstrap.yml` for initial setup, `mikrotik-configure.yml` for ongoing config). List what the playbooks configure (system identity, DHCP, DNS, static leases, service hardening, auto-updates). Remove FreshTomato setup checklist.
- **"Router Firewall" section**: Remove `scripts/router-firewall.sh` references. Note that MikroTik ships with a factory default firewall (NAT masquerade, input/forward chains). Port forwarding and Cloudflare-only firewall rules are covered separately in `docs/plan-external-access.md`.
- **Cloudflare section** (line 64): Remove mention of "the router runs a dynamic DNS client" -- DDNS on MikroTik is covered in `plan-external-access.md`, not this migration. Note that DDNS configuration is pending.
- **Remove** all references to FreshTomato, `scripts/router-firewall.sh`, VLAN tagging, and the GS305EP.

---

## IP Allocation Summary

| IP | Device | Notes |
|---|---|---|
| 192.168.1.1 | MikroTik (edge) | Gateway, static on bridge |
| 192.168.1.2 | TP-Link EAP723 | DHCP reservation |
| 192.168.1.3 | Desktop | DHCP reservation |
| 192.168.1.50-199 | DHCP pool | Dynamic clients |
| 192.168.1.200 | Synology NAS LAN 1 | OS-level static + DHCP reservation |
| 192.168.1.201 | Synology NAS LAN 2 | OS-level static + DHCP reservation (currently unplugged) |
| 192.168.1.210 | k3-m1 | OS-level static + DHCP reservation |
| 192.168.1.211 | k3-n1 | OS-level static + DHCP reservation |
| 192.168.1.220-239 | MetalLB pool | L2 mode, managed by k8s |

Only k8s manifest change: `kube/sys/coredns/coredns.yml:49` hostname `switch` → `wifi-ap` (Phase 6). IP allocations match the existing CoreDNS hosts file and MetalLB pool configuration.

---

## Risk Mitigations

| Risk | Mitigation |
|---|---|
| Locked out during subnet change | Bootstrap adds 192.168.1.0/24 alongside factory 192.168.88.0/24 without removing the old subnet. SSH connection stays up throughout. Factory reset restores defaults as last resort (hold reset button during power-on, may require extended hold) |
| TP-Link AP unreachable after subnet | AP is in DHCP mode; gets .2 via reservation after configure playbook runs. Still bridges L2 regardless of management IP |
| Ansible playbook breaks something | RouterOS safe mode or factory reset as fallback |
| Auto-update installs breaking RouterOS release | Update channel set to `stable` (not `testing` or `development`). Factory reset recoverable |
| Scheduler not available for auto-updates | Device-mode in home mode disables scheduler. Phase 5.5 switches to advanced mode (requires button press). After that, configure playbook successfully creates schedulers |

---

## Notes

- **192.168.10.0/24 rule dropped**: The old `scripts/router-firewall.sh` had `iptables -I INPUT -s 192.168.10.0/24 -j ACCEPT`. This subnet isn't referenced anywhere else in the homelab config and is not carried forward to the MikroTik configuration.

---

## Critical files

- `kube/sys/coredns/coredns.yml:48-57` - Authoritative IP-to-hostname mapping (must match)
- `kube/sys/metallb/helm-values.yml` - MetalLB pool definition (DHCP range must not overlap)
- `ansible/inventory/hosts.ini` - Inventory to extend with `[router]` group
- `ansible/inventory/group_vars/all.yaml` - Existing group vars pattern to follow
- `ansible/ansible.cfg` - Connection settings reference
- `ansible/rpi-bootstrap.yml` - Pattern reference for bootstrap-then-ansible approach

---

## Review Findings

Issues identified during plan review, with resolutions.

### Resolved

1. **SSH key import is two-step on RouterOS**: RouterOS is not Linux -- `ansible.builtin.user` and `authorized_keys` don't exist. The public key file must be uploaded to the router's filesystem via `scp` (delegated to localhost), then imported with `/user ssh-keys import public-key-file=<filename> user=macgregor`. The bootstrap playbook must handle both steps. Note: `ansible.netcommon.net_put` was rejected because it sends shell verification commands (`echo`, `ls`) over SSH that RouterOS doesn't understand, producing error logs. Confirmed the existing key (`~/.ssh/macgregor.id_rsa.pub`) is RSA, which RouterOS requires.

2. **`/system routerboard upgrade` prompts for confirmation**: Interactive prompt hangs automation. Resolution: use `/system routerboard settings set auto-upgrade=yes` so firmware upgrades apply automatically on next reboot. Check current vs upgrade firmware versions with `/system routerboard print` for idempotency.

3. **Subnet migration approach**: RouterOS scheduler fires only on reboot; `:execute` is async with no reliable output capture. Resolution: write the migration as a proper `.rsc` file, upload via `sshpass scp`, and run synchronously via `/import`. The script adds 192.168.1.0/24 alongside the factory 192.168.88.0/24 rather than replacing it — this avoids the SSH session being dropped mid-execution. `defconf` DHCP server is disabled (not deleted) and a new `dhcp-lan` server created, ensuring only one DHCP server is ever active on the bridge at a time.

4. **`ansible_password` vs `ansible_ssh_pass`**: Plan note on line 151 is incorrect -- they are aliases. Both work with both connection types. Use `ansible_password` consistently in new code (current recommended name).

5. **Auto-update causes unattended reboots**: Package updates require a router reboot. Resolution: schedule the auto-update check+install to run at a low-traffic time (e.g., 4 AM) so reboots happen predictably. Update channel remains `stable`.

6. **`+cet512w` username suffix**: The `community.routeros` docs warn that long RouterOS commands can break if output wraps at 80 characters. Resolution: add `+cet512w` suffix to the SSH username in `router.yaml` group_vars (e.g., `ansible_user: macgregor+cet512w`). This disables terminal width restrictions.

### Verified Correct

- IP allocations match CoreDNS hosts file (`coredns.yml:47-57`) exactly
- MetalLB pool `.220-.239` does not overlap DHCP pool `.50-.199` (`metallb/addresspool.yml`)
- CoreDNS line 49 has `switch` hostname (confirmed needs rename to `wifi-ap`)
- `ansible_become: no` in group_vars overrides global `become = True` in `ansible.cfg`
- `pipelining` and `ControlMaster` in `ansible.cfg` are ignored by `network_cli` (no conflict)
- `community.routeros.command` works over SSH with `network_cli` (not API-only)
- `collections/requirements.yml` currently only has commented-out roles; adding `collections:` block is valid YAML
- Admin removal is self-verifying: the configure playbook connects as `macgregor` via SSH key, so if it runs at all, `macgregor` works

---

## Implementation TODO

Ansible playbooks first. Do not run against the switch until all playbooks are written and syntax-checked. Use `--syntax-check` and `--check` (dry run) modes only.

### Phase 2: Ansible setup

- [x] 1. Update `ansible/collections/requirements.yml` -- add `collections:` block with `ansible.netcommon` and `community.routeros`
- [x] 2. Run `ansible-galaxy collection install -r collections/requirements.yml` to install the collections
- [x] 3. Update `ansible/inventory/hosts.ini` -- add `[router]` group with `edge ansible_host=192.168.1.1`, add `ansible_host` values to existing entries
- [x] 4. Create `ansible/inventory/group_vars/router.yaml` -- `network_cli` connection, `routeros` network_os, `ansible_become: no`, username with `+cet512w` suffix
- [x] 5. Syntax-check: `ansible-inventory --list` to verify inventory parses correctly

### Phase 3: Bootstrap playbook

- [x] 6. Create `ansible/mikrotik-bootstrap.yml` with:
  - Connection overrides: `ansible_host: 192.168.88.1`, factory credentials from `.envrc`
  - Task: render `bootstrap-create-user.rsc.j2` template locally, upload via `sshpass scp`
  - Task: upload SSH public key and `bootstrap-migrate-subnet.rsc` via `sshpass scp`
  - Task: run user creation script via `/import` (creates `macgregor` user, imports SSH key)
  - Task: run subnet setup script via `/import` (adds 192.168.1.0/24, disables defconf, creates dhcp-lan)
  - `dry_run=true` flag passes `verbose=yes dry-run` to `/import` for validation without changes
- [x] 7. Syntax-check: `ansible-playbook mikrotik-bootstrap.yml --syntax-check`

### Phase 4: Configure playbook

- [x] 8. Create `ansible/mikrotik-configure.yml` with the following task groups:
  - System: identity (`edge`), timezone, NTP client, strong SSH crypto
  - User cleanup: remove factory `admin` user
  - DHCP tuning: narrow pool to `.50-.199`, set lease time
  - DNS: set upstream to `1.1.1.1`
  - Static DHCP leases: AP (.2), Desktop (.3), NAS LAN 1/2 (.200/.201), k3-m1/k3-n1 (.210/.211) using MAC addresses from `.envrc`
  - Service hardening: loop to disable [telnet, ftp, api, api-ssl]; loop to restrict [ssh, winbox, www] to LAN
  - Discovery hardening: disable mac-server ping, neighbor discovery on WAN, bandwidth server
  - Auto-update: upload `auto-update.rsc` + `configure-auto-update.rsc` via `scp` (key auth), import setup script (sets scheduler + auto-upgrade flag)
  - Cleanup: remove `bootstrap-migrate-subnet.rsc` and `configure-auto-update.rsc` if present
- [x] 9. Syntax-check: `ansible-playbook mikrotik-configure.yml --syntax-check`
- [ ] 10. Dry-run review: `ansible-playbook mikrotik-configure.yml --check` (will fail against live router but validates task structure)

### Pre-execution verification

- [x] 11. Review both playbooks end-to-end: verify all RouterOS commands are valid syntax, MAC addresses reference correct env vars, IP addresses match the allocation table
- [x] 12. Verify `.envrc` has all required env vars: `MIKROTIK_DEFAULT_USER`, `MIKROTIK_DEFAULT_PASSWORD`, all MAC address vars

### Phase 6: Documentation and manifest updates

- [ ] 13. Update `kube/sys/coredns/coredns.yml:49` -- rename hostname `switch` to `wifi-ap`
- [ ] 14. Update `docs/00-getting-started.md` -- replace old hardware (Nighthawk, GS305EP) with MikroTik + TP-Link AP in table and narrative sections, fix 1GB/4GB typo, update software stack and repo layout to mention router provisioning
- [ ] 15. Update `docs/01-rpis-and-k3s.md` -- mention `[router]` group in inventory section, update prerequisites to reference Ansible-managed DHCP reservations, update galaxy install command, add `ansible-pylibssh` and `libssh-devel` as prerequisites for RouterOS SSH transport, add `mikrotik-bootstrap.yml`/`mikrotik-configure.yml` to provisioning section
- [ ] 16. Update `docs/03-networking.md` -- rewrite mermaid diagram (MikroTik replaces router+switch), rewrite "Router Configuration" section for MikroTik/Ansible, rewrite firewall section (factory default + pending external access plan), remove all FreshTomato/GS305EP/VLAN references, note DDNS as pending
