# Homelab

A k3s Kubernetes cluster running on Raspberry Pi 4B nodes (Rocky Linux 9, ARM), backed by a Synology DS720+ NAS for persistent storage. Deployment is Makefile-driven using kubectl and Helmfile. See [Getting Started](docs/00-getting-started.md) for the full project overview, hardware details, and software stack.

## Quick Start

All Kubernetes commands run from the `kube/` directory. The `KUBECONFIG` env var is set via `.envrc` ([direnv](https://direnv.net/)).

```bash
# Deploy an app
make jellyfin-deploy

# Check status / tail logs
make jellyfin-status
make jellyfin-logs

# Stop / start / restart
make jellyfin-stop
make jellyfin-start
make jellyfin-restart

# Deploy by category
make deploy-sys       # System infrastructure
make deploy-apps      # User applications
make deploy-all       # Everything
```

## Documentation

1. [Getting Started](docs/00-getting-started.md) -- Project overview, hardware, software stack, and repo layout.
2. [RPis and k3s](docs/01-rpis-and-k3s.md) -- Cluster topology, k3s configuration, and Ansible provisioning.
3. [Persistence](docs/02-persistence.md) -- Synology NAS setup and Kubernetes storage configuration.
4. [Networking](docs/03-networking.md) -- Network topology, DNS, MetalLB, ingress controllers, TLS, and authentication.
5. [Security](docs/04-security.md) -- Authentication and access control.
6. [Observability](docs/05-observability.md) -- Logging and monitoring stack.
7. [Maintenance](docs/06-maintenance.md) -- k3s upgrades and cluster maintenance procedures.
8. [Saving Your SD Cards](docs/07-saving-your-sdcards.md) -- Reducing SD card wear on Raspberry Pi nodes.

## Repository Layout

- **`ansible/`** -- Pi provisioning and k3s installation playbooks
- **`kube/`** -- Kubernetes manifests, Helm values, and Makefile-driven deployment tooling
- **`docs/`** -- Operational documentation

See [Getting Started](docs/00-getting-started.md) for details.
