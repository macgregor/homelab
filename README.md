# Homelab

A k3s Kubernetes cluster running on Raspberry Pi 4B nodes (Rocky Linux 9, ARM), backed by a Synology DS720+ NAS for persistent storage. Deployment is driven by [just](https://github.com/casey/just) using kubectl and Helmfile. See [Getting Started](docs/00-getting-started.md) for the full project overview, hardware details, and software stack.

## Quick Start

All Kubernetes commands run from the `kube/` directory. The `KUBECONFIG` env var is set via `.envrc` ([direnv](https://direnv.net/)).

```bash
# Deploy an app
just jellyfin-deploy

# Check status / tail logs
just jellyfin-status
just jellyfin-logs

# Stop / start / restart
just jellyfin-stop
just jellyfin-start
just jellyfin-restart

# Deploy by category
just deploy-sys       # System infrastructure
just deploy-apps      # User applications
just deploy-all       # Everything
```

## Documentation

1. [Getting Started](docs/00-getting-started.md) -- Project overview, hardware, software stack, and repo layout.
2. [Infrastructure Provisioning](docs/01-infrastructure-provisioning.md) -- Ansible provisioning of MikroTik router and Raspberry Pis.
3. [RPis and k3s](docs/02-rpis-and-k3s.md) -- Kubernetes cluster topology and k3s configuration.
4. [Persistence](docs/03-persistence.md) -- Synology NAS setup and Kubernetes storage configuration.
5. [Networking](docs/04-networking.md) -- Network topology, DNS, MetalLB, ingress controllers, TLS, and authentication.
6. [Security](docs/05-security.md) -- Authentication and access control.
7. [Observability](docs/06-observability.md) -- Logging and monitoring stack.
8. [Maintenance](docs/07-maintenance.md) -- k3s upgrades and cluster maintenance procedures.

## Repository Layout

- **`ansible/`** -- Provisioning playbooks for MikroTik router, Raspberry Pi OS, and k3s installation
- **`kube/`** -- Kubernetes manifests, Helm values, and just-driven deployment tooling
- **`docs/`** -- Operational documentation

See [Getting Started](docs/00-getting-started.md) for details.
