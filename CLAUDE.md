# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@README.md

## Project Documentation

Load these documents based on the task at hand. Do not load speculatively.

| Document | Load when... |
|----------|-------------|
| `docs/00-getting-started.md` | You need hardware specs, IP addresses, or software stack details |
| `docs/01-infrastructure-provisioning.md` | Setting up or troubleshooting MikroTik router or Raspberry Pi provisioning |
| `docs/02-rpis-and-k3s.md` | Working with k3s configuration, cluster topology, or node roles |
| `docs/03-persistence.md` | Adding/modifying PVs, PVCs, NFS mounts, or Synology storage |
| `docs/04-networking.md` | Working with MetalLB, ingress, DNS, TLS, or Cloudflare configuration |
| `docs/05-security.md` | Implementing authentication, access control, or security hardening |
| `docs/06-observability.md` | Working with logging, monitoring, or debugging infrastructure |
| `docs/07-maintenance.md` | Upgrading k3s, rotating certificates, or cluster recovery |
| `docs/appendix/mikrotik-routeros.md` | Working with MikroTik router config, RouterOS scripting, or firewall rules |
| `docs/appendix/media-services.md` | Working with Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Gluetun, Tdarr, Seerr, or Decluttarr |
| `docs/appendix/grafana-dashboards.md` | Creating, editing, or troubleshooting Grafana dashboards, dashboard JSON, PromQL/MetricsQL queries, or panel configuration |
| `docs/appendix/telegraf.md` | Working with Telegraf configuration, plugin tuning, metric filtering, containerized deployment, or debugging collection issues |
| `docs/appendix/victoriametrics-queries.md` | Writing PromQL/MetricsQL or LogsQL queries, investigating metrics or logs |
| `docs/appendix/media-playback-hardware.md` | Troubleshooting audio/video playback, Shield TV or soundbar configuration, HDMI/ARC issues |

**`docs/plans/`** — Files here are speculative or historical planning documents (gitignored, ephemeral). Never load them unless the user explicitly asks. They contain outdated or hypothetical information that will contradict the actual state of the project. Never reference or link to them from long-lived documentation.

## Key Commands

All Kubernetes commands run from `kube/` directory. The `KUBECONFIG` env var is set via `.envrc` (direnv).

### Diagnostics

The diagnostic script (`scripts/homelab-diagnose.py`) gathers system state via SSH and kubectl directly -- it does **not** use the observability stack (VictoriaMetrics/Grafana). This makes it useful when Kubernetes or network infrastructure is unreliable, but for routine investigation prefer the observability tooling (Grafana dashboards, VictoriaMetrics queries) which provides historical data and trends. Use the diagnostic script when you need a quick snapshot of current state or when the observability stack itself is down.

```bash
just diagnose                    # Full system report (router + nodes + k8s)
just diagnose-app jellyfin       # App-specific deep dive (logs, events, resources)
just diagnose-node               # Both nodes only
just diagnose-node k3-m1         # Single node
just diagnose-kube               # Kubernetes state only
just diagnose-router             # Router only
```

The report covers: node health (CPU, memory, disk, temperature, SD card I/O), k3s service status, NFS/iSCSI mounts and I/O stats, network routes, DNS resolution (external + internal split-DNS), router interfaces/DHCP/DNS config, pod health and restart counts, resource usage vs limits, certificate expiry, and warning events. Output is Markdown by default; use `--output json` for programmatic consumption.

The tool is at `scripts/homelab-diagnose.py` (stdlib only, no dependencies). It uses SSH multiplexing for performance and relies on `~/.ssh/config` aliases.

### Debugging

```bash
just pod-debug <pod-name> ns=<namespace>   # Shell into a pod
just cluster-debug node=k3-m1              # Shell into network-multitool on a node
```

## Architecture

### Kubernetes Organization (`kube/`)

Apps are grouped by category: `sys/`, `app/`, `media/`, `observation/`, `demo/`, `graveyard/` (deprecated).

Each application follows a standard structure:
```
app-name/
├── justfile           # Just recipes (deploy, remove, stop, start, etc.)
├── namespace.yml      # Namespace
├── storage.yml        # PV/PVC definitions
├── app-name.yml       # Deployment/StatefulSet
├── network.yml        # Service/Ingress
├── helmfile.yaml      # If Helm-managed (optional)
└── helm-values.yml    # Helm values, may use .gotmpl for env var injection
```

`kube/templates/kube-objects.yml` contains shared YAML anchors (control-plane tolerations, node affinity, common labels).

### Deployment Methods

Three patterns exist depending on the component:

1. **Plain kubectl** - Most apps. `kubectl apply -f` on YAML files directly.
2. **Helmfile** - Complex upstream charts (cert-manager, ingress-nginx, victoriametrics). Uses `helmfile apply` with `helm-values.yml`.
3. **envsubst** - For injecting env vars into plain YAML before `kubectl apply` (used by cert-manager cluster issuers).

`.gotmpl` files use Go template syntax (`{{ requiredEnv "VAR_NAME" | quote }}`) for Helmfile value injection.

### Secrets Management

All secrets live in `.envrc` (gitignored), loaded by direnv. They flow into Kubernetes deployments via:
- `envsubst` for plain YAML
- `.gotmpl` templates for Helmfile values
- `kubectl create secret --dry-run=client -o yaml | kubectl apply -f -` in justfile recipes

For how secrets flow into Ansible provisioning, see `docs/01-infrastructure-provisioning.md`.

## SSH Access to Systems

When connecting to any system (RPis, Synology, router, etc.), check `~/.ssh/config` for pre-configured hosts and authentication methods. Don't guess connection parameters—the config file defines the correct user, identity file, and other settings for each host. Use the configured host alias when possible (e.g., `ssh k3-m1` instead of `ssh macgregor@192.168.1.210`).

## Split-Horizon DNS

When adding, removing, or changing Ingress resources (including `ingressClassName`), run `./scripts/homelab-sync-dns.sh` to regenerate the CoreDNS hosts block and router static DNS entries. Then deploy both: `cd kube && just coredns-deploy` and `cd ansible && ansible-playbook mikrotik-configure.yml`.

## Observability Query Capture

When investigating homelab issues using ad-hoc VictoriaMetrics or VictoriaLogs queries that prove useful, **capture them as obs-query subcommands** rather than leaving them as inline Python or raw curl/HTTP calls:

1. Develop the query during investigation (ad-hoc is fine for exploration)
2. Once useful, add a `cmd_<name>(args)` function to `.claude/skills/homelab-investigator/obs-query`
3. Register it in the `COMMANDS` dict
4. Document it in `.claude/skills/homelab-investigator/query-recipes.md`
5. If it reveals a stable failure pattern, add that to `.claude/skills/homelab-investigator/known-patterns.md`

The obs-query script runs as a pre-approved Bash command. Ad-hoc Python scripts and raw HTTP calls require explicit user permission for every invocation and fail entirely when run by subagents. Capturing queries in obs-query makes them reliably available to the homelab-investigator skill and any agent that uses it.

## Conventions

- Just recipes follow `<app>-<action>` naming (e.g., `jellyfin-deploy`, `metallb-status`)
- Each per-app justfile is imported by the top-level `kube/justfile`
- Labels use `app.kubernetes.io/name` consistently
- Replicas are controlled via `<APP>_REPLICAS` env vars with defaults
- `remove` targets use `|| true` to ignore errors during teardown

## YAML Frontmatter Template

```yaml
---
name: document-name  # required: lowercase-with-hyphens, max 64 chars
description: >  # required: when should AI load this? max 1024 chars
  Clear statement of when AI should load this document.
categories: [category1, category2]  # optional: broad classification
tags: [tag1, tag2]  # optional: specific concepts
related_docs:  # optional: relative paths from project root
  - path/to/doc.md
complexity: basic  # optional: basic|intermediate|advanced
---
```
