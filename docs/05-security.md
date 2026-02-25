---
name: security
description: >
  Load this document when implementing authentication, access control, authorization
  proxies, or security policy for the homelab.
categories: [kubernetes, security]
tags: [authentication, authorization, oauth-proxy, sso, access-control]
related_docs:
  - docs/04-networking.md
  - docs/01-infrastructure-provisioning.md
complexity: intermediate
---

# Security

This document covers authentication, access control, and security hardening across the homelab infrastructure.

## Threat Model

Security decisions are informed by the threat model:

- **Environment**: Small home lab serving a few specific people, not a shared platform
- **Data sensitivity**: Low. Non-personal media files, isolated service credentials
- **Primary concern**: Publicly accessible services (Jellyfin, Arr apps exposed via DNS/Cloudflare)
- **Attack type**: Deterring automated, low-effort attacks (script kiddies, mass scanning). Not defending against:
  - Targeted, sophisticated attacks
  - Compliance requirements (GDPR, PCI-DSS, etc.)
  - Nation-state adversaries
- **Acceptable risk**: If someone is determined enough, they'll get in. Security is about raising the bar to "not worth the effort."

Given this threat model, the security approach is layered: infrastructure-level hardening via Ansible, network-level filtering via the MikroTik router, and application-level authentication. Running applications in Kubernetes containers provides isolation boundaries between services—if one application is compromised, it doesn't automatically grant access to others or the host.

## Infrastructure Hardening

Security hardening is automated via Ansible and covers SSH access, service hardening, and automatic updates across hosts and the router.

**Raspberry Pi hosts**: SSH key-only authentication, automatic OS updates, firewall disabled (relying on network isolation). See `ansible/roles/sys/tasks/main.yml` and [Infrastructure Provisioning](01-infrastructure-provisioning.md) for details.

**MikroTik router**: Insecure services disabled, SSH/Winbox/HTTP restricted to LAN, strong crypto enabled, automatic firmware updates. See `ansible/mikrotik-configure.yml` and [Infrastructure Provisioning](01-infrastructure-provisioning.md) for details.

### Network Filtering

The MikroTik router implements firewall rules that:

- **Allow external traffic only from Cloudflare IPs**: Incoming HTTPS from the internet is restricted to Cloudflare proxy IPs, then DNAT'd to the ingress controller
- **Isolate cluster subnets**: Internal MetalLB service IPs (192.168.1.220-239) are restricted from external access via firewall rules (see `ansible/files/cloudflare-firewall.rsc`)

See [Networking](04-networking.md) for traffic flow and external access setup.

## Application Authentication

The homelab currently uses **per-application authentication** rather than a centralized authentication proxy. Each service handles its own auth (if required):

- **Jellyfin** (media server): Native user accounts and API tokens
- **Arr suite** (media management): Individual API keys and auth plugins
- **Kubernetes API**: Standard kubeconfig + certificate auth for kubectl access
- **Router access**: SSH key auth only (no password login)

### Centralized SSO Experiments

Two centralized authentication approaches were evaluated but not deployed:

1. **OAuth2-proxy** (lightweight ingress-based SSO): Tested as a middleware to provide centralized OAuth2/OIDC authentication. While functional for standard web applications, it introduced compatibility issues:
   - Not all services supported running behind an authentication proxy
   - Some clients (mobile apps, API consumers) couldn't use OAuth2-proxy flows
   - Operational overhead for managing a separate auth proxy
   - Better suited for unified SaaS platforms; overkill for diverse homelab services

2. **Teleport** (SSH bastion + SSO): Considered as a comprehensive access control layer but deferred due to:
   - Additional operational complexity
   - Better suited for larger teams than single-user homelab
   - Current SSH key management is sufficient for secure access

Both remain available if access control requirements change. For now, application-level authentication is simpler and aligns with the principle of keeping the homelab maintainable.

## Vulnerability Management

**Container image scanning (Trivy)**: Automated vulnerability scanning of container images was explored (`kube/observation/trivy/`) but abandoned due to lack of external communication or CI to automate remediation. Currently, container images are manually reviewed and updated periodically.

**Image update tracking (DIUN)**: A service to track available image updates was also tested but abandoned for the same reason — without automation to deploy updates, tracking becomes a manual workflow that could be handled by periodic manual checks.
