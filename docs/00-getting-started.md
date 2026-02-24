# Getting Started

## Overview

This project is a homelab built on a k3s Kubernetes cluster running on Raspberry Pi 4B nodes, backed by a Synology NAS for persistent storage. The goals are:

- Learn Kubernetes by building and operating a real cluster
- Self-host services (media server, NAS access, personal applications)
- Secure external access to targeted LAN resources via DNS
- Keep recurring costs low (power, domain registration -- no cloud compute bills)

## Hardware

| Product | Qty | Description |
| ------- | --- | ----------- |
| [Synology DS720+](https://www.synology.com/en-us/products/DS720+) | 1 | 2-disk NAS, expandable to 7 disks with the [DX517](https://www.synology.com/en-us/products/DX517) |
| [Seagate IronWolf 8TB NAS HDD](https://www.seagate.com/products/nas-drives/ironwolf-hard-drive/) | 2 | NAS-rated drives |
| [MikroTik RB5009UPr+S+IN](https://mikrotik.com/product/rb5009ups) | 1 | Router/managed switch with PoE on all ports |
| [TP-Link EAP723 Wireless AP](https://www.tp-link.com/us/business/wireless/eap723/) | 1 | Standalone WiFi 6 access point |
| [Raspberry Pi 4B (4GB RAM)](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/) | 1 | Cluster node |
| [Raspberry Pi 4B (8GB RAM)](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/) | 1 | Cluster node |
| [Raspberry Pi PoE+ HAT](https://www.raspberrypi.com/products/poe-plus-hat/) | 2 | Required to safely deliver PoE power to the Pis |
| [UCTRONICS 4-Bay Raspberry Pi Cluster Enclosure](https://www.amazon.com/gp/product/B09JNHKL2N/) | 1 | Rack enclosure for the Pis |
| [UCTRONICS Fan Adapter Board](https://www.amazon.com/dp/B09TP9HT3C) | 1 | Adapter to power enclosure fans when PoE HAT blocks the GPIO pins |
| Micro Center 32GB Micro SD Card (5 pack) | 1 | Primary storage for the Pis |
| Cat 6 Ethernet Cable 1 ft (10 pack) | 1 | PoE-compliant patch cables |

### Compute -- Raspberry Pi 4B

Raspberry Pis are small, inexpensive, complete ARM-based computers. Their low cost and low power draw make them practical nodes for a home Kubernetes cluster. The cluster runs two nodes: a 4GB control-plane and an 8GB worker.

### Network -- Router and Wireless

The MikroTik RB5009UPr+S+IN is a managed router/switch with integrated PoE on all ports, powering both the Raspberry Pis and the wireless AP via Ethernet. It supports advanced routing, firewall rules, DHCP, DNS, and auto-updates. Configuration is automated via Ansible (`ansible/mikrotik-bootstrap.yml` and `ansible/mikrotik-configure.yml`).

The TP-Link EAP723 is a standalone WiFi 6 access point providing wireless coverage. It manages itself independently through a web UI and bridges seamlessly into the network via DHCP.

### Storage -- Synology NAS

The Synology DS720+ provides reliable, expandable network storage using [Synology Hybrid RAID (SHR)](https://kb.synology.com/en-uk/DSM/tutorial/What_is_Synology_Hybrid_RAID_SHR), which is more flexible than standard RAID when mixing drive sizes. It serves NFS shares consumed by the Kubernetes cluster for both application config and media files.

## Software Stack

| Component | Technology | Purpose |
| --------- | ---------- | ------- |
| OS | Rocky Linux 9 (ARM) | Runs on each Raspberry Pi |
| Provisioning | Ansible | Bootstraps MikroTik, Pis, and installs k3s |
| Orchestration | k3s | Lightweight Kubernetes distribution |
| Storage | NFS (Synology) + democratic-csi | Static NFS mounts for most apps; democratic-csi for dynamic provisioning |
| Load Balancer | MetalLB (L2 mode) | Assigns IPs from a local pool (192.168.1.220-239) |
| Ingress | ingress-nginx (x2) | Dual controllers: `nginx-internal` (LAN) and `nginx-external` (internet-facing) |
| TLS | cert-manager | LetsEncrypt certificates via Cloudflare DNS-01 challenge |
| Auth | oauth2-proxy | GitHub-backed authentication for protected services |
| Observability | fluent-bit, Loki, kube-prometheus-stack | Log aggregation and metrics with Grafana dashboards |
| Deployment | Make + kubectl / Helmfile | Makefile-driven deploys (not GitOps); Helmfile for complex upstream charts |

## Repository Layout

- **`ansible/`** -- Playbooks and roles for MikroTik router provisioning, Raspberry Pi OS setup, and k3s installation.
- **`kube/`** -- All Kubernetes manifests, Helm values, and Makefile-driven deployment tooling. Apps are grouped by category (`sys/`, `app/`, `media/`, `observation/`).
- **`docs/`** -- Operational documentation covering setup, networking, security, observability, and maintenance.
- **`.envrc`** -- Secrets and environment variables (gitignored), loaded via [direnv](https://direnv.net/).
