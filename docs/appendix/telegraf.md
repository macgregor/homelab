---
name: telegraf
description: >
  Load this document when working with Telegraf configuration, plugin tuning,
  containerized deployment, metric filtering, or debugging collection issues.
categories: [observability, monitoring]
tags: [telegraf, metrics, influxdb, snmp, diskio, kubernetes, containers, memory, tail, elasticsearch, logs]
related_docs:
  - docs/06-observability.md
  - docs/appendix/grafana-dashboards.md
complexity: intermediate
---

# Telegraf Reference

Reference for AI agents working with Telegraf 1.x. Covers configuration model, plugin behavior, containerized deployment, memory management, and common pitfalls. Not a tutorial -- a concise working reference with links to official docs.

**Official documentation root:** https://docs.influxdata.com/telegraf/v1/

**Source code (v1.37):** https://github.com/influxdata/telegraf/tree/v1.37.3

---

## Table of Contents

1. [Critical Gotchas](#1-critical-gotchas)
2. [Configuration Model](#2-configuration-model)
3. [Agent Settings](#3-agent-settings)
4. [Per-Plugin Filters](#4-per-plugin-filters)
5. [Debugging](#5-debugging)
6. [Containerized Deployment](#6-containerized-deployment)
7. [Container Memory Behavior](#7-container-memory-behavior)
8. [Plugin Reference: diskio](#8-plugin-reference-diskio)
9. [Plugin Reference: disk](#9-plugin-reference-disk)
10. [Plugin Reference: kubernetes](#10-plugin-reference-kubernetes)
11. [Plugin Reference: SNMP](#11-plugin-reference-snmp)
12. [Plugin Reference: influxdb_v2 Output](#12-plugin-reference-influxdb_v2-output)
13. [Plugin Reference: tail](#13-plugin-reference-tail)
14. [Plugin Reference: elasticsearch Output](#14-plugin-reference-elasticsearch-output)
15. [Helm Charts](#15-helm-charts)
16. [Documentation Links](#16-documentation-links)

---

## 1. Critical Gotchas

### diskio hardcodes `/dev/` -- no env var override

The diskio plugin constructs paths as `/dev/<devName>` (hardcoded in `diskio_linux.go`). It does not respect `HOST_MOUNT_PREFIX`, `HOST_DEV`, or any environment variable. In containers where host `/dev` is not mounted at `/dev`, device name resolution fails with warnings like `Unable to gather disk name for "sda"`. Metrics still flow (collected from `/proc/diskstats` via `HOST_PROC`), but `name_templates` and `device_tags` won't work. Use `log_level: "error"` on the plugin to suppress these warnings.

### Mounting host `/dev` at container `/dev` breaks the container runtime

The container runtime (containerd/CRI-O) needs to create `/dev/termination-log` inside the container. If you mount the host's `/dev` read-only at the container's `/dev`, this mount point creation fails and the container won't start. Mounting it read-write exposes host device nodes. There is no clean workaround within the standard helm chart.

### SNMP table-level `oid` auto-discovers all columns

When a table entry has a top-level `oid` (e.g., `oid: "1.3.6.1.2.1.2.2"`), Telegraf performs a full SNMP walk and auto-discovers all columns -- even if you also list explicit `field` entries. This causes unwanted fields (like `ifPhysAddress`) to be collected and triggers deprecated conversion warnings. To collect only specific columns, omit the table-level `oid` and list each column as an explicit `field` with its full OID.

### `fieldinclude` applies across all measurements from a plugin

`fieldinclude`/`fieldexclude` is not scoped per measurement. If a plugin emits multiple measurement names (e.g., `kubernetes_node`, `kubernetes_pod_container`, `kubernetes_pod_network`), the filter applies to all of them. You cannot keep `rx_bytes` in `kubernetes_pod_network` while dropping it from `kubernetes_node` using a single plugin instance.

### `metric_buffer_limit` is pre-allocated at startup

The buffer is created as `make([]telegraf.Metric, capacity)` -- the full slice is allocated immediately, not grown on demand. Oversizing wastes memory. Size it based on actual metrics per cycle, not the default of 10,000.

### `memory.current` at the cgroup limit is normal for DaemonSet pods

Page cache from reading host `/proc/*` and `/sys/*` fills `memory.current` to the limit. This is reclaimable and does not cause OOM kills. See [Container Memory Behavior](#6-container-memory-behavior).

---

## 2. Configuration Model

Telegraf uses [TOML](https://toml.io/) configuration with four top-level sections:

```toml
[global_tags]          # key-value pairs added to all metrics
[agent]                # agent behavior (intervals, buffering, logging)
[[inputs.<plugin>]]    # one or more input plugin instances
[[outputs.<plugin>]]   # one or more output plugin instances
[[processors.<plugin>]] # optional metric transformation
[[aggregators.<plugin>]] # optional metric aggregation
```

### Processing pipeline

```
Inputs -> Processors -> Aggregators -> Outputs
                              \--(pass-through)--> Outputs
```

- Inputs write metrics to a shared channel.
- Processors form a chain, applied in config order.
- Aggregators consume metrics and emit aggregated results; originals pass through to outputs unless `drop_original = true`.
- Every output receives a copy of every metric (last output gets zero-copy for efficiency).

### Multiple instances

Any plugin can be instantiated multiple times with different configs:

```toml
[[inputs.snmp]]
  name = "router"
  agents = ["udp://192.168.1.1:161"]

[[inputs.snmp]]
  name = "nas"
  agents = ["udp://192.168.1.200:161"]
```

Each instance runs independently with its own collection goroutine.

### Measurement naming

Per-input settings control the measurement name in emitted metrics:

| Setting | Description |
|---------|-------------|
| `name_override` | Replace the plugin's default measurement name entirely. |
| `name_prefix` | Prepend a string to the measurement name. |
| `name_suffix` | Append a string to the measurement name. |

### Config loading

Telegraf loads config from `--config` (single file) and/or `--config-directory` (all `.conf` files in a directory, merged). In Helm chart deployments, the chart renders a single ConfigMap-mounted file. Telegraf does not support config reload via SIGHUP -- a restart is required after config changes.

---

## 3. Agent Settings

### Intervals and timing

| Setting | Default | Scope | Description |
|---------|---------|-------|-------------|
| `interval` | `"10s"` | global or per-input | Collection interval. Per-input override gives each input its own ticker. |
| `flush_interval` | `"10s"` | global or per-output | How often outputs write buffered metrics. Independent of collection. |
| `collection_jitter` | `"0s"` | global or per-input | Random delay before each collection. Prevents simultaneous sysfs reads. |
| `flush_jitter` | `"0s"` | global or per-output | Random delay added to flush interval. Prevents write spikes with many instances. |
| `collection_offset` | `"0s"` | global or per-input | Fixed offset for deterministic staggering (unlike jitter which is random). |

### Buffer and batching

| Setting | Default | Description |
|---------|---------|-------------|
| `metric_batch_size` | `1000` | Max metrics per `Write()` call to an output. |
| `metric_buffer_limit` | `10000` | Max unwritten metrics buffered per output. Pre-allocated at startup. When full, oldest metrics are silently dropped. Must be >= 2x `metric_batch_size`. |

**Sizing formula:** `metrics_per_cycle * buffer_minutes * (60 / interval_seconds)`

Example: 68 metrics/cycle at 30s interval, 5 minutes of buffer: `68 * 5 * 2 = 680`. Round up to the nearest `metric_batch_size` multiple.

Both settings can be overridden per-output in the output plugin's config block.

### Logging

| Setting | Default | Description |
|---------|---------|-------------|
| `debug` | `false` | Enable debug logging globally. |
| `quiet` | `false` | Suppress everything below error level globally. |
| `log_level` | (per-plugin) | Override log level for a specific plugin: `"error"`, `"warn"`, `"info"`, `"debug"`, `"trace"`. |

### Go runtime

Telegraf does not set `GOMEMLIMIT` or `GOGC` internally. Both can be set as container environment variables to tune GC behavior.

---

## 4. Per-Plugin Filters

Filters are compiled once at config load and applied at two pipeline points:

1. **Input side** (`RunningInput.MakeMetric`): before metrics enter the processor chain.
2. **Output side** (`RunningOutput.AddMetric`): before metrics enter the output buffer.

### Selection filters (keep or drop entire metrics)

| Setting | Type | Behavior |
|---------|------|----------|
| `namepass` | `[]string` (globs) | Only metrics whose measurement name matches pass. |
| `namedrop` | `[]string` (globs) | Metrics whose measurement name matches are dropped. |
| `tagpass` | `map[tag][]string` | Metric passes if named tag's value matches any pattern. |
| `tagdrop` | `map[tag][]string` | Metric dropped if named tag's value matches any pattern. |

When both `namepass` and `namedrop` are set, a metric must match `namepass` AND not match `namedrop`.

### Modification filters (remove fields/tags from surviving metrics)

| Setting | Type | Behavior |
|---------|------|----------|
| `fieldinclude` | `[]string` (globs) | Only matching fields are kept. |
| `fieldexclude` | `[]string` (globs) | Matching fields are removed. |
| `taginclude` | `[]string` (globs) | Only matching tag keys are emitted. |
| `tagexclude` | `[]string` (globs) | Matching tag keys are removed. |

When both include and exclude are set, a field/tag must match include AND not match exclude. If all fields are removed, the entire metric is dropped.

`fieldinclude` filters at collection time, before metrics enter the buffer. This reduces buffer memory usage and downstream ingestion volume.

**Deprecated aliases:** `fieldpass`/`fielddrop` were renamed to `fieldinclude`/`fieldexclude` in v1.29.0 (removal in v1.40.0).

---

## 5. Debugging

**Docs:** https://docs.influxdata.com/telegraf/v1/administration/troubleshooting/

### `--test` flag

Runs all inputs once, prints metrics to stdout in line protocol format, then exits. Does not send to outputs. Essential for verifying what a config actually collects:

```bash
telegraf --config /etc/telegraf/telegraf.conf --test
```

### `--input-filter` / `--output-filter`

Restrict which plugins run. Combine with `--test` to isolate a single input:

```bash
telegraf --config telegraf.conf --test --input-filter diskio --output-filter ""
```

### `internal` input plugin

Exposes Telegraf's own operational metrics: gather errors, metrics written/dropped, buffer fullness. Enable with `[[inputs.internal]]`. Set `collect_memstats = false` to reduce noise unless debugging Go memory.

### Common warning patterns

| Warning | Cause | Fix |
|---------|-------|-----|
| `Unable to gather disk name for "X"` | diskio can't stat `/dev/X` in container | `log_level = "error"` on diskio input |
| `DeprecationWarning: Value "hwaddr"` | SNMP table auto-discovered ifPhysAddress | Remove table-level `oid`, use explicit fields |
| `Metric buffer overflow; N metrics dropped` | Output unreachable longer than buffer allows | Increase `metric_buffer_limit` or fix output |

---

## 6. Containerized Deployment

### Environment variables

Telegraf uses [gopsutil](https://github.com/shirou/gopsutil) for system metrics. gopsutil reads these environment variables to find host filesystem paths:

| Env Var | Default | Used by |
|---------|---------|---------|
| `HOST_PROC` | `/proc` | cpu, mem, swap, net, diskio, processes, system |
| `HOST_SYS` | `/sys` | temp, diskio (sysfs block info) |
| `HOST_MOUNT_PREFIX` | (none) | disk plugin only (Telegraf-specific, not gopsutil) |
| `HOST_ETC` | `/etc` | (rarely used) |
| `HOST_VAR` | `/var` | (rarely used) |
| `HOST_RUN` | `/run` | (rarely used) |
| `HOST_DEV` | `/dev` | gopsutil device resolution (diskio ignores this -- see [gotcha](#diskio-hardcodes-dev----no-env-var-override)) |

### The hostfs mount pattern

Standard approach for monitoring containers:

```bash
# Mount host root read-only, set env vars to use prefixed paths
docker run -v /:/hostfs:ro \
  -e HOST_PROC=/hostfs/proc \
  -e HOST_SYS=/hostfs/sys \
  -e HOST_MOUNT_PREFIX=/hostfs \
  telegraf
```

This makes the host's `/proc`, `/sys`, and all mount points accessible inside the container. The disk plugin uses `HOST_MOUNT_PREFIX` for path remapping (see [disk plugin](#host_mount_prefix-remapping)).

### What the hostfs mount exposes

Mounting host `/` at `/hostfs` makes **everything** on the host visible: all mount points (NFS, iSCSI, overlay), all container rootfs overlays, all kubelet volume mounts. The disk plugin discovers these via `/proc/self/mounts` and calls `statfs()` on each unless filtered. Use `mount_points`, `ignore_fs`, or `ignore_mount_opts` to restrict what gets measured.

---

## 7. Container Memory Behavior

Monitoring DaemonSets that mount host filesystems show `memory.current` near the cgroup limit. This is normal. The kernel fills reclaimable page cache (from reading `/proc/*`, `/sys/*`, etc.) up to the limit and evicts it on demand. OOM kills only occur when non-reclaimable memory (anon + kernel) exceeds the limit.

Key metrics: `kubectl top` reports `memory.working_set_bytes` (`memory.current - inactive_file`), which excludes reclaimable pages. The OOM killer uses `memory.current` vs `memory.max`, but reclaims page cache first. A pod showing 95Mi in `kubectl top` with `memory.current` at 150Mi is healthy -- the 55Mi difference is reclaimable cache.

Typical breakdown: anon ~32MB (Go heap, metric buffers), file ~120MB (page cache), kernel ~2.5MB.

### Memory tuning levers

| Lever | What it reduces | Effect on page cache |
|-------|----------------|---------------------|
| `metric_buffer_limit` | Heap (anon) | None |
| `metric_batch_size` | Peak heap during writes | None |
| `fieldinclude` | Metrics in buffer (anon) | None |
| `mount_points` on disk | statfs() calls | Reduces page cache slightly |
| `GOMEMLIMIT` env var | Go GC target | Reduces anon by triggering GC earlier |
| Container memory limit | Everything | Page cache adjusts; anon is the OOM risk |

The memory limit should be set with awareness that page cache will fill the remaining space. Size the limit for anon headroom, not total usage.

---

## 8. Plugin Reference: diskio

**Source:** `plugins/inputs/diskio/`

Collects disk I/O statistics from `/proc/diskstats`.

### Configuration

```toml
[[inputs.diskio]]
  ## Filter to specific devices (exact names or globs)
  # devices = ["sda", "sdb", "mmcblk*"]

  ## Skip serial number tag
  # skip_serial_number = true

  ## Add udev properties as tags (Linux only)
  # device_tags = ["ID_FS_TYPE", "ID_FS_USAGE"]

  ## Custom name templates using udev properties
  # name_templates = ["$ID_FS_LABEL", "$DM_VG_NAME/$DM_LV_NAME"]

  ## Per-plugin log level
  # log_level = "error"
```

### Device filtering behavior

The `devices` filter behaves differently depending on whether patterns contain glob characters:

- **Exact names (no globs):** Passed to gopsutil which filters at the `/proc/diskstats` level. Only matching devices are returned. `diskName()` is still called on each returned device.
- **Glob patterns (`*`, `?`, `[`):** All devices are returned from gopsutil. `diskName()` is called on every device, then the glob filter is applied. This means name resolution warnings fire for all devices, not just matched ones.

### Derived fields

Calculated from deltas between consecutive collections. Not emitted on the first collection or when counter wraparound is detected.

| Field | Formula | Unit |
|-------|---------|------|
| `io_await` | `(delta_read_time + delta_write_time) / (delta_reads + delta_writes)` | ms per I/O op |
| `io_svctm` | `delta_io_time / (delta_reads + delta_writes)` | ms per I/O op |
| `io_util` | `100 * delta_io_time / wall_time_ms` | % busy |

### Container limitations

In containers, `name_templates`, `device_tags`, and serial numbers don't work because `diskInfo()` hardcodes `/dev/` (see [gotcha](#diskio-hardcodes-dev----no-env-var-override)). Core metrics from `/proc/diskstats` work correctly via `HOST_PROC`.

---

## 9. Plugin Reference: disk

**Source:** `plugins/inputs/disk/`, `plugins/common/psutil/ps.go`

Collects filesystem usage via `statfs()`.

### Configuration

```toml
[[inputs.disk]]
  ## Whitelist specific mount points (exact match, not glob)
  # mount_points = ["/", "/boot"]

  ## Blacklist filesystem types
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

  ## Blacklist mount options (e.g., filter bind mounts)
  # ignore_mount_opts = ["bind"]
```

### Evaluation order

1. Mount option exclusion (`ignore_mount_opts`)
2. Mount point whitelist (`mount_points`) -- if set, only listed paths pass
3. Filesystem type exclusion (`ignore_fs`)
4. `HOST_MOUNT_PREFIX` path remapping for `statfs()`

`autofs` is always excluded (hardcoded) to prevent triggering automounts.

### HOST_MOUNT_PREFIX remapping

When set (e.g., `/hostfs`), the plugin prepends the prefix to mount points before calling `statfs()`. For example, mount point `/` becomes `statfs("/hostfs/")`. The reported path is stripped back to `/`. If the prefixed path collides with an existing mount point, it is skipped to avoid double-counting.

### Container pitfalls

- **NFS mounts:** `statfs()` on unreachable NFS mounts blocks with no timeout. Use `mount_points` or `ignore_fs: ["nfs", "nfs4"]` to avoid hangs.
- **Duplicate metrics:** Without `mount_points`, the plugin sees every kubelet bind mount (iSCSI volumes, NFS volumes, local-path volumes) and emits duplicate metrics for the same underlying device.
- **Page cache:** Each `statfs()` reads filesystem metadata, generating page cache charged to the container's cgroup.

---

## 10. Plugin Reference: kubernetes

**Source:** `plugins/inputs/kubernetes/`

Collects container and pod metrics from the kubelet summary API.

### Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/stats/summary` | Node-level and per-pod/container resource usage |
| `/pods` | Pod metadata for label enrichment |

### Measurements

| Measurement | Series per | Key fields |
|-------------|-----------|------------|
| `kubernetes_node` | node | cpu_usage_nanocores, memory_working_set_bytes, network rx/tx |
| `kubernetes_pod_container` | node x pod x container | cpu_usage_nanocores, memory_working_set_bytes, rootfs/logsfs |
| `kubernetes_pod_network` | node x pod | rx_bytes, tx_bytes, rx_errors, tx_errors |
| `kubernetes_pod_volume` | node x pod x volume | available_bytes, capacity_bytes, used_bytes |
| `kubernetes_system_container` | node x system container | cpu, memory (kubelet, runtime, pods) |

### Cardinality management

This is typically the highest cardinality input because series multiply with pod/container count. Key controls:

- **`fieldinclude`:** Retain only fields used by dashboards. Applies across all measurements from the plugin (no per-measurement scoping).
- **`label_include` / `label_exclude`:** Control which pod labels become tags. Default is `label_exclude = ["*"]` (exclude all). Enabling pod labels multiplies cardinality by label value combinations.
- **Measurement-level filtering:** Use `namepass`/`namedrop` if you need different field sets per measurement, but this requires multiple plugin instances.

---

## 11. Plugin Reference: SNMP

**Source:** `plugins/inputs/snmp/`

Polls SNMP agents for metrics via GET and WALK operations.

### Connection config

```toml
[[inputs.snmp]]
  agents = ["udp://192.168.1.1:161"]
  version = 2                          # 1, 2, or 3
  community = "public"                 # v1/v2c only
  timeout = "5s"
  retries = 3
  agent_host_tag = "source"            # tag key for the agent address
  name = "snmp_router"                 # measurement name prefix
```

### Table collection modes

**Full table walk** (table-level `oid` set):
```toml
[[inputs.snmp.table]]
  oid = "IF-MIB::ifTable"       # walks entire table, auto-discovers all columns
  name = "interface"
```

All columns are auto-discovered from MIB definitions. Explicit `field` entries are merged (deduped by OID). Index columns are auto-tagged. Auto-discovered fields get their `conversion` set automatically from the MIB's DISPLAY-HINT.

**Explicit fields only** (no table-level `oid`):
```toml
[[inputs.snmp.table]]
  name = "interface"            # no oid = only collects listed fields
  [[inputs.snmp.table.field]]
    oid = "1.3.6.1.2.1.2.2.1.2"
    name = "name"
    is_tag = true
  [[inputs.snmp.table.field]]
    oid = "1.3.6.1.2.1.2.2.1.10"
    name = "bytes_recv"
```

Only listed OIDs are fetched. No auto-discovery. Preferred when you need specific columns and want to avoid deprecated conversion warnings from auto-discovered fields.

### Conversion options

| Value | Description |
|-------|-------------|
| `""` (auto) | Detected from MIB. Non-UTF-8 OctetStrings are hex-encoded. |
| `"float"` / `"float(N)"` | Convert to float64, optionally divide by 10^N. |
| `"int"` | Convert to int64. |
| `"ipaddr"` | Convert 4/16-byte value to IP string. |
| `"displayhint"` | Format using MIB's DISPLAY-HINT. Preferred for MAC addresses, etc. |
| `"hwaddr"` | **Deprecated (v1.33.0).** Use `"displayhint"` instead. |

### `inherit_tags`

Per-table setting. Copies tag values from top-level (non-table) fields into each row of the table. Useful for propagating device identity (e.g., `sysName`, `agent_host_tag`) into per-interface rows.

---

## 12. Plugin Reference: influxdb_v2 Output

**Source:** `plugins/outputs/influxdb_v2/`

Writes metrics to InfluxDB v2 or compatible endpoints (including VictoriaMetrics) using line protocol.

### Line protocol format

```
<measurement>,<tag1>=<val1> <field1>=<val1>i,<field2>=<val2> <timestamp_ns>
```

- Integer fields are suffixed with `i`, unsigned with `u` (if `influx_uint_support = true`).
- NaN and Inf float values are silently dropped per-field.
- Content is gzip-compressed by default.

### VictoriaMetrics compatibility

VictoriaMetrics accepts InfluxDB line protocol at `/api/v2/write`. The `organization`, `bucket`, and `token` parameters appear in the URL but are ignored by VM. Set them to placeholder values. VM stores all values as float64 internally, so `influx_uint_support` should generally be `false`.

### Error handling

- **413 (too large):** Batch is split in half and retried recursively.
- **429/502/503/504:** Exponential backoff with `Retry-After` header support (capped at 600s).
- **Multiple URLs:** Load-balanced randomly. On failure, next URL is tried.

---

## 13. Plugin Reference: tail

**Source:** `plugins/inputs/tail/`

Follows and reads lines appended to log files. Supports glob patterns for file discovery.

### Configuration

```toml
[[inputs.tail]]
  ## Glob patterns for files to tail
  files = ["/var/log/myapp/*.log"]

  ## Start position for new files (no persisted offset)
  ## "beginning", "end", "saved-or-beginning", "saved-or-end" (default)
  from_beginning = false

  ## Watch method: "inotify" (Linux/BSD) or "poll" (250ms intervals)
  # watch_method = "inotify"

  ## Data format: "value" treats each line as a single string field
  data_format = "value"
  data_type = "string"

  ## Named pipe mode (for reading from FIFOs)
  # pipe = true

  ## ANSI color stripping
  # filters = ["ansi_color"]
```

### File discovery and rotation

The plugin re-evaluates glob patterns on each gather cycle to discover new files. When a file is rotated (moved/replaced), `ReOpen: true` detects the replacement and starts reading the new file. Compressed files (`*.gz`) and temp files (`*.tmp`) are excluded by default.

### Kubernetes container log limitations

The tail plugin is **not designed for Kubernetes container log collection**:

- **Symlink chains:** Container logs at `/var/log/containers/` are symlinks to `/var/log/pods/` which contain the actual log files. The tail plugin uses `os.Lstat()` (does not follow symlinks) for initial file matching. Both directories must be mounted as separate hostPath volumes for symlinks to resolve inside the container.
- **SELinux:** On SELinux-enforcing systems (e.g., Rocky Linux 9), container log files are labeled `var_log_t:s0` with `640` permissions. Even containers running as root get "permission denied" because the container process lacks a context that grants read access to `var_log_t` files. The `telegraf-ds` chart provides no mechanism to set `seLinuxOptions`.
- **CRI log format:** Container runtime (containerd/CRI-O) prepends each line with a CRI header: `<timestamp> <stream> <flags> <message>`. A processor (e.g., starlark) is needed to strip this prefix.
- **No metadata enrichment:** Unlike dedicated Kubernetes log collectors (Vector `kubernetes_logs`, Fluent Bit `tail` with Kubernetes filter), the tail plugin does not automatically attach pod name, namespace, container name, or labels to log entries.

For Kubernetes container log collection, use a purpose-built tool like Vector's `kubernetes_logs` source, which handles symlink resolution, log rotation, CRI format parsing, SELinux contexts, and metadata enrichment natively.

---

## 14. Plugin Reference: elasticsearch Output

**Source:** `plugins/outputs/elasticsearch/`

Writes metrics/logs to Elasticsearch-compatible endpoints using the bulk API.

### Configuration

```toml
[[outputs.elasticsearch]]
  urls = ["http://localhost:9200"]
  index_name = "telegraf-%Y.%m.%d"

  ## Disable cluster health checks and sniffing for non-Elasticsearch targets
  enable_sniffer = false
  health_check_interval = "0s"
  manage_template = false

  ## Custom HTTP headers (used by VictoriaLogs for field mapping)
  [outputs.elasticsearch.headers]
    VL-Msg-Field = "tail.value"
    VL-Time-Field = "@timestamp"
    VL-Stream-Fields = "tag.log_source,tag.log_type"
```

### VictoriaLogs compatibility

VictoriaLogs accepts data via its `/insert/elasticsearch/_bulk` endpoint, which is compatible with the Elasticsearch bulk API. Use `VL-*` HTTP headers to control field mapping:

| Header | Purpose | Example |
|--------|---------|---------|
| `VL-Msg-Field` | Field(s) containing the log message | `message,msg,_msg` |
| `VL-Time-Field` | Field containing the timestamp | `@timestamp` |
| `VL-Stream-Fields` | Fields used to group logs into streams | `host,log_source,log_type` |
| `AccountID` | Multi-tenancy account (use `"0"` for single-tenant) | `0` |
| `ProjectID` | Multi-tenancy project (use `"0"` for single-tenant) | `0` |

Header values are comma-separated strings. Telegraf v1.32+ emits deprecation warnings about the string format, suggesting JSON array syntax. Both formats work; the warnings are cosmetic.

Required settings for VictoriaLogs compatibility:
- `enable_sniffer = false` -- VictoriaLogs does not support Elasticsearch cluster sniffing.
- `health_check_interval = "0s"` -- Disables Elasticsearch-specific health checks.
- `manage_template = false` -- VictoriaLogs does not use index templates.

---

## 15. Helm Charts

Two charts from `influxdata/helm-charts`:

| Chart | Kind | Use case |
|-------|------|----------|
| `influxdata/telegraf` | Deployment | Centralized collection (e.g., SNMP polling) |
| `influxdata/telegraf-ds` | DaemonSet | Per-node system metrics |

### YAML-to-TOML rendering

The charts render `values.yaml` into a TOML ConfigMap. The YAML structure mirrors TOML:

```yaml
config:
  agent:
    interval: "10s"       # -> interval = "10s"
  inputs:
    - cpu:                # -> [[inputs.cpu]]
        percpu: true      #      percpu = true
```

Arbitrary per-plugin keys (like `fieldinclude`, `log_level`, `devices`) pass through to TOML as long as the YAML types are correct. Use `override_config.toml` to bypass rendering and inject raw TOML.

### telegraf-ds chart limitations

The DaemonSet chart has several hardcoded elements that cannot be overridden via values:

- **`hostfsro` volume:** Always mounts host `/` at `/hostfs` read-only. Cannot be changed to mount fewer directories.
- **No `command` override:** Only `args` is exposed. The entrypoint drops privileges to the `telegraf` user before running args, so pre-startup setup requiring root is not possible.
- **No `initContainers`:** Not supported in the chart template.
- **No container-level `securityContext`:** Only pod-level `podSecurityContext` is exposed.
- **`HOST_*` env vars:** Hardcoded in the default values. Can be overridden via the `env` values key.

Custom volumes and mounts are supported via `volumes` and `mountPoints` values.

### telegraf-ds is not suitable for Kubernetes log collection

The telegraf-ds chart is designed for host-level metrics collection, not container log tailing. Key blockers:

- **RBAC collision:** The chart creates a cluster-scoped `ClusterRole` named `influx-stats-viewer`. A second instance of the chart (e.g., for logs) fails with an ownership metadata conflict because Helm tracks cluster-scoped resources per release.
- **No SELinux support:** The chart exposes `podSecurityContext` but not container-level `securityContext` or `seLinuxOptions`. On SELinux-enforcing hosts, the tail plugin cannot read container log files (see [tail plugin limitations](#kubernetes-container-log-limitations)).
- **No log-specific docs or examples:** The chart has zero documentation or configuration examples for log collection use cases.

For Kubernetes container log collection, use a purpose-built agent like [Vector](https://vector.dev/) (with its `kubernetes_logs` source) deployed via its own Helm chart or as a bundled dependency of the VictoriaLogs chart.

---

## 16. Documentation Links

- [Telegraf Configuration](https://docs.influxdata.com/telegraf/v1/configuration/) -- agent settings, plugin config
- [Input Plugin List](https://docs.influxdata.com/telegraf/v1/plugins/#input-plugins) -- all available inputs
- [Output Plugin List](https://docs.influxdata.com/telegraf/v1/plugins/#output-plugins) -- all available outputs
- [Metric Filtering](https://docs.influxdata.com/telegraf/v1/configuration/#metric-filtering) -- fieldinclude, namepass, tagpass, etc.
- [InfluxDB Line Protocol](https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/) -- wire format reference
- [gopsutil](https://github.com/shirou/gopsutil) -- Go library for system metrics, handles HOST_* env vars
- [Kubernetes Memory Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) -- cgroup limits, OOM behavior
- [Telegraf Helm Charts](https://github.com/influxdata/helm-charts) -- telegraf and telegraf-ds chart source
