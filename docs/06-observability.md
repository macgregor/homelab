---
name: observability
description: >
  Load this document when working with logging, monitoring, or observability
  infrastructure.
categories: [kubernetes, observability]
tags: [logging, monitoring, observability]
complexity: intermediate
---

# Observability

The homelab relies on Kubernetes' built-in observability features (kubelet logs, pod events, metrics-server) rather than a centralized observability stack. A dedicated stack (ELK, Loki+Grafana) was explored but requires excessive resources on Raspberry Pi nodes.

## Centralized Logging Experiments

**Elasticsearch + Kibana**: Tested as a centralized log aggregation solution but was too resource-intensive to run alongside applications.

**Fluentd/Fluent-bit + Loki + Grafana**: Also evaluated as a lightweight alternative but still required dedicating an entire node to observability infrastructure, which is impractical for the current setup.

Both approaches are abandoned. For now, debugging relies on standard Kubernetes tools (`kubectl logs`, `kubectl describe`, pod events) and direct access to systemd journal on nodes.
