# External Access Plan (Cloudflare + Port Forwarding)

## Prerequisites

Complete `docs/plan-mikrotik-migration.md` first. LAN must be stable on 192.168.1.0/24 with `mikrotik-configure.yml` applied.

## Context

The old Nighthawk router had iptables rules (`scripts/router-firewall.sh`) that:
- Maintained a Cloudflare IP address list
- DNAT'd TCP 443 from Cloudflare sources to 192.168.1.220 (nginx-external MetalLB VIP)
- Allowed forwarding of that DNAT'd traffic

This needs to be replicated on the MikroTik. The factory default firewall is already in place:
- NAT: masquerade on WAN out-interface-list
- Filter input: accept established/related/untracked, drop invalid, accept ICMP, accept loopback, drop all not from LAN
- Filter forward: accept ipsec in/out, fasttrack established/related, accept established/related/untracked, drop invalid, drop all from WAN not DSTNATed
- Interface lists: WAN=ether1, LAN=bridge

The last forward rule (`drop all from WAN not DSTNATed`) is the insertion point - new forward-accept rules must be placed before it using `place-before`.

---

## Approach

A single RouterOS script handles all Cloudflare firewall configuration. The script is deployed by Ansible and scheduled to run every 15 minutes on the router. This keeps the address list current and rebuilds the firewall rules atomically each run.

### What the script does

1. Fetches `https://www.cloudflare.com/ips-v4` to a temp file
2. Removes all entries from the `cloudflare` address list
3. Parses the file and adds each CIDR as a new entry
4. Removes and re-creates the DNAT rule (TCP 443 from `cloudflare` src → 192.168.1.220:443, `in-interface-list=WAN`)
5. Removes and re-creates the forward rule (accept DNAT'd Cloudflare traffic, placed before the factory default `drop all from WAN not DSTNATed` using `place-before`)
6. Cleans up the temp file and logs success

### Ansible deliverable

A new playbook (or additional tasks in `mikrotik-configure.yml`) that:
1. Deploys the RouterOS script to the router
2. Creates a scheduler that runs the script every 15 minutes
3. Runs the script once immediately to populate the address list and create the firewall rules

### Idempotency

The script itself is idempotent (remove-then-add). The Ansible tasks that deploy the script and scheduler use the same remove-then-add pattern with `ignore_errors` on removes for first-run.

**Note:** RouterOS scripting has quirks with string/file parsing. The exact syntax will need testing during implementation.

---

## Verification

```bash
# From the LAN - check firewall rules exist
ssh macgregor@192.168.1.1 "/ip firewall nat print" | grep 443
ssh macgregor@192.168.1.1 "/ip firewall filter print" | grep cloudflare
ssh macgregor@192.168.1.1 "/ip firewall address-list print where list=cloudflare"

# External access through Cloudflare
curl -v https://jellyfin.matthew-stratton.me

# Check nginx-external is receiving traffic
make ingress-nginx-external-status
```

---

## Risk Mitigations

| Risk | Mitigation |
|---|---|
| Firewall rule ordering | Use `place-before` to insert accept before default drop |
| Cloudflare IPs change over time | RouterOS scheduled script fetches and rebuilds every 15 minutes |
| Script fails to parse Cloudflare IP list | Existing rules remain until next successful run; 15-minute cycle limits exposure |

---

## Critical files

- `scripts/router-firewall.sh` - Old iptables rules being translated to RouterOS
- `kube/sys/metallb/helm-values.yml` - MetalLB pool definition (nginx-external VIP at .220)
- `kube/sys/ingress-nginx/external/helm-values.yml` - External ingress controller config
