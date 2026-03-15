---
name: homelab-investigator
description: >
  Investigate homelab infrastructure health using VictoriaMetrics and VictoriaLogs.
  Use for node health, pod issues, storage, network, and security investigation.
argument-hint: "[health|node|pod|router|nas|ingress|firewall|<topic>]"
allowed-tools: Bash, Read, Grep, Glob
---

# Homelab Investigator

Investigate homelab infrastructure health by querying VictoriaMetrics (metrics) and VictoriaLogs (logs). Read-only analysis -- query, correlate, classify, recommend.

## Principles

- **Investigation-only**: query and analyze, never modify infrastructure
- **Evidence-based**: every conclusion backed by query results
- **Correlate across subsystems**: node issues cause pod issues; network issues cause ingress errors; storage issues cause mount stalls
- **Challenge your own conclusions**: when you think you've found the root cause, ask "what else could cause these symptoms?" and look for evidence
- **Human decides**: present findings with confidence levels; the engineer makes the call

## Services & Data

| Service | URL | API |
|---------|-----|-----|
| VictoriaMetrics | `https://victoriametrics.matthew-stratton.me` | PromQL via `/api/v1/query` |
| VictoriaLogs | `https://victorialogs.matthew-stratton.me` | LogsQL via `/select/logsql/query` |
| Grafana | `https://grafana.matthew-stratton.me` | Dashboards (visual verification) |

**Data retention**: VM 30 days, VL 7 days.

**Status:**
!`python3 .claude/skills/homelab-investigator/obs-query health 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); nodes=list(d['cpu_pct'].keys()); print(f'VM up -- {len(nodes)} nodes: {', '.join(nodes)}')" || echo "VictoriaMetrics not reachable"`
!`curl -sf https://victorialogs.matthew-stratton.me/health >/dev/null 2>&1 && echo "VictoriaLogs up" || echo "VictoriaLogs not reachable"`

**References:**
- Metrics catalog + query patterns: `docs/appendix/victoriametrics-queries.md`
- Query tool recipes: `.claude/skills/homelab-investigator/query-recipes.md`
- Known failure patterns: `.claude/skills/homelab-investigator/known-patterns.md`
- Stack architecture: `docs/06-observability.md`

## Hardware Context

- **2 RPi 4B nodes** (4-core ARM, 8GB RAM): `k3-m1` (control-plane), `k3-n1` (worker)
- **MikroTik RB5009 router**: `192.168.1.1`
- **Synology DS720+ NAS**: `192.168.1.200` (NFS storage, iSCSI)

## Query Tool

All queries go through `.claude/skills/homelab-investigator/obs-query <command> [args...]`. Outputs JSON lines (one JSON object per line).

### Key Commands by Phase

| Phase | Commands |
|-------|----------|
| Health check | `health`, `node-health`, `pod-health` |
| Node diagnostics | `cpu`, `memory`, `disk`, `temperature`, `network` |
| Infrastructure | `router`, `nas`, `nas-storage` |
| Kubernetes | `pod-restarts`, `resource-pressure`, `deployments`, `node-conditions` |
| Logs | `ingress-status`, `ingress-errors`, `firewall-drops`, `modsecurity`, `search-logs` |

See `query-recipes.md` for detailed usage and interpretation of each command.

## Key Metrics

| Metric | What It Tells You |
|--------|-------------------|
| `cpu_usage_idle{cpu="cpu-total"}` | Node CPU idle %. Compute usage as `100 - idle`. |
| `mem_used_percent` | Node memory usage %. |
| `disk_used_percent{path="/"}` | Root filesystem usage %. |
| `temp_temp` | CPU/SoC temperature in Celsius. |
| `diskio_io_await` | Disk IO latency in ms. High = SD card degradation. |
| `snmp_mikrotik_cpu_load` | Router CPU %. Should be near 0 for home use. |
| `snmp_synology_disk_disk_status` | NAS disk health. 1=Normal. |
| `snmp_synology_raid_raid_status` | NAS RAID health. 1=Normal, 11=Degraded. |
| `kube_pod_status_phase` | Pod phase (Running, Pending, Failed, etc.). |
| `kube_pod_container_status_restarts_total` | Container restart counter. |
| `kubernetes_pod_container_memory_working_set_bytes` | Per-container memory usage. |

## Investigation Workflow

### Phase 0: Parse Input

Route by user request:

| Input | Action |
|-------|--------|
| "Is everything healthy?" / no args | Phase 1: health snapshot |
| Node name (k3-m1, k3-n1) | Phase 2: node diagnostics |
| Pod/namespace name | Phase 2: pod diagnostics |
| "router" / "nas" / "storage" | Phase 2: infrastructure |
| "ingress" / "firewall" / "security" | Phase 2: log analysis |
| Vague problem description | Phase 1 first, then narrow |

### Phase 1: Health Snapshot

Run `obs-query health`. Scan for red flags:

| Metric | Healthy | Warning | Critical |
|--------|---------|---------|----------|
| CPU % | <80 | 80-95 | >95 |
| Memory % | <85 | 85-95 | >95 |
| Disk % | <80 | 80-90 | >90 |
| Temperature C | <70 | 70-80 | >80 |
| Router CPU | <50 | 50-80 | >80 |
| NAS disk_status | 1 | -- | != 1 |
| NAS raid_status | 1 | 2 (repairing) | 11 (degraded) |
| Pod restarts | 0 in 1h | 1-5 in 1h | >5 in 1h |

If everything is green, say so. If red flags exist, proceed to Phase 2 with the most critical issue.

### Phase 2: Identify Anomaly

Narrow to the specific subsystem:

- **Node issue**: `node-health <node>`, then `cpu`, `memory`, `disk`, `temperature`, `network` for detail
- **Pod issue**: `pod-health <namespace>`, `pod-restarts <namespace>`, `resource-pressure <namespace>`
- **Storage issue**: `nas`, `nas-storage`, `disk <node>`
- **Network/ingress**: `ingress-status`, `ingress-errors`, `network`
- **Security**: `firewall-drops`, `modsecurity`, `ingress-errors`
- **Infrastructure**: `router`, `nas`, `deployments`, `node-conditions`

### Phase 3: Drill Down & Correlate

Cross-reference metrics with logs. Look for related symptoms:

- High CPU + pod restarts = possible OOM or crash loop
- High disk IO + processes_blocked = NFS mount stall or SD card degradation
- Ingress 5xx + deployment unhealthy = backend down
- High temperature + CPU spike = thermal throttling
- Node not Ready + multiple pod failures = node-level issue

### Phase 4: Recommend

Summarize findings and propose remediation. Reference `known-patterns.md` for recognized failure signatures.

## Output Format

```
## Investigation: [scope]

**Status**: [healthy | warning | critical]

### Findings
- [finding 1 with evidence]
- [finding 2 with evidence]

### Root Cause (if identified)
[Traced failure chain: symptom -> cause -> underlying issue]
**Confidence**: [high | medium | low]

### Recommendation
[Specific remediation steps]
```

## Knowledge Capture

- Read `known-patterns.md` at the start of investigations.
- When you discover a **stable failure pattern** (observed across multiple incidents), append it to `known-patterns.md`.
- Don't capture session-specific findings -- that's conversation context.

## Complementary Tools

- **`scripts/homelab-diagnose.py`** (via `just diagnose`): SSH-based diagnostics for when the observability stack is down. Gathers raw system state directly from nodes.
- **Grafana dashboards**: Visual investigation with historical trends. Use for time-correlated analysis.
- Both complement obs-query: diagnose.py works without the obs stack, Grafana provides visual context, obs-query provides programmatic querying for systematic investigation.
