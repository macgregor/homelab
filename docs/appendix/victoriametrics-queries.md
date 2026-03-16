---
name: victoriametrics-queries
description: >
  Writing PromQL/MetricsQL or LogsQL queries, investigating metrics or logs,
  understanding available metrics and their labels.
categories: [observability]
tags: [victoriametrics, victorialogs, promql, metricsql, logsql, metrics, queries]
related_docs:
  - docs/06-observability.md
  - docs/appendix/telegraf.md
complexity: intermediate
---

# VictoriaMetrics & VictoriaLogs Query Reference

## API Endpoints

| Service | External URL | In-Cluster URL |
|---------|-------------|----------------|
| VictoriaMetrics | `https://victoriametrics.matthew-stratton.me` | `http://victoriametrics-server.obs.svc:8428` |
| VictoriaLogs | `https://victorialogs.matthew-stratton.me` | `http://victorialogs.obs.svc:9428` |

### VictoriaMetrics API Paths

| Path | Method | Description |
|------|--------|-------------|
| `/api/v1/query` | POST | Instant query (current value) |
| `/api/v1/query_range` | GET/POST | Range query (time series) |
| `/api/v1/label/__name__/values` | GET | List all metric names |
| `/api/v1/labels?match[]=<metric>` | GET | List labels for a metric |

### VictoriaLogs API Paths

| Path | Method | Description |
|------|--------|-------------|
| `/select/logsql/query` | POST | Log search (NDJSON response) |
| `/select/logsql/stats_query` | POST | Aggregated stats (Prometheus-format JSON) |
| `/select/logsql/streams?query=*` | GET | List active streams |
| `/health` | GET | Health check |

## Metrics Catalog

### Telegraf DaemonSet (System Metrics)

Source: `kube/observation/telegraf/helm-values.yml`. Runs on every node. Labels include `host` (node name).

**CPU** (`cpu` input):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `cpu_usage_idle` | `host`, `cpu` | % | CPU idle percentage. Filter `cpu="cpu-total"` for aggregate. Usage = `100 - idle`. |

**Memory** (`mem` input):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `mem_used_percent` | `host` | % | Memory usage percentage |
| `mem_available` | `host` | bytes | Available memory |
| `mem_total` | `host` | bytes | Total memory |
| `mem_free` | `host` | bytes | Free memory (not including buffers/cache) |
| `mem_buffered` | `host` | bytes | Buffered memory |
| `mem_cached` | `host` | bytes | Cached memory |
| `mem_used` | `host` | bytes | Used memory |
| `mem_available_percent` | `host` | % | Available memory percentage |
| `mem_swap_free` | `host` | bytes | Free swap |
| `mem_swap_total` | `host` | bytes | Total swap |

**Disk** (`disk` input, mount points `/` and `/boot`):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `disk_used_percent` | `host`, `path`, `device`, `fstype`, `mode` | % | Filesystem usage |
| `disk_free` | `host`, `path`, `device`, `fstype`, `mode` | bytes | Free space |
| `disk_total` | `host`, `path`, `device`, `fstype`, `mode` | bytes | Total space |
| `disk_used` | `host`, `path`, `device`, `fstype`, `mode` | bytes | Used space |

**Disk IO** (`diskio` input):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `diskio_io_await` | `host`, `name` | ms | IO wait time. Key device: `mmcblk0` (SD card). |
| `diskio_read_bytes` | `host`, `name` | bytes | Total bytes read (counter, use `rate()`) |
| `diskio_write_bytes` | `host`, `name` | bytes | Total bytes written (counter) |
| `diskio_reads` | `host`, `name` | count | Total read operations (counter) |
| `diskio_writes` | `host`, `name` | count | Total write operations (counter) |
| `diskio_io_time` | `host`, `name` | ms | Total IO time (counter) |
| `diskio_weighted_io_time` | `host`, `name` | ms | Weighted IO time (counter) |

**Network** (`net` input):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `net_bytes_recv` | `host`, `interface` | bytes | Bytes received (counter). Key interface: `eth0`. |
| `net_bytes_sent` | `host`, `interface` | bytes | Bytes sent (counter) |
| `net_err_in` | `host`, `interface` | count | Inbound errors |
| `net_err_out` | `host`, `interface` | count | Outbound errors |
| `net_drop_in` | `host`, `interface` | count | Inbound drops |
| `net_drop_out` | `host`, `interface` | count | Outbound drops |

**System** (`system` input):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `system_load1` | `host` | float | 1-minute load average |
| `system_load5` | `host` | float | 5-minute load average |
| `system_load15` | `host` | float | 15-minute load average |
| `system_uptime` | `host` | seconds | System uptime |
| `system_n_cpus` | `host` | count | Number of CPUs |

**Processes** (`processes` input):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `processes_blocked` | `host` | count | Blocked processes (waiting on IO) |
| `processes_running` | `host` | count | Running processes |
| `processes_zombies` | `host` | count | Zombie processes |
| `processes_total` | `host` | count | Total processes |
| `processes_total_threads` | `host` | count | Total threads |

**Temperature** (`temp` input):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `temp_temp` | `host`, `sensor` | Celsius | Temperature reading |

**Container Metrics** (`kubernetes` input):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `kubernetes_pod_container_cpu_usage_nanocores` | `host`, `namespace`, `pod_name`, `container_name`, `node_name` | nanocores | Container CPU usage |
| `kubernetes_pod_container_memory_working_set_bytes` | `host`, `namespace`, `pod_name`, `container_name`, `node_name` | bytes | Container memory working set |

Note: Telegraf kubernetes input uses `pod_name`/`container_name` labels, while KSM uses `pod`/`container`. Match by pod name value when joining.

### Telegraf SNMP (Device Metrics)

Source: `kube/observation/telegraf-snmp/helm-values.yml.gotmpl`. Single pod polling router and NAS.

**MikroTik Router** (`snmp_mikrotik` measurement, target `192.168.1.1`):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `snmp_mikrotik_cpu_load` | `host`, `source` | % | Router CPU load |
| `snmp_mikrotik_cpu_temperature` | `host`, `source` | Celsius | Router CPU temperature |
| `snmp_mikrotik_memory_used` | `host`, `source` | bytes | Used memory |
| `snmp_mikrotik_memory_total` | `host`, `source` | bytes | Total memory |
| `snmp_mikrotik_uptime` | `host`, `source` | centiseconds | System uptime (divide by 100 for seconds) |
| `snmp_mikrotik_interface_bytes_recv` | `host`, `source`, `name` | bytes | Interface bytes received (counter) |
| `snmp_mikrotik_interface_bytes_sent` | `host`, `source`, `name` | bytes | Interface bytes sent (counter) |
| `snmp_mikrotik_interface_oper_status` | `host`, `source`, `name` | enum | 1=up, 2=down, 6=notPresent |

**Synology NAS** (`snmp_synology` measurement, target `192.168.1.200`):
| Metric | Labels | Unit | Description |
|--------|--------|------|-------------|
| `snmp_synology_system_temperature` | `host`, `source` | Celsius | System temperature |
| `snmp_synology_load_1m` | `host`, `source` | float | 1-minute load average |
| `snmp_synology_load_5m` | `host`, `source` | float | 5-minute load average |
| `snmp_synology_load_15m` | `host`, `source` | float | 15-minute load average |
| `snmp_synology_uptime` | `host`, `source` | centiseconds | System uptime |
| `snmp_synology_memory_total_real_kb` | `host`, `source` | KB | Total physical memory |
| `snmp_synology_memory_avail_real_kb` | `host`, `source` | KB | Available physical memory |
| `snmp_synology_memory_buffered_kb` | `host`, `source` | KB | Buffered memory |
| `snmp_synology_memory_cached_kb` | `host`, `source` | KB | Cached memory |
| `snmp_synology_disk_disk_status` | `host`, `source`, `disk_id` | enum | 1=Normal, 2=Initialized, 3=NotInitialized, 4=SystemPartitionFailed, 5=Crashed |
| `snmp_synology_disk_disk_temperature` | `host`, `source`, `disk_id` | Celsius | Disk temperature |
| `snmp_synology_raid_raid_status` | `host`, `source`, `raid_name` | enum | 1=Normal, 2=Repairing, 11=Degraded, 12=Crashed |
| `snmp_synology_storage_storage_used` | `host`, `source`, `storage_descr` | allocation units | Storage used (multiply by allocation_units for bytes) |
| `snmp_synology_storage_storage_size` | `host`, `source`, `storage_descr` | allocation units | Storage total size |
| `snmp_synology_storage_allocation_units` | `host`, `source`, `storage_descr` | bytes | Size of one allocation unit |

### kube-state-metrics (KSM)

Source: `kube/observation/kube-state-metrics/helm-values.yml`. Enabled collectors: daemonsets, deployments, jobs, nodes, pods, statefulsets.

| Metric | Labels | Description |
|--------|--------|-------------|
| `kube_pod_status_phase` | `namespace`, `pod`, `phase`, `uid` | Value 1 for current phase, 0 otherwise. Phases: Running, Pending, Succeeded, Failed, Unknown. |
| `kube_pod_container_status_restarts_total` | `namespace`, `pod`, `container` | Container restart counter |
| `kube_pod_container_resource_limits` | `namespace`, `pod`, `container`, `resource`, `unit`, `node` | Resource limits. Filter `resource="memory"` or `resource="cpu"`. |
| `kube_pod_container_resource_requests` | `namespace`, `pod`, `container`, `resource`, `unit`, `node` | Resource requests |
| `kube_deployment_spec_replicas` | `namespace`, `deployment` | Desired replicas |
| `kube_deployment_status_replicas_available` | `namespace`, `deployment` | Available replicas |
| `kube_daemonset_status_desired_number_scheduled` | `namespace`, `daemonset` | Desired scheduled pods |
| `kube_daemonset_status_number_ready` | `namespace`, `daemonset` | Ready pods |
| `kube_node_status_condition` | `node`, `condition`, `status` | Node conditions. Filter `status="true"`. Conditions: Ready, MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable. |
| `kube_statefulset_replicas` | `namespace`, `statefulset` | Desired replicas |
| `kube_statefulset_status_replicas_ready` | `namespace`, `statefulset` | Ready replicas |

## PromQL Quick Reference

VictoriaMetrics uses MetricsQL, a superset of PromQL. Key differences: supports subqueries in `over_time` functions, implicit `step` in range selectors.

### Filters
```
metric{label="value"}           # exact match
metric{label=~"regex"}          # regex match
metric{label!="value"}          # not equal
metric{label!~"regex"}          # negative regex
```

### Aggregations
```
sum by (label) (metric)         # sum grouped by label
avg by (label) (metric)         # average grouped by label
count by (label) (metric)       # count grouped by label
topk(N, metric)                 # top N by value
sort_desc(metric)               # sort descending
```

### Over-time Functions
```
avg_over_time(metric[window:])       # average over window
min_over_time(metric[window:])       # minimum over window
max_over_time(metric[window:])       # maximum over window
rate(counter[window])                # per-second rate of counter
increase(counter[window])            # total increase over window
last_over_time(metric[window])       # last value in window
```

MetricsQL extension -- subqueries in over_time:
```
avg_over_time((100 - cpu_usage_idle{cpu="cpu-total"})[6h:])
```

## Useful Query Patterns

### NAS Memory Usage %
Can't subtract across SNMP metrics with different label structures in PromQL. Query individually and compute in Python:
```python
total = vm_scalar("snmp_synology_memory_total_real_kb")
avail = vm_scalar("snmp_synology_memory_avail_real_kb")
buf = vm_scalar("snmp_synology_memory_buffered_kb")
cached = vm_scalar("snmp_synology_memory_cached_kb")
used_pct = 100 * (total - avail - buf - cached) / total
```

### NAS Storage Usage %
Requires multiplying by allocation units. Query three series and compute:
```python
used = snmp_synology_storage_storage_used * allocation_units
size = snmp_synology_storage_storage_size * allocation_units
pct = used / size * 100
```

### Router Memory %
```promql
100 * snmp_mikrotik_memory_used / snmp_mikrotik_memory_total
```

### CPU Usage %
```promql
100 - cpu_usage_idle{cpu="cpu-total"}
```

### Pod Restarts in Last Hour
```promql
sort_desc(increase(kube_pod_container_status_restarts_total[1h]) > 0)
```

### Unhealthy Pods
```promql
kube_pod_status_phase{phase!="Running",phase!="Succeeded"} == 1
```

### Deployment Health (Unavailable Replicas)
```promql
kube_deployment_spec_replicas - kube_deployment_status_replicas_available
```

### Memory Pressure (Usage vs Limits)
Query independently due to label mismatch (Telegraf uses `pod_name`, KSM uses `pod`):
```python
usage = vm_query("kubernetes_pod_container_memory_working_set_bytes")  # pod_name label
limits = vm_query('kube_pod_container_resource_limits{resource="memory"}')  # pod label
# Join in Python by matching pod name values
```

## LogsQL Quick Reference

VictoriaLogs uses LogsQL for log queries. Docs: https://docs.victoriametrics.com/victorialogs/logsql/

### Filtering
```
word                            # contains word
"exact phrase"                  # contains phrase
_msg:~"regex"                   # regex match on message
field:value                     # exact field match
field:~"regex"                  # regex on field
_time:1h                        # last 1 hour
_time:24h                       # last 24 hours
```

### Pipes
```
| extract "pattern" from _msg   # extract fields from message
| filter field:~"regex"         # filter extracted fields
| fields field1, field2         # select output fields
| stats by (field) count() as n # aggregate
| sort by (field) desc          # sort results
```

### Extract Patterns
Use `<field_name>` to capture, `<_>` to skip:
```
| extract "<client_ip> <_> <_> [<_>] \"<method> <path> <_>\" <status>" from _msg
```
Escaped quotes `\"` match literal `"` in the log line.

## Log Query Patterns

### Nginx Access Log Parsing
Full extract pattern (from security dashboard):
```logsql
log_type:access stream:stdout
| extract "<client_ip> <_> <_> [<_>] \"<method> <path> <_>\" <status> <body_bytes> \"<_>\" \"<_>\" <_> <request_time> [<upstream>]" from _msg
| fields _time, client_ip, method, path, status, body_bytes, request_time, upstream
```

### Status Code Distribution
```logsql
log_type:access stream:stdout
| extract "\" <status> <_>" from _msg
| filter status:~"^[0-9]+$"
| stats by (status) count() as requests
```

### Firewall Drop Parsing
```logsql
_msg:~"firewall,info"
| extract "firewall,info <action> <chain>: in:<in_iface> out:<out_iface>, connection-state:<conn_state> src-mac <src_mac>, proto <proto>, <src_ip>:<src_port>-><dst_ip>:<dst_port>, len <pkt_len>" from _msg
| fields _time, action, chain, proto, conn_state, src_ip, src_port, dst_ip, dst_port
```

### Threat Intelligence Egress Hits
```logsql
_msg:~"firewall,info" _msg:~"threat-intel"
| extract "firewall,info <action> <chain>: in:<in_iface> out:<out_iface>, connection-state:<conn_state> src-mac <src_mac>, proto <proto>, <src_ip>:<src_port>-><dst_ip>:<dst_port>, len <pkt_len>" from _msg
| fields _time, proto, src_ip, src_port, dst_ip, dst_port, src_mac
```

### ModSecurity Events
```logsql
log_type:modsecurity
```

## Naming Conventions

- **Telegraf**: `<measurement>_<field>`. Example: `cpu_usage_idle`, `mem_used_percent`, `net_bytes_recv`.
- **SNMP**: `snmp_<device>_<field>` for scalars, `snmp_<device>_<table>_<field>` for tables. Example: `snmp_mikrotik_cpu_load`, `snmp_synology_disk_disk_status`.
- **KSM**: `kube_<resource>_<metric>`. Example: `kube_pod_status_phase`, `kube_deployment_spec_replicas`.
- **Telegraf kubernetes**: `kubernetes_pod_container_<field>`. Example: `kubernetes_pod_container_memory_working_set_bytes`.

## Data Retention

- **VictoriaMetrics**: 30 days (default, no explicit retention flag set)
- **VictoriaLogs**: 7 days (`retentionPeriod: 7d` in helm-values.yml)
