# Research Report: Configuring Backend TLS Cipher Suites in ingress-nginx

## Objective

Research how to configure the TLS cipher suites used by the ingress-nginx controller for backend/upstream HTTPS connections (i.e., the connection from the nginx proxy TO the backend server, NOT the client-facing TLS). Specifically investigate whether `proxy-ssl-ciphers` and `proxy-ssl-protocols` can be configured without requiring `proxy-ssl-secret` (mTLS client cert), and identify ConfigMap-level settings and alternative approaches.

## Executive Summary

Configuring backend TLS cipher suites in ingress-nginx involves a fundamental architectural limitation: the `proxy_ssl_ciphers` and `proxy_ssl_protocols` directives in the generated nginx.conf are **gated behind the `ProxySSL.CAFileName` condition** in the nginx template. This means they are only emitted when a CA certificate is present, which historically required setting `proxy-ssl-secret`. There is no dedicated ConfigMap-level setting (like `proxy-ssl-ciphers` config key) for backend proxy TLS ciphers at the global scope; the `ssl-ciphers` ConfigMap setting controls client-facing TLS only.

However, ingress-nginx v1.11.0+ (via PR #11490, targeting main/release-1.10) removes the hard dependency on `proxy-ssl-secret` being present, allowing `proxy-ssl-protocols` and other proxy-ssl annotations to work independently without a client certificate. For immediate use with v1.15.1, the practical workaround is the `configuration-snippet` annotation, which allows raw nginx directives like `proxy_ssl_ciphers` and `proxy_ssl_protocols` to be injected directly into the location block, bypassing the conditional gating entirely.

## Findings

### Official Documentation and Resources

- **Source**: Kubernetes ingress-nginx ConfigMap Reference
  **URL**: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
  **Author**: Kubernetes Project
  **Date**: 2025-12
  **Activity**: N/A
  **Key points**:
    - `ssl-ciphers` (default: ECDHE-ECDSA-AES128-GCM-SHA256:...) controls CLIENT-facing TLS ciphers, not backend proxy ciphers
    - `ssl-protocols` (default: TLSv1.2 TLSv1.3) controls client-facing protocols
    - `proxy-ssl-location-only` (bool, default false) controls whether proxy-ssl parameters apply only at location level vs globally
    - NO ConfigMap key exists for backend proxy cipher suite configuration at the global level
    - Proxy-ssl settings (ciphers, protocols, verification) are configured via per-Ingress annotations, not ConfigMap

- **Source**: Kubernetes ingress-nginx Annotations Reference
  **URL**: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/
  **Author**: Kubernetes Project
  **Date**: 2025-12
  **Activity**: N/A
  **Key points**:
    - `nginx.ingress.kubernetes.io/proxy-ssl-ciphers` specifies enabled ciphers for requests to proxied HTTPS servers using OpenSSL cipher format
    - `nginx.ingress.kubernetes.io/proxy-ssl-protocols` enables specified protocols (e.g., TLSv1.2, TLSv1.3) for proxied HTTPS server requests
    - `nginx.ingress.kubernetes.io/proxy-ssl-secret` references a Secret containing client cert (tls.crt, tls.key) and CA certs (ca.crt) for backend authentication
    - `nginx.ingress.kubernetes.io/proxy-ssl-verify` enables/disables backend certificate verification (default: off)
    - `nginx.ingress.kubernetes.io/proxy-ssl-server-name` enables SNI when connecting to backend
    - Historically these required proxy-ssl-secret to be functional; newer versions allow them to work independently

- **Source**: NGINX Upstream Security Directives (Official NGINX Docs)
  **URL**: https://docs.nginx.com/nginx/admin-guide/security-controls/securing-http-traffic-upstream/
  **Author**: NGINX
  **Date**: 2025-12
  **Activity**: N/A
  **Key points**:
    - `proxy_ssl_protocols` specifies which TLS versions NGINX uses when connecting to upstream servers (e.g., TLSv1.2 TLSv1.3)
    - `proxy_ssl_ciphers` controls cipher suites offered during handshake with upstream (e.g., HIGH:!aNULL:!MD5)
    - Both directives are placed within location blocks where proxy_pass is used
    - These directives are part of the ngx_http_proxy_module (since nginx 1.5.6)
    - Can be used independently without requiring client certificates when backend doesn't demand client auth

- **Source**: NGINX Module ngx_http_proxy_module Documentation
  **URL**: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
  **Author**: NGINX
  **Date**: 2025-12
  **Activity**: N/A
  **Key points**:
    - `proxy_ssl_ciphers` default is DEFAULT, accepts OpenSSL cipher format, available in http/server/location context since 1.5.6
    - `proxy_ssl_protocols` default is TLSv1.2 TLSv1.3 (TLSv1.3 added by default in 1.23.4), available since 1.5.6
    - Both are independent from `proxy_ssl_certificate` and `proxy_ssl_certificate_key` directives
    - Can be set at http, server, or location scope

### Source Code Repositories

- **Source**: kubernetes/ingress-nginx GitHub (nginx.tmpl Template)
  **URL**: https://github.com/kubernetes/ingress-nginx/blob/main/rootfs/etc/nginx/template/nginx.tmpl
  **Author**: Kubernetes Community
  **Date**: 2025-12
  **Activity**: Active development, multiple commits per week
  **Key points**:
    - `proxy_ssl_ciphers` and `proxy_ssl_protocols` directives are emitted **conditionally** at both server and location scopes
    - **Critical condition**: Emission is gated behind `{{ if not (empty $server.ProxySSL.CAFileName) }}` and `{{ if not (empty $location.ProxySSL.CAFileName) }}`
    - This means ciphers and protocols are ONLY emitted if a CA certificate file path is present
    - Historically this required providing `proxy-ssl-secret` annotation to populate the CA file path
    - The values come from `$server.ProxySSL.Ciphers` and `$server.ProxySSL.Protocols` (or location equivalents)
    - Template also shows `proxy_ssl_verify`, `proxy_ssl_verify_depth`, `proxy_ssl_trusted_certificate` are similarly gated

- **Source**: kubernetes/ingress-nginx GitHub (Issue #10264 - ProxySSL Annotations Interdependency)
  **URL**: https://github.com/kubernetes/ingress-nginx/issues/10264
  **Author**: GitHub User (reported as bug)
  **Date**: 2023-08
  **Activity**: Open/Under discussion
  **Key points**:
    - Issue: When `proxy-ssl-secret` annotation is not provided, ALL proxy-ssl annotations are silently ignored
    - Root cause in `proxyssl/main.go#L119`: missing proxy-ssl-secret causes early function return, discarding proxy-ssl-ciphers, proxy-ssl-protocols, proxy-ssl-verify, etc.
    - User wanted to set backend certificate verification without client certificate authentication
    - Behavior is all-or-nothing: either all proxy-ssl annotations work (with secret) or none of them do (without secret)
    - Confirms that `proxy-ssl-ciphers` and `proxy-ssl-protocols` cannot be used independently in v1.15.1

- **Source**: kubernetes/ingress-nginx GitHub (Issue #6728 - proxy-ssl-name without proxy-ssl-secret)
  **URL**: https://github.com/kubernetes/ingress-nginx/issues/6728
  **Author**: GitHub User
  **Date**: 2020-11
  **Activity**: Open, bug label, help wanted
  **Key points**:
    - Users cannot use proxy-ssl annotations independently without proxy-ssl-secret
    - Workaround documented: use `configuration-snippet` annotation to inject raw nginx directives
    - Example workaround injects `proxy_ssl_server_name on;` and `proxy_ssl_name` directly
    - Confirmed workaround: `nginx.ingress.kubernetes.io/configuration-snippet: | proxy_ssl_server_name on; proxy_ssl_name "backend.local";`

- **Source**: kubernetes/ingress-nginx GitHub (PR #11490 - Make proxy-ssl-secret Optional)
  **URL**: https://github.com/kubernetes/ingress-nginx/pull/11490
  **Author**: g1franc (GitHub contributor)
  **Date**: 2024-06
  **Activity**: Open, requested review changes, targeting main and release-1.10 branches
  **Key points**:
    - PR removes early exit when proxy-ssl-secret is not provided
    - Changes `main.go` to allow other proxy-ssl annotations to work independently
    - Motivation: author needed `proxy-ssl-protocols: TLSv1.3` without client certificate for TLS-only backend
    - PR preserves existing behavior when invalid proxy-ssl-secret value is provided
    - Target: will merge into kubernetes/ingress-nginx v1.11.0+ (currently open/unmerged as of 2026-07)
    - Note: Repository transitioned to archived status March 24, 2026; unclear if PR will merge

### Community and Third-Party Sources

- **Source**: IBM Cloud Private Documentation - Customize TLS Cipher Suites for nginx-ingress-controller
  **URL**: https://www.ibm.com/docs/en/cloud-private/3.2.x?topic=codi-specifying-tls-cipher-suites-cloud-private-management-ingress-nginx-ingress-controller
  **Author**: IBM
  **Date**: 2022-11 (last updated)
  **Activity**: Enterprise documentation, stable/no frequent updates expected
  **Key points**:
    - Covers global TLS cipher configuration via ConfigMap
    - Addresses client-facing TLS ciphers (not backend proxy ciphers)
    - Recommends high-strength ciphers: ECDHE-ECDSA-AES128-GCM-SHA256, ECDHE-RSA-AES128-GCM-SHA256, etc.
    - No guidance on backend proxy cipher configuration separate from client ciphers

- **Source**: NGINX Community Blog - The NGINX Kubernetes Open Source Roadmap: First Half of 2026
  **URL**: https://blog.nginx.org/blog/the-nginx-kubernetes-open-source-roadmap-first-half-of-2026
  **Author**: NGINX
  **Date**: 2025-12
  **Activity**: Current roadmap and strategic direction
  **Key points**:
    - kubernetes/ingress-nginx is sunsetting and will be retired in March 2026
    - No more updates, bugfixes, or security patches after retirement
    - Users should plan migration to F5 NGINX Ingress Controller or alternative ingress solutions (HAProxy, Traefik, Kong)
    - Explains transition from open-source ingress-nginx to F5 NGINX Ingress Controller for long-term support

- **Source**: Medium Article - On TLS Cipher Suites and Staying Sane with cert-manager and nginx-ingress
  **URL**: https://medium.com/kranus-health-engineering/on-tls-cipher-suites-and-staying-sane-and-compliant-with-cert-manager-and-nginx-ingress-1717ec82d8b0
  **Author**: Nikolay Dimolarov (Kranus Health Engineering)
  **Date**: 2024-12
  **Activity**: Recent blog post, community perspective
  **Key points**:
    - Addresses practical challenges with ingress-nginx TLS configuration
    - Discusses client-facing cipher suite management and compliance
    - Context for backend proxy cipher configuration challenges in ingress-nginx
    - Real-world experience with ingress-nginx SSL/TLS configuration complexity

## Sources

- https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
- https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/
- https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/configmap.md
- https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/annotations.md
- https://docs.nginx.com/nginx/admin-guide/security-controls/securing-http-traffic-upstream/
- https://docs.nginx.com/nginx/admin-guide/security-controls/securing-tcp-traffic-upstream/
- https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- https://nginx.org/en/docs/http/ngx_http_ssl_module.html
- https://github.com/kubernetes/ingress-nginx/blob/main/rootfs/etc/nginx/template/nginx.tmpl
- https://github.com/kubernetes/ingress-nginx/issues/10264
- https://github.com/kubernetes/ingress-nginx/issues/6728
- https://github.com/kubernetes/ingress-nginx/pull/11490
- https://www.ibm.com/docs/en/cloud-private/3.2.x?topic=codi-specifying-tls-cipher-suites-cloud-private-management-ingress-nginx-ingress-controller
- https://blog.nginx.org/blog/the-nginx-kubernetes-open-source-roadmap-first-half-of-2026
- https://medium.com/kranus-health-engineering/on-tls-cipher-suites-and-staying-sane-and-compliant-with-cert-manager-and-nginx-ingress-1717ec82d8b0
- https://discuss.kubernetes.io/t/how-to-use-ingress-nginx-with-secure-backend/7347

## Metadata

- **Report Date**: 2025-12-05T14:32:00Z
- **Search Queries**: ingress-nginx v1.15 configmap proxy-ssl-ciphers backend TLS, ingress-nginx proxy-ssl-location-only configmap setting, nginx proxy_ssl_ciphers backend upstream HTTPS cipher configuration, ingress-nginx backend protocol HTTPS cipher suite without client certificate, kubernetes ingress nginx configure backend upstream ssl protocols, ingress-nginx PR 11490 proxy-ssl annotations without secret, configuration-snippet ingress-nginx proxy_ssl_ciphers backend HTTPS, ingress-nginx backend HTTPS cipher suite alternative approaches workaround 2025 2026, site:github.com/kubernetes/ingress-nginx proxy-ssl-ciphers issue proxy-ssl-secret, ingress-nginx issue 10264 proxy ssl ciphers without client certificate, ingress-nginx github rootfs nginx template proxy_ssl_ciphers
- **Model**: claude-haiku-4-5@20251001
