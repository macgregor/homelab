# Known Patterns

Stable failure signatures observed across multiple incidents. Reference during Phase 3 (drill down) of investigation.

## 1. SD Card Degradation

**Symptoms**: Rising `diskio_io_await` on `mmcblk0`, filesystem errors in dmesg, read-only root mount, high `processes_blocked`.
**Detection**:
```
obs-query disk <node>       # io_await_ms on mmcblk0 > 100ms
obs-query node-health <node> # procs_blocked > 0 sustained
```
**Impact**: Node becomes unusable. Pods fail to start. Kubelet may go NotReady.
**Remediation**: Replace SD card. Consider USB boot or iSCSI root for longevity.
**Related**: NFS Mount Stalls (pattern 3) can have similar blocked-process symptoms.

## 2. ARM Thermal Throttling

**Symptoms**: `temp_temp > 80C`, CPU frequency drops (visible as sudden CPU usage drop despite load), correlates with CPU-intensive workloads.
**Detection**:
```
obs-query temperature <node> 24h  # max_c > 80
obs-query cpu <node> 24h          # look for drops coinciding with temp spikes
```
**Impact**: Performance degradation. Pods may timeout. Build/transcode jobs slow down.
**Remediation**: Improve case airflow. Add heatsinks or fan. Reduce concurrent CPU-intensive workloads. RPi 4B throttles at 80C.

## 3. NFS Mount Stalls

**Symptoms**: Pods stuck in ContainerCreating, `processes_blocked > 0` sustained, `df` hangs on SSH, node may go NotReady if kubelet's root volume is affected.
**Detection**:
```
obs-query node-health <node>  # procs_blocked > 0 sustained
obs-query nas                 # check NAS health, load, uptime
obs-query network <node>      # network errors between node and NAS
```
**Impact**: All pods using NFS PVs on affected node stall. New pods can't mount volumes.
**Remediation**: Check NAS reachability (`ping 192.168.1.200`). Check NFS exports (`showmount -e 192.168.1.200`). If NAS is healthy, try `umount -f` on the stale mount. May require node reboot.
**Related**: SD Card Degradation (pattern 1) can also cause blocked processes.

## 4. Pod OOM Kills

**Symptoms**: Restart storms (>5 restarts/hour), `resource-pressure` shows ratio > 0.9, node may show MemoryPressure condition.
**Detection**:
```
obs-query pod-restarts <namespace> 1h    # high restart count
obs-query resource-pressure <namespace>  # ratio near 1.0
obs-query node-conditions                # MemoryPressure
```
**Impact**: Pod crash loops. If many pods OOM simultaneously, node memory pressure triggers evictions.
**Remediation**: Increase memory limits. Investigate memory leak (growing usage over time). Check if workload is legitimately memory-hungry.

## 5. DNS Resolution Failures

**Symptoms**: Ingress 502 errors spike, CoreDNS pods unhealthy or restarting, internal service names fail to resolve.
**Detection**:
```
obs-query ingress-errors 1h     # 502 spike
obs-query pod-health kube-system # CoreDNS health
obs-query pod-restarts kube-system
```
**Impact**: All services relying on DNS fail. Ingress returns 502 for requests it can't route.
**Remediation**: Check CoreDNS pods (`kubectl -n kube-system logs -l k8s-app=kube-dns`). Verify CoreDNS configmap. CoreDNS is managed by k3s's bundled HelmChart CR -- restart with `kubectl -n kube-system rollout restart deployment/coredns`.

## 6. Certificate Expiry

**Symptoms**: HTTPS errors in browsers, 495/496 nginx status codes in ingress logs, cert-manager pod issues.
**Detection**:
```
obs-query ingress-errors 1h     # 495/496 status codes
obs-query pod-health cert-manager
obs-query deployments cert-manager
```
**Impact**: All HTTPS services return certificate errors. Let's Encrypt certs auto-renew, so this usually indicates cert-manager failure.
**Remediation**: Check cert-manager logs. Verify ClusterIssuer. Check `kubectl get certificates -A` for NotReady certs. See `docs/08-maintenance.md` for cert rotation.

## 7. Synology RAID Degradation

**Symptoms**: `raid_status != 1`, `disk_status != 1`, NAS may show elevated load or temperature.
**Detection**:
```
obs-query nas    # raid status and disk status
```
**Impact**: RAID 1 can survive one disk failure. Degraded RAID has no redundancy -- a second failure means data loss. All NFS-backed pods are at risk.
**Remediation**: Check Synology DSM Storage Manager for details. Replace failed disk. Do NOT reboot NAS during rebuild. Monitor rebuild progress. Status codes: 1=Normal, 2=Repairing, 11=Degraded, 12=Crashed.

## 8. Router Overload

**Symptoms**: `snmp_mikrotik_cpu_load > 80%`, packet drops on WAN interface, latency spikes.
**Detection**:
```
obs-query router              # cpu_load, interface stats
obs-query firewall-drops 1h   # volume of drops
```
**Impact**: Network throughput degradation. DNS resolution slows. All cluster operations affected.
**Remediation**: Check for DDoS or port scan (high firewall drop volume from single source). Check for routing loops. Reduce firewall rule complexity. Consider disabling per-connection tracking for high-throughput flows.

## 9. Ingress Controller Issues

**Symptoms**: 5xx spike in `ingress-status`, ingress-nginx deployment shows `healthy: false`, pods restarting.
**Detection**:
```
obs-query ingress-status 1h   # 5xx count
obs-query deployments ingress-nginx
obs-query pod-restarts ingress-nginx
```
**Impact**: All externally-accessible services return errors. Internal ingress may be affected independently.
**Remediation**: Check ingress-nginx pod logs. Check for resource pressure on the node running the controller. Restart with `just ingress-nginx-external-restart`.

## 10. Storage Volume Full

**Symptoms**: `disk_used_percent > 90%`, DiskPressure node condition, pods fail to write, log rotation stops.
**Detection**:
```
obs-query disk <node>         # used_pct > 90
obs-query node-conditions     # DiskPressure
obs-query nas-storage         # NAS volume usage
```
**Impact**: Node: kubelet evicts pods. NAS: NFS writes fail, databases corrupt.
**Remediation**: Node: clean up container images (`crictl rmi --prune`), check log sizes. NAS: identify large consumers, expand volume or move data.
