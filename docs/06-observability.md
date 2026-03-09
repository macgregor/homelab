---
name: observability
description: >
  Load this document when working with logging, monitoring, or observability
  infrastructure.
categories: [kubernetes, observability]
tags: [logging, monitoring, metrics, grafana, victoriametrics, telegraf, snmp]
complexity: intermediate
---

# Observability

The homelab runs a VictoriaMetrics + Telegraf + Grafana stack for metrics collection and visualization. All components run in the `obs` namespace with control-plane node affinity and `CriticalAddonsOnly` tolerations.

## Architecture

```
┌──────────────┐    ┌──────────────┐
│  MikroTik    │    │  Synology    │
│  Router      │    │  NAS         │
│  (SNMP)      │    │  (SNMP)      │
└──────┬───────┘    └──────┬───────┘
       │                   │
       └───────┬───────────┘
               │ SNMPv2c
    ┌──────────▼──────────┐
    │  Telegraf SNMP      │  (Deployment, single pod)
    │  telegraf-snmp      │
    └──────────┬──────────┘
               │ influxdb_v2
    ┌──────────▼──────────┐     ┌──────────────────┐
    │  VictoriaMetrics    │◄────│  Telegraf DS      │ (DaemonSet, one per node)
    │  victoriametrics    │     │  telegraf         │
    │  (TSDB)             │     │  influxdb_v2      │
    └──────────┬──────────┘     └──────────────────┘
               │                  collects: cpu, mem, disk,
               │                  diskio, net, system,
    ┌──────────▼──────────┐       processes, kubernetes
    │  Grafana            │
    │  grafana            │
    │  (Dashboards)       │
    └─────────────────────┘
```

## Components

### VictoriaMetrics (`kube/observation/victoriametrics/`)

Single-node time-series database. Accepts metrics via InfluxDB line protocol on port 8428. Deployed as a StatefulSet with persistent storage.

- **Retention:** 30 days
- **Storage:** 10Gi on `synology-nfs-app-data-retain`
- **Memory limit:** 200MB (`-memory.allowedBytes`)
- **UI:** `https://victoriametrics.matthew-stratton.me` (internal ingress)
- **In-cluster URL:** `http://victoriametrics-server.obs.svc:8428`

### Telegraf DaemonSet (`kube/observation/telegraf/`)

Collects node-level system metrics and Kubernetes pod/container metrics from the kubelet API. Runs on every node including control-plane.

**Input plugins:** `cpu`, `mem`, `disk`, `diskio`, `net`, `system`, `processes`, `kubernetes`

**Output:** `influxdb_v2` to VictoriaMetrics

### Telegraf SNMP (`kube/observation/telegraf-snmp/`)

Polls MikroTik router and Synology NAS via SNMPv2c from a single pod inside the cluster. Uses the `tplVersion: 2` Helm chart setting for proper nested TOML rendering.

**MikroTik metrics:** CPU load, memory usage, uptime, per-interface traffic (bytes sent/recv, operational status)

**Synology metrics:** System temperature, load averages, memory usage, per-disk health and temperature, RAID status, storage utilization

**SNMP community string:** Injected via `SNMP_COMMUNITY` env var through `.gotmpl` template

### Grafana (`kube/observation/grafana/`)

Dashboards and visualization. Auto-provisioned with VictoriaMetrics as a Prometheus-type datasource.

- **UI:** `https://grafana.matthew-stratton.me` (internal ingress)
- **Admin password:** `GRAFANA_ADMIN_PASS` env var
- **Storage:** 1Gi on `synology-nfs-app-data-retain`

## SNMP Prerequisites

Both SNMP targets must have SNMPv2c enabled before Telegraf SNMP can collect metrics:

- **MikroTik:** Enabled via Ansible (`ansible-playbook mikrotik-configure.yml`). Verify: `ssh router '/snmp print'` shows `enabled: yes`.
- **Synology:** Enabled via DSM Control Panel > Terminal & SNMP. Verify: `snmpwalk -v2c -c $SNMP_COMMUNITY 192.168.1.200 sysDescr`.

Both use the same community string from the `SNMP_COMMUNITY` env var in `.envrc`.

## Deployment

```bash
# Deploy entire observation stack (included in deploy-sys)
just victoriametrics-deploy
just telegraf-deploy
just telegraf-snmp-deploy
just grafana-deploy

# Check status
just victoriametrics-status
just telegraf-status
just telegraf-snmp-status
just grafana-status
```

## Verifying Metrics

Query VictoriaMetrics directly or through Grafana:

- **Node metrics:** `cpu_usage_idle`, `mem_used_percent`, `disk_used_percent`
- **Kubernetes metrics:** `kubernetes_pod_container_resource_requests_cpu_cores`
- **MikroTik SNMP:** `snmp_mikrotik_cpu_load`, `snmp_mikrotik_interface_bytes_recv`
- **Synology SNMP:** `snmp_synology_system_temperature`, `snmp_synology_disk_disk_temperature`

## Previous Experiments

Elasticsearch+Kibana and Fluentd/Fluent-bit+Loki+Grafana were evaluated as centralized logging solutions but required too many resources on Raspberry Pi nodes. Old configs are archived in `kube/graveyard/`.

## Related Documentation

- [Getting Started](00-getting-started.md) -- Hardware specs and resource constraints
- [Persistence](03-persistence.md) -- NFS storage classes used by VictoriaMetrics and Grafana
- [Networking](04-networking.md) -- Internal ingress and DNS configuration
- [Infrastructure Provisioning](01-infrastructure-provisioning.md) -- Ansible playbooks including MikroTik SNMP setup
