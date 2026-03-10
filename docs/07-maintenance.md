---
name: maintenance
description: >
  Load this document when upgrading Kubernetes components (Helm charts, container images),
  planning or executing upgrades, recovering from cluster failures, rotating certificates,
  or performing routine maintenance tasks.
categories: [kubernetes, operations]
tags: [upgrades, certificates, recovery, troubleshooting, maintenance, helm]
related_docs:
  - docs/02-rpis-and-k3s.md
  - docs/01-infrastructure-provisioning.md
  - docs/04-networking.md
complexity: intermediate
---

# Maintenance

## Upgrading Kubernetes Components

Components deploy via Helm (helmfile) or plain kubectl. The upgrade method depends on whether breaking changes involve immutable Kubernetes fields. Scale planning to the component's blast radius -- system infrastructure (`kube/sys/`) warrants thorough analysis and a written plan; application upgrades (media services, user apps) can skip to execution with lighter verification.

### Planning an Upgrade

Before writing any code, research the upgrade path: what changed, what breaks, and whether in-place upgrade works or uninstall+reinstall is required. For low-risk application upgrades, a quick changelog scan may suffice.

**1. Determine the version gap and read changelogs.**

Check the deployed version (`helm list -n <namespace>` for Helm, or the running image tag for kubectl-managed apps). Compare with the latest stable release. Read changelogs for every minor version in the gap -- breaking changes accumulate.

**2. Identify immutable field changes.**

Kubernetes prohibits modifying certain fields after creation (e.g., `matchLabels` on Deployments, `spec.attachRequired` on CSIDriver objects). If any chart version in the upgrade path changed an immutable field's default, in-place `helmfile apply` fails. This determines the upgrade method:

- **No immutable changes**: In-place upgrade via `helmfile apply` or `kubectl apply`. Simpler, lower risk, supports `helm rollback`.
- **Immutable changes**: Must uninstall first, then reinstall. Order matters -- delete the old release, delete immutable objects (CSIDriver, etc.), apply file changes, then deploy. Expect brief service disruption.

**3. Check values schema changes.**

Helm charts rename, restructure, or change defaults for values between versions. Upstream charts publish a `values.yaml` with defaults -- diff the old and new versions to catch:
- Renamed keys (e.g., `external-snapshotter` to `externalSnapshotter`)
- Flipped defaults (e.g., `attachRequired: false` becoming `true`)
- Deprecated values (e.g., `installCRDs` replaced by `crds.enabled`)
- New features enabled by default that add unnecessary resource overhead (e.g., FRR sidecars, external attacher containers)

For kubectl-managed apps (e.g., CoreDNS), steps 2-3 are simpler: check for RBAC or config syntax changes, update the image tag, and `kubectl apply`.

**4. Assess data safety and blast radius.**

Understand what survives an uninstall. Key Kubernetes behaviors:
- Helm never deletes CRDs on uninstall (`helmfile destroy` preserves CRDs and their instances)
- PVs and PVCs are independent of the controllers that provisioned them
- Namespaces persist through uninstall/reinstall
- Services lose their LoadBalancer IPs during uninstall (MetalLB reassigns them on reinstall)

For components with multiple instances (e.g., internal + external ingress controllers), upgrade the lower-risk instance first, verify, then proceed.

**5. Document the plan.**

Write upgrade plans to `docs/plans/` (gitignored, ephemeral). Use a consistent structure:
- **Context**: Current version, target version, deployment method, current health
- **Breaking Changes**: Table with version, change, impact assessment, and mitigation
- **File Changes**: Exact edits needed, with before/after snippets
- **Upgrade Procedure**: Pre-flight checks, execution steps, post-upgrade verification, rollback steps
- **Observations**: Anything learned that might help future upgrades

### Upgrade Procedure Structure

Every upgrade follows the same phases:

**Pre-flight (read-only):** Verify the component is healthy before touching it. Record current state for rollback comparison -- pod status, image versions, helm chart versions, service IPs.

**Execute:** Apply file changes and deploy. For uninstall+reinstall upgrades, order matters: destroy old release, delete immutable objects, apply file edits, deploy new version. Never deploy with stale values files -- old values against a new chart silently produce wrong configuration.

**Post-upgrade verification:** Confirm pods are running, images are correct, and services have their IPs. Verify the component works, not just runs. Test end-to-end:
- DNS components: resolve internal and external names
- Ingress controllers: hit actual endpoints through the ingress
- Storage drivers: create and mount a test PVC
- Certificate managers: dry-run a Certificate creation through the webhook

**Rollback:** Document a rollback path before execution. For in-place Helm upgrades, `helm rollback <release> 0` reverts to the previous revision. For uninstall+reinstall upgrades: destroy the failed install, `git checkout` the file changes, redeploy with the old configuration.

### Recurring Patterns

Patterns from past upgrades:

**Pin chart versions in helmfile.yaml.** Without a version pin, `helmfile apply` silently pulls the latest chart version. Always pin: `version: x.y.z`. This makes upgrades intentional and rollbacks predictable.

**Clean up dead configuration during upgrades.** Upgrades are a natural time to remove stale values (unused annotations, references to undeployed components, deprecated value keys). Keep these cleanups in the same commit as the upgrade so the diff tells a coherent story.

**Separate risky follow-up work into its own commit.** When an upgrade enables a follow-up migration (e.g., migrating `spec.loadBalancerIP` to `metallb.io/loadBalancerIPs` annotations after a MetalLB chart swap), upgrade first, verify, then migrate in a separate commit. This keeps each change's blast radius small and rollback boundaries clean.

**Pre-pull images before uninstall+reinstall upgrades.** The downtime window shrinks when nodes already have the new images cached. During pre-flight, `ssh <node> "sudo crictl pull <image>:<tag>"` on each node. This avoids image pull delays when the new pods schedule after reinstall.

**Verify ARM64 image availability.** This cluster runs on Raspberry Pi (ARM64). Confirm the target version publishes `linux/arm64` images -- check the image registry or release notes. An image that supported ARM64 in the past may drop it in a future release.

**Chart swaps (e.g., Bitnami to upstream) always require uninstall+reinstall.** Different chart maintainers use different label selectors, values schemas, and resource naming. Treat a chart swap the same as an immutable field change.

## Historical Reference

Legacy troubleshooting notes. These sections will be replaced as automation improves.

## k3s Upgrades

1. Pick a new version from https://github.com/k3s-io/k3s/releases (probably look for "Latest")
2. Update the k3s version in `ansible/inventory/group_vars/all.yaml`:
```
k3s_version: v1.27.2+k3s1
```
3. Run `ansible-playbook k3-install.yml`.

### Agent Error Rejoining Cluster

https://github.com/k3s-io/k3s/issues/802#issuecomment-841748960

```
Jun 02 20:15:03 k3-n1 k3s[2335]: time="2024-06-02T20:15:03-04:00" level=info msg="Waiting to retrieve agent configuration; server is not ready: Node password rejected, duplicate hostname or contents of '/etc/rancher/node/password' may not match server passwd entry
```

Solution: from the master node (or any connected kubectl) run `kubectl -n kube-system delete secret <agent-node-name>.node-password.k3s`

In my case it was:
```
kubectl -n kube-system delete secrets k3-n1.node-password.k3s
```

## Server OS Upgrade

DONT DO IT. Its not worth the pain. Start with a fresh install instead.

## Rotating k3s Certs

https://docs.k3s.io/cli/certificate#rotating-self-signed-ca-certificates

```
wget https://raw.githubusercontent.com/k3s-io/k3s/master/contrib/util/rotate-default-ca-certs.sh
sudo bash rotate-default-ca-certs.sh
sudo k3s certificate rotate-ca --path=/var/lib/rancher/k3s/server/rotate-ca
sudo systemctl restart k3s
```

### Cert Weirdness Recreating Master Node

```
Dec 28 11:43:36 k3-m1 k3s[9577]: time="2023-12-28T11:43:36-05:00" level=fatal msg="/var/lib/rancher/k3s/server/tls/etcd/peer-ca.crt, /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt, /var/lib/rancher/k3s/server/cred/ipsec.psk, /var/lib/rancher/k3s/server/tls/request-header-ca.crt, /var/lib/rancher/k3s/server/tls/server-ca.crt, /var/lib/rancher/k3s/server/tls/client-ca.crt, /var/lib/rancher/k3s/server/tls/client-ca.key, /var/lib/rancher/k3s/server/tls/etcd/peer-ca.key, /var/lib/rancher/k3s/server/tls/etcd/server-ca.key, /var/lib/rancher/k3s/server/tls/request-header-ca.key, /var/lib/rancher/k3s/server/tls/server-ca.key, /var/lib/rancher/k3s/server/tls/service.key newer than datastore and could cause a cluster outage. Remove the file(s) from disk and restart to be recreated from datastore."
```

```
> sudo rm /var/lib/rancher/k3s/server/tls/etcd/peer-ca.crt /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt /var/lib/rancher/k3s/server/cred/ipsec.psk /var/lib/rancher/k3s/server/tls/request-header-ca.crt /var/lib/rancher/k3s/server/tls/server-ca.crt /var/lib/rancher/k3s/server/tls/client-ca.crt /var/lib/rancher/k3s/server/tls/client-ca.key /var/lib/rancher/k3s/server/tls/etcd/peer-ca.key /var/lib/rancher/k3s/server/tls/etcd/server-ca.key /var/lib/rancher/k3s/server/tls/request-header-ca.key /var/lib/rancher/k3s/server/tls/server-ca.key /var/lib/rancher/k3s/server/tls/service.key
> sudo systemctl restart k3s
```
