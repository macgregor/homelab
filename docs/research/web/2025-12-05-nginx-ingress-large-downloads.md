# Research Report: NGINX Ingress Controller Annotations and Configuration for Large File Downloads

## Objective

Research nginx-ingress-controller annotations and configuration options relevant to serving large file downloads through a reverse proxy, focusing on: keep-alive mechanisms (upstream and client), chunked transfer encoding and streaming behavior, connection timeout settings beyond read/send timeouts, buffer and temp file limits, and other directives commonly recommended for sustaining multi-GB downloads over slow connections.

## Executive Summary

NGINX Ingress Controller provides a comprehensive set of annotations and ConfigMap settings designed to handle large file downloads through four key mechanisms. First, **timeout configuration** uses interval-based rather than total-time logic: `proxy-read-timeout` and `proxy-send-timeout` measure gaps between data chunks, not total transfer duration, meaning sustained streaming won't trigger timeouts as long as data flows continuously. Second, **upstream keep-alive connections** (controlled by `upstream-keepalive-connections`, `upstream-keepalive-timeout`, `upstream-keepalive-time`, and `upstream-keepalive-requests` ConfigMap settings) enable connection reuse between NGINX and backend servers, reducing connection overhead for multiple downloads. Third, **buffering control** defaults to disabled (`proxy-buffering: "off"`) and when combined with `proxy-http-version: "1.1"`, enables true streaming of responses without intermediate buffering, critical for avoiding memory exhaustion on large files. Fourth, **HTTP/1.1 configuration** via the `proxy-http-version` annotation enables both keep-alive connections and proper chunked transfer encoding behavior, which is essential for streaming large responses where NGINX must forward data immediately rather than accumulating it.

The settings already applied (proxy-read-timeout, proxy-send-timeout, proxy-buffering: off, proxy-body-size: 0) address the most critical requirements for downloads. However, several additional considerations emerge: ensure `proxy-http-version` is set to "1.1" to enable upstream connection reuse and chunked transfer support; consider `upstream-keepalive-connections` if the backend has connection limits or if serving many concurrent downloads; and note that `client-body-timeout` and `client-header-timeout` are less relevant for downloads (they govern uploads and headers), but `proxy-buffer-size` remains important for handling response headers even when response body buffering is disabled.

## Findings

### Official Documentation and Resources

- **Source**: NGINX Ingress Controller - Annotations Reference
  **URL**: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/
  **Author**: Kubernetes Project
  **Date**: 2025-12 (maintained)
  **Activity**: N/A
  **Key points**:
    - All timeout values are unitless and in seconds (e.g., `nginx.ingress.kubernetes.io/proxy-read-timeout: "120"`)
    - Timeouts measure **interval between operations**, not total request time
    - `proxy-buffering` defaults to disabled; set to "on" only if needed for rate limiting
    - `proxy-buffer-size` (default 4k) sets header buffer; response body can exceed this when buffering disabled
    - `proxy-buffers-number` (default 4) controls number of buffers when buffering enabled
    - `proxy-max-temp-file-size` spills responses to disk when memory buffers full (only when buffering enabled)
    - `proxy-http-version` defaults to "1.1" — supports keep-alive and chunked transfer encoding
    - `connection-proxy-header` (e.g., "keep-alive") overrides NGINX's default connection header behavior
    - `proxy-request-buffering: "off"` prevents buffering of chunked request bodies before sending to backend

- **Source**: NGINX Ingress Controller - ConfigMap Reference
  **URL**: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
  **Author**: Kubernetes Project
  **Date**: 2025-12 (maintained)
  **Activity**: N/A
  **Key points**:
    - `upstream-keepalive-connections` (default 320) — max idle keepalive connections per worker to backends
    - `upstream-keepalive-timeout` (default 60s) — idle connection timeout before closure
    - `upstream-keepalive-time` (default 1h) — max total lifetime for processing requests through one connection
    - `upstream-keepalive-requests` (default 10000) — max requests per keepalive connection before forced closure
    - `proxy-connect-timeout` (default 5s) — establishes TCP to backend; rarely needs adjustment
    - `proxy-read-timeout` (default 60s) — interval between successive read operations from backend
    - `proxy-send-timeout` (default 60s) — interval between successive write operations to backend
    - `client-body-timeout` (default 60s) — timeout reading client request body (relevant for uploads, not downloads)
    - `client-header-timeout` (default 60s) — timeout reading client request headers
    - `proxy-buffering` (default "off") — disables response buffering for streaming
    - `proxy-buffer-size` (default 4k) — buffer for response headers only when buffering disabled
    - `proxy-request-buffering` (default "on") — buffers entire request before sending to backend
    - `proxy-body-size` (default 1m) — `client_max_body_size`; set "0" for unlimited

- **Source**: NGINX Official Documentation - ngx_http_proxy_module
  **URL**: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
  **Author**: NGINX Core Project
  **Date**: 2025 (maintained)
  **Activity**: N/A
  **Key points**:
    - `proxy_read_timeout` measures gap between consecutive read operations; large streaming transfers won't timeout if data continuously arrives
    - `proxy_send_timeout` measures gap between consecutive write operations to backend
    - `proxy_buffering` controls whether responses are buffered in memory; when off, data proxies synchronously to client
    - `proxy_buffer_size` is the buffer for the **first part** of response (headers); default 4k-8k depending on platform
    - `proxy_buffers` (e.g., 8 4k) sets number and size of buffers for response body (only when buffering enabled)
    - `proxy_busy_buffers_size` limits total buffer space that can be busy sending response while still reading from backend
    - `proxy_max_temp_file_size` allows spilling buffered responses to disk (only when buffering enabled)
    - `proxy_http_version 1.1` is required for keep-alive connections to upstream; default is now 1.1 as of NGINX 1.29.7
    - **Keep-alive setup requires three elements**: `upstream { keepalive N; }`, `proxy_http_version 1.1;`, and `proxy_set_header Connection "";`
    - Clearing the Connection header prevents client headers from interfering with upstream connection reuse
    - `proxy_request_buffering` controls request body buffering; when off and HTTP/1.1 enabled, chunked requests forward without buffering

- **Source**: NGINX Official Documentation - ngx_http_upstream_module
  **URL**: https://nginx.org/en/docs/http/ngx_http_upstream_module.html
  **Author**: NGINX Core Project
  **Date**: 2025 (maintained)
  **Activity**: N/A
  **Key points**:
    - `keepalive` directive sets max idle connections per worker process to cache (not total system limit)
    - `keepalive_timeout` (default 60s) governs how long idle connections stay in the cache before closure
    - `keepalive_requests` (default 100, but 10000 in ingress-nginx) — requests per connection before forced close
    - `keepalive_time` (default 1h) — absolute max lifetime for a connection even if actively used
    - Connections are reused in LRU (Least Recently Used) order; when cache full, oldest idle connection closes

- **Source**: NGINX Blog - Keep-Alive to Upstreams Now Default in NGINX 1.29.7
  **URL**: https://blog.nginx.org/blog/keep-alive-to-upstreams-is-now-default-in-nginx-1-29-7
  **Author**: NGINX Product Team
  **Date**: 2026-03
  **Activity**: N/A
  **Key points**:
    - As of NGINX 1.29.7 (March 2026), HTTP/1.1 with keep-alive is the default for upstream proxying
    - Prior to 1.29.7, manual configuration was required; post-1.29.7, it's automatic
    - The `proxy_set_header Connection "";` directive remains essential to override client Connection headers

### Source Code Repositories

- **Source**: kubernetes/ingress-nginx GitHub Repository - Annotations Documentation
  **URL**: https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/annotations.md
  **Author**: Kubernetes Community
  **Date**: 2025-12 (actively maintained)
  **Activity**: Commits within last month; repository has 17k+ stars
  **Key points**:
    - Comprehensive annotation reference with defaults and examples for all timeout, buffering, and connection settings
    - `proxy-http-version: "1.1"` annotation enables HTTP/1.1 proxying with keep-alive and chunked encoding support
    - Per-Ingress annotations override global ConfigMap settings
    - `proxy-request-buffering: "off"` prevents buffering of entire request body before forwarding (for streaming uploads)
    - `connection-proxy-header` annotation customizes the Connection header sent to upstream (e.g., "keep-alive")
    - `backend-protocol` supports GRPC/GRPCS for streaming-aware protocol selection
    - Stream-level (TCP/UDP) configuration via `stream-snippet` annotation for custom streaming tunnels

- **Source**: kubernetes/ingress-nginx GitHub Repository - ConfigMap Documentation
  **URL**: https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/configmap.md
  **Author**: Kubernetes Community
  **Date**: 2025-12 (actively maintained)
  **Activity**: Commits within last month; repository has 17k+ stars
  **Key points**:
    - Complete ConfigMap reference with 100+ global settings
    - `upstream-keepalive-*` family controls backend connection pooling at the cluster level
    - `proxy-*` timeouts and buffer settings can be overridden per-Ingress via annotations
    - `proxy-stream-timeout: "600s"` (10 minutes) for TCP/UDP stream proxying (different from HTTP proxy timeouts)
    - `proxy-buffering: "off"` is the default, enabling synchronous streaming for all backends unless explicitly overridden

- **Source**: kubernetes/ingress-nginx GitHub Issue #6242 - Chunked Transfer Encoding Not Working
  **URL**: https://github.com/kubernetes/ingress-nginx/issues/6242
  **Author**: Kubernetes Community
  **Date**: 2023-2024 (issue active, discussing request buffering behavior)
  **Activity**: Multiple comments from maintainers and users; unresolved at time of research
  **Key points**:
    - User reported that `proxy-request-buffering: "off"` wasn't preventing buffering of large POST request bodies
    - Even with annotation set, the entire request was held before forwarding to backend (preventing streaming uploads)
    - NGINX official docs state request buffering should be disabled, but ingress-nginx controller didn't honor it in some scenarios
    - Discussion reveals interaction between Azure Application Gateway (SSL termination) and ingress-nginx buffering behavior
    - Issue highlights that `proxy-request-buffering` is specifically for **request** bodies, not response bodies; different directive

### Community and Third-Party Sources

- **Source**: GetPageSpeed - NGINX Upstream Keepalive: Connection Pooling Guide
  **URL**: https://www.getpagespeed.com/server-setup/nginx/nginx-upstream-keepalive
  **Author**: GetPageSpeed (DevOps/NGINX Consulting)
  **Date**: 2026 (recently updated)
  **Activity**: N/A
  **Key points**:
    - Keepalive connection pooling operates **between NGINX and backends**, not between clients and NGINX
    - Each NGINX worker maintains an independent LRU cache of idle connections; connections not reused across workers
    - With 8 NGINX workers and `keepalive 32`, maximum total pool is 256 connections
    - Connection sizing formula: `pool_size = (requests_per_second / workers) / avg_requests_per_connection * 2`
    - Keep-alive eliminates 10-100ms TCP handshake latency and 10-50ms additional TLS handshake for HTTPS backends
    - Without keep-alive, high RPS leads to TIME_WAIT socket accumulation (60s per closed connection); this can exhaust available sockets
    - Large file transfers hold their connection until completion, so large downloads don't see reuse benefits during transfer but benefit from reduced churn on other requests

- **Source**: GetPageSpeed - NGINX Timeout Directives: Complete Configuration Guide
  **URL**: https://www.getpagespeed.com/server-setup/nginx/nginx-timeout
  **Author**: GetPageSpeed (DevOps/NGINX Consulting)
  **Date**: 2026 (recently updated)
  **Activity**: N/A
  **Key points**:
    - **Critical distinction**: proxy timeouts measure **intervals between data chunks**, not total transfer time
    - If backend sends 100 MB file with continuous data flow, even `proxy_read_timeout 60s` won't timeout a multi-hour download
    - Timeout only fires when connection goes idle for longer than the configured interval
    - For large file uploads, both `client_body_timeout` (NGINX ← client) and `proxy_send_timeout` (NGINX → backend) matter
    - For large file downloads, `proxy_read_timeout` (NGINX ← backend) is critical; `client_body_timeout` is irrelevant
    - For large downloads to slow clients, increase `client_body_timeout` is wrong; client-side buffering/streaming doesn't use this timeout
    - Location-specific overrides (per-Ingress annotations) are preferred over global ConfigMap changes
    - Example practical config: `proxy-connect-timeout: 10, proxy-read-timeout: 300, proxy-send-timeout: 300` for heavy processing backends

- **Source**: USAVPS - How to Configure Nginx Proxy Buffers for Optimal Performance
  **URL**: https://usavps.com/blog/nginx-proxy-buffers/
  **Author**: USAVPS (Hosting Provider)
  **Date**: 2026
  **Activity**: N/A
  **Key points**:
    - When `proxy_buffering: off`, responses stream synchronously without intermediate buffering
    - Even with buffering off, `proxy_buffer_size` (default 4k) still applies — this buffer holds response headers
    - For large downloads with buffering off, the response headers must fit in `proxy_buffer_size`; if headers exceed this, response is considered invalid
    - When buffering is on, `proxy_buffers` (e.g., 8 4k = 32k total in-memory) controls response body buffering
    - When buffering on and response exceeds `proxy_buffers` limit, NGINX spills to disk temp files (controlled by `proxy_max_temp_file_size`)
    - Disk buffering reduces RAM usage but increases latency and disk I/O; appropriate for slow clients downloading large files
    - For streaming large files to fast clients, buffering off is optimal; for slow clients, moderate buffering or temp file spillover can improve throughput

- **Source**: Medium - Improving Microservices Performance with NGINX Upstream and Proxy Buffers
  **URL**: https://medium.com/@favxlaw/improving-microservices-performance-with-nginx-upstream-and-proxy-buffers-db6341a96c8f
  **Author**: Favour Lawrence
  **Date**: 2025
  **Activity**: N/A
  **Key points**:
    - Upstream keep-alive and proxy buffering are independent concerns; configure both based on use case
    - For microservices with multiple backends, high upstream keep-alive connection counts prevent connection pool exhaustion
    - Buffering strategy depends on client speed: fast clients benefit from streaming (buffering off); slow clients benefit from buffering to absorb backend response rate variation

- **Source**: OneUptime - NGINX Ingress Controller Annotations Configuration
  **URL**: https://oneuptime.com/blog/post/2026-02-20-kubernetes-nginx-ingress-annotations/view
  **Author**: OneUptime (Observability Platform)
  **Date**: 2026-02
  **Activity**: N/A
  **Key points**:
    - Annotations take precedence over ConfigMap defaults
    - Timeout annotations are useful for specific backends with known slow processing characteristics
    - Large file downloads require both adequate timeouts and proper buffering configuration

- **Source**: OneUptime - NGINX Ingress ConfigMap Tuning
  **URL**: https://oneuptime.com/blog/post/2026-02-09-nginx-ingress-configmap-tuning/view
  **Author**: OneUptime (Observability Platform)
  **Date**: 2026-02
  **Activity**: N/A
  **Key points**:
    - Global ConfigMap changes apply to all Ingresses unless overridden by per-Ingress annotations
    - Keep-alive settings are cluster-wide, affecting all upstream connections
    - ConfigMap changes require NGINX controller restart to take effect; annotations trigger hot reload

## Sources

- https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/
- https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
- https://nginx.org/en/docs/http/ngx_http_proxy_module.html
- https://nginx.org/en/docs/http/ngx_http_upstream_module.html
- https://blog.nginx.org/blog/keep-alive-to-upstreams-is-now-default-in-nginx-1-29-7
- https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/annotations.md
- https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/configmap.md
- https://github.com/kubernetes/ingress-nginx/issues/6242
- https://www.getpagespeed.com/server-setup/nginx/nginx-upstream-keepalive
- https://www.getpagespeed.com/server-setup/nginx/nginx-timeout
- https://usavps.com/blog/nginx-proxy-buffers/
- https://medium.com/@favxlaw/improving-microservices-performance-with-nginx-upstream-and-proxy-buffers-db6341a96c8f
- https://oneuptime.com/blog/post/2026-02-20-kubernetes-nginx-ingress-annotations/view
- https://oneuptime.com/blog/post/2026-02-09-nginx-ingress-configmap-tuning/view

## Metadata

- **Report Date**: 2025-12-05T15:30:00Z
- **Search Queries**: nginx-ingress-controller annotations proxy-read-timeout proxy-send-timeout large file downloads, kubernetes nginx ingress keep-alive connections upstream-keepalive-timeout, nginx reverse proxy streaming large files chunked transfer encoding HTTP/2, nginx proxy buffering settings buffer-size proxy-buffer large downloads, nginx ingress controller ConfigMap settings client-body-timeout client-header-timeout, nginx upstream keepalive directive connection pooling reuse large file downloads, proxy-connect-timeout proxy-send-timeout proxy-read-timeout large files slow clients streaming
- **Model**: claude-haiku-4-5@20251001
