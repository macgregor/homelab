---
name: observability
description: >
  Load this document when working with logging, monitoring, or observability
  infrastructure.
categories: [kubernetes, observability]
tags: [logging, monitoring, metrics, grafana, victoriametrics, telegraf, snmp, kube-state-metrics, dashboards]
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
    │                     │◄────┤                   │
    │  also scrapes:      │     └──────────────────┘
    │  kube-state-metrics │       collects: cpu, mem, disk,
    └──────────┬──────────┘       diskio, net, system,
               │                  processes, kubernetes
    ┌──────────▼──────────┐
    │  Grafana            │  ┌──────────────────────┐
    │  grafana            │  │  kube-state-metrics   │
    │  (Dashboards)       │  │  (k8s object state)   │
    └─────────────────────┘  └──────────────────────┘
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

### kube-state-metrics (`kube/observation/kube-state-metrics/`)

Exposes Kubernetes object state as Prometheus metrics: pod phase, restart counts, resource requests/limits, deployment status, node conditions. Scraped by VictoriaMetrics on a 30-second interval.

- **Port:** 8080 (Prometheus scrape target)
- **In-cluster URL:** `http://kube-state-metrics.obs.svc:8080`

### Grafana (`kube/observation/grafana/`)

Dashboards and visualization. Auto-provisioned with VictoriaMetrics as a Prometheus-type datasource.

- **UI:** `https://grafana.matthew-stratton.me` (internal ingress)
- **Admin password:** `GRAFANA_ADMIN_PASS` env var
- **Storage:** 1Gi on `synology-nfs-app-data-retain`
- **Dashboards:** Provisioned from ConfigMap (`grafana-dashboards`), source JSON in `kube/observation/grafana/dashboards/`

Two dashboards are provisioned in the "Homelab" folder:

- **Homelab Overview** -- Infrastructure health: uptime, CPU, memory, storage, temperature, network traffic, and device health status across router, NAS, and cluster nodes.
- **Kubernetes** -- Workload state: node readiness, pod phases, container restarts, resource requests vs limits, and deployment availability. Uses kube-state-metrics data with a namespace filter variable.

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
just kube-state-metrics-deploy
just grafana-deploy

# Check status
just victoriametrics-status
just telegraf-status
just telegraf-snmp-status
just kube-state-metrics-status
just grafana-status
```

## Verifying Metrics

Query VictoriaMetrics directly or through Grafana:

- **Node metrics:** `cpu_usage_idle`, `mem_used_percent`, `disk_used_percent`
- **Kubernetes metrics (Telegraf):** `kubernetes_pod_container_resource_requests_cpu_cores`
- **Kubernetes metrics (kube-state-metrics):** `kube_node_info`, `kube_pod_status_phase`, `kube_deployment_spec_replicas`
- **MikroTik SNMP:** `snmp_mikrotik_cpu_load`, `snmp_mikrotik_interface_bytes_recv`
- **Synology SNMP:** `snmp_synology_system_temperature`, `snmp_synology_disk_disk_temperature`

## Previous Experiments

Elasticsearch+Kibana and Fluentd/Fluent-bit+Loki+Grafana were evaluated as centralized logging solutions but required too many resources on Raspberry Pi nodes. Old configs are archived in `kube/graveyard/`.

## Related Documentation

- [Getting Started](00-getting-started.md) -- Hardware specs and resource constraints
- [Persistence](03-persistence.md) -- NFS storage classes used by VictoriaMetrics and Grafana
- [Networking](04-networking.md) -- Internal ingress and DNS configuration
- [Infrastructure Provisioning](01-infrastructure-provisioning.md) -- Ansible playbooks including MikroTik SNMP setup
