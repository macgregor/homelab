# Query Recipes

Per-command usage, output fields, and interpretation guidance for `obs-query`.

## Health Overview

### `health`
```
obs-query health
```
**Output**: Single JSON object with `cpu_pct`, `mem_pct`, `disk_pct`, `temp_c` (keyed by node), `router` (cpu_load, temp_c, mem_pct), `nas` (temp_c, load_1m, disk_status, raid_status), `pod_restarts` (list), `pods_not_running` (list).

**Interpretation**: First command to run. Scan all fields for threshold violations (see SKILL.md thresholds table). Empty `pod_restarts` and `pods_not_running` = healthy cluster.

### `node-health [node]`
```
obs-query node-health          # all nodes
obs-query node-health k3-m1    # single node
```
**Output**: One JSON line per node with `cpu_pct`, `mem_pct`, `disk_pct`, `temp_c`, `load1/5/15`, `uptime_s`, `procs_blocked`, `procs_zombies`, `net_err_in`, `net_drop_in`.

**Interpretation**:
- `procs_blocked > 0`: Processes waiting on IO. Correlate with `disk` command. Persistent blocking = NFS stall or SD card issue.
- `procs_zombies > 0`: Zombie processes. Usually harmless unless growing.
- `net_err_in` or `net_drop_in > 0`: Network errors. Check cable, switch, or driver issues.
- `load1 > 4.0`: RPi 4B has 4 cores. Load > core count = CPU saturation.

### `pod-health [namespace]`
```
obs-query pod-health           # all namespaces
obs-query pod-health media     # single namespace
```
**Output**: First line is `phase_counts` (Running, Pending, Failed, etc.). Subsequent lines: `type: restarts` (pods with nonzero restart count) and `type: unhealthy` (pods not in Running/Succeeded).

## Node Diagnostics

### `cpu [node] [window]`
```
obs-query cpu                  # all nodes, 6h window
obs-query cpu k3-n1 24h        # single node, 24h window
```
**Output**: Per-node `current_pct`, `avg_pct`, `min_pct`, `max_pct` over window.

**Thresholds**: avg >80% sustained = warning, >95% = critical. High max with low avg = spiky workload (usually fine). High avg = sustained pressure.

### `memory [node] [window]`
```
obs-query memory
obs-query memory k3-m1 24h
```
**Output**: Per-node `current_pct`, `avg_pct`, `available_mb`, `total_mb`.

**Thresholds**: >85% = warning, >95% = OOM risk. RPi 4B has 8GB. If `available_mb` < 500, investigate top consumers with `resource-pressure`.

### `disk [node]`
```
obs-query disk
obs-query disk k3-m1
```
**Output**: Per-node `used_pct`, `free_mb`, `io_await_ms` (keyed by device), `read_kbs`, `write_kbs` (keyed by device).

**Thresholds**:
- `used_pct > 80%`: Warning. `> 90%`: Critical.
- `io_await_ms > 100` on `mmcblk0`: SD card degradation. Check for filesystem errors.
- High write rate on `mmcblk0`: Excessive writes shorten SD card life.

### `temperature [node] [window]`
```
obs-query temperature
obs-query temperature k3-m1 24h
```
**Output**: Per-node `current_c`, `avg_c`, `max_c` (keyed by sensor).

**Thresholds**: >70C = warning, >80C = RPi 4B throttles CPU. If max_c frequently hits 80+, improve cooling.

### `network [node]`
```
obs-query network
obs-query network k3-n1
```
**Output**: Per-node `recv_kbs`, `sent_kbs`, `net_err_in`, `net_err_out`, `net_drop_in`, `net_drop_out`.

**Interpretation**: Baseline traffic is typically <100 KB/s per node. Spikes during media streaming or backups are normal. Nonzero error/drop counters warrant investigation.

## Infrastructure

### `router`
```
obs-query router
```
**Output**: `cpu_load`, `temp_c`, `mem_pct`, `mem_used`, `mem_total`, `uptime_s`, `interfaces` (list with `name`, `oper_status`, `recv_kbs`, `sent_kbs`).

**Interpretation**:
- `cpu_load > 80`: Unusual for MikroTik RB5009 in home use. Check for routing loops or attack traffic.
- `oper_status`: 1=up, 2=down, 6=notPresent. Down interfaces should be expected (unused ports).
- `uptime_s`: Divide by 86400 for days. Very long uptime + issues = possible firmware bug, consider reboot.

### `nas`
```
obs-query nas
```
**Output**: `temp_c`, `load_1m/5m/15m`, `uptime_s`, `mem_used_kb`, `mem_total_kb`, `mem_pct`, `disks` (list with `disk_id`, `status`, `temp_c`), `raids` (list with `raid_name`, `status`).

**Interpretation**:
- `disk status`: 1=Normal, 2=Initialized, 3=NotInitialized, 4=SystemPartitionFailed, 5=Crashed.
- `raid status`: 1=Normal, 2=Repairing (monitor), 11=Degraded (critical), 12=Crashed (emergency).
- `disk temp_c > 50`: Warning for HDD longevity.
- `mem_pct`: NAS memory includes cache. High usage is normal if load is low.

### `nas-storage`
```
obs-query nas-storage
```
**Output**: Per-volume `volume`, `used_gb`, `size_gb`, `used_pct`.

**Thresholds**: `used_pct > 80%` = warning, `> 90%` = critical. `/volume1` is the main data volume.

## Kubernetes

### `pod-restarts [namespace] [window]`
```
obs-query pod-restarts             # all namespaces, 1h
obs-query pod-restarts media 6h    # media namespace, 6h
```
**Output**: Per-pod `pod`, `namespace`, `container`, `restarts` (count in window).

**Thresholds**: >5 in 1h = investigate. Check `resource-pressure` for OOM. Check pod logs via `kubectl logs`.

### `resource-pressure [namespace]`
```
obs-query resource-pressure
obs-query resource-pressure media
```
**Output**: Per-container `pod`, `container`, `namespace`, `usage_mb`, `limit_mb` (if set), `ratio` (usage/limit).

**Interpretation**: `ratio > 0.9` = near OOM kill. `ratio > 0.8` = warning. Missing `limit_mb` = no memory limit set. Containers without limits can't be OOM-killed but can cause node pressure.

### `deployments [namespace]`
```
obs-query deployments
obs-query deployments obs
```
**Output**: Per-deployment/daemonset `type`, `namespace`, `name`, `desired`, `available`/`ready`, `unavailable`, `healthy`.

**Interpretation**: `healthy: false` = pods not running at desired count. Check `pod-health` and pod events for the namespace.

### `node-conditions`
```
obs-query node-conditions
```
**Output**: Per-condition `node`, `condition`, `ok`.

**Interpretation**: Only `Ready=true` should appear. Other true conditions (MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable) indicate node-level problems.

## Logs

### `ingress-status [window]`
```
obs-query ingress-status        # last 1h
obs-query ingress-status 24h
```
**Output**: Per-status-code `status`, `requests` (count).

**Interpretation**: Baseline is mostly 200/304. High 429 = rate limiting active. High 5xx = backend issues. High 403 = auth/WAF blocking. High 499 = client disconnects (often bots).

### `ingress-errors [window] [limit]`
```
obs-query ingress-errors 1h 20
```
**Output**: Per-request `_time`, `client_ip`, `method`, `path`, `status`, `body_bytes`, `request_time`, `upstream`.

**Interpretation**: Group by `upstream` to find which backend is failing. Group by `client_ip` to find attack sources. `status 502` + empty upstream = backend unreachable.

### `firewall-drops [window] [limit]`
```
obs-query firewall-drops 1h 20
```
**Output**: Per-drop `_time`, `action`, `chain`, `proto`, `src_ip`, `src_port`, `dst_ip`, `dst_port`.

**Interpretation**:
- `drop-input-wan`: External probes blocked at WAN. Normal internet noise.
- `drop-invalid`: Invalid connection state. Usually TCP RST for expired connections.
- `drop-forward-wan`: Blocked outbound traffic. Check if internal host is compromised.
- High volume from single `src_ip` = targeted scan.

### `threat-intel [window] [limit]`
```
obs-query threat-intel          # last 24h (default wider window since hits should be rare)
obs-query threat-intel 7d 100   # last week
```
**Output**: Per-event `_time`, `proto`, `src_ip`, `src_port`, `dst_ip`, `dst_port`, `src_mac`.

**Interpretation**:
- Any hit means a LAN device attempted a connection to an IP on a curated threat feed (Spamhaus DROP/EDROP, abuse.ch Feodo Tracker).
- `src_ip` identifies which LAN device made the connection. Cross-reference with DHCP leases to identify the device.
- `src_mac` provides hardware identification even if the IP changes.
- `dst_ip` is the threat-listed destination. Look it up on Spamhaus/abuse.ch for context.
- Zero results is the expected healthy state. Any hit warrants investigation.

### `modsecurity [window] [limit]`
```
obs-query modsecurity 1h 20
```
**Output**: Per-event `_time`, `_msg` (raw ModSecurity transaction JSON).

**Interpretation**: Parse `_msg` for rule IDs and matched data. False positives are common; cross-reference with `ingress-errors` to see if requests were actually blocked (403 status).

### `search-logs <query> [limit]`
```
obs-query search-logs '_msg:~"error"' 20
obs-query search-logs '_time:1h log_type:access status:502' 50
```
**Output**: Raw log entries matching the LogsQL query.

**Usage**: Pass-through for ad-hoc LogsQL queries. See `docs/appendix/victoriametrics-queries.md` for LogsQL syntax reference.
