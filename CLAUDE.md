# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A homelab infrastructure repository managing a k3s Kubernetes cluster on Raspberry Pi 4B nodes (Rocky Linux 9 ARM) with a Synology DS720+ NAS for persistent storage. Deployment is Makefile-driven (not GitOps).

## Key Commands

All Kubernetes commands run from `kube/` directory. The `KUBECONFIG` env var is set via `.envrc` (direnv).

### Deploying Applications

```bash
# Deploy a single app (from kube/ directory)
make jellyfin-deploy

# Other per-app targets: remove, stop, start, restart, status, debug, logs
make jellyfin-status
make jellyfin-logs
make jellyfin-stop
make jellyfin-start

# Deploy by category
make deploy-sys      # System infrastructure
make deploy-apps     # User applications
make deploy-demos    # Test/demo apps
make deploy-all      # Everything
```

### Ansible (from ansible/ directory)

```bash
ansible-playbook rpi-bootstrap.yml    # Initial Pi setup
ansible-playbook k3-install.yml       # Install k3s
```

### Debugging

```bash
make pod-debug pod=<pod-name> n=<namespace>   # Shell into a pod
make cluster-debug node=k3-m1                 # Shell into network-multitool on a node
```

## Architecture

### Directory Layout

- `ansible/` - Playbooks and roles for Pi provisioning and k3s installation
- `kube/` - All Kubernetes manifests and deployment tooling
- `docs/` - Operational documentation (setup, networking, maintenance)
- `.envrc` - Secrets and env vars (gitignored, loaded via direnv)

### Kubernetes Organization (`kube/`)

Apps are grouped by category: `sys/`, `app/`, `media/`, `observation/`, `demo/`, `graveyard/` (deprecated).

Each application follows a standard structure:
```
app-name/
├── app-name.mk       # Makefile targets (deploy, remove, stop, start, etc.)
├── namespace.yml      # Namespace
├── storage.yml        # PV/PVC definitions
├── app-name.yml       # Deployment/StatefulSet
├── network.yml        # Service/Ingress
├── helmfile.yaml      # If Helm-managed (optional)
└── helm-values.yml    # Helm values, may use .gotmpl for env var injection
```

`kube/templates/kube-objects.yml` contains shared YAML anchors (control-plane tolerations, node affinity, common labels).

### Deployment Methods

Three patterns exist depending on the component:

1. **Plain kubectl** - Most apps. `kubectl apply -f` on YAML files directly.
2. **Helmfile** - Complex upstream charts (cert-manager, ingress-nginx, prometheus). Uses `helmfile apply` with `helm-values.yml`.
3. **envsubst** - For injecting env vars into plain YAML before `kubectl apply` (used by cert-manager cluster issuers).

`.gotmpl` files use Go template syntax (`{{ requiredEnv "VAR_NAME" | quote }}`) for Helmfile value injection.

### Secrets Management

All secrets live in `.envrc` (gitignored), loaded by direnv. They flow into deployments via:
- `envsubst` for plain YAML
- `.gotmpl` templates for Helmfile values
- `kubectl create secret --dry-run=client -o yaml | kubectl apply -f -` in Makefile targets
- `{{ lookup('env', 'VAR_NAME') }}` in Ansible

### Storage Patterns

- **Config/persistent data**: Static PV/PVC on Synology NFS at `/volume2/kube-nfs/v/<app>-config`
- **Volatile/cache**: `local-path` StorageClass (node-local)
- **Media files**: Direct NFS volume mounts (not PV/PVC)
- **Dynamic provisioning**: `democratic-csi` NFS driver for Synology

### Networking

- **MetalLB**: L2 mode load balancer, IP pool 192.168.1.220-239
- **Two ingress controllers**: `nginx-internal` (LAN only) and `nginx-external` (internet-facing)
- **TLS**: cert-manager with LetsEncrypt via Cloudflare DNS-01 challenge
- **Auth**: oauth2-proxy with GitHub provider for protected services

## Conventions

- Makefile targets follow `<app>-<action>` naming (e.g., `jellyfin-deploy`, `metallb-status`)
- Each `.mk` file is included by the top-level `kube/Makefile`
- Labels use `app.kubernetes.io/name` consistently
- Replicas are controlled via `<APP>_REPLICAS` env vars with `?=1` defaults
- `remove` targets prefix commands with `-` to ignore errors during teardown
