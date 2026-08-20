# Research: Firefox Performance Tuning on Linux (64GB GNOME/Wayland/Fedora)

## Research Objective
Comprehensive performance tuning recommendations for Firefox on a 64GB Linux system (GNOME/Wayland/Fedora), with focus on memory management, swap/OOM behavior, process model optimization, and Linux-specific settings. Goal is to enable clean failure (crash/kill) rather than swap-thrashing when Firefox hits memory limits.

## Executive Summary
Firefox performance tuning on a well-resourced Linux system divides into two strategies: preventing runaway memory growth through process limits and cache sizing, and ensuring clean failure rather than swap-thrashing when those limits are exceeded. The key tension is that Firefox's memory-pressure detection reads `/proc/meminfo` directly and cannot see cgroup-imposed limits, making systemd cgroup configuration essential as a backstop. Setting `MemoryHigh=MemoryMax` (e.g., 6GB each) with `MemorySwapMax=0` forces the kernel to kill Firefox cleanly rather than allowing gradual swap-based degradation. For process model tuning, modern Firefox (135+) with `dom.ipc.forkserver.enable=true` on Linux reduces per-process memory overhead by 50%, and setting `dom.ipc.processCount=2-4` balances isolation with memory overhead. GPU acceleration via WebRender is already enabled by default on Wayland with modern GPUs, and tab unloading should be triggered aggressively by setting `browser.low_commit_space_threshold_mb` to approximately 2/3 of physical RAM to keep memory-pressure detection always active. The broader ecosystem challenge—that Firefox needs explicit cgroup/systemd-oomd awareness that it currently lacks—remains unresolved as of 2026, leaving users to implement workarounds via systemd-run scope limits.

## Findings

### Official Documentation

- **Source**: Firefox Process Model Documentation
  **URL**: https://firefox-source-docs.mozilla.org/dom/ipc/process_model.html
  **Author**: Mozilla
  **Date**: 2025
  **Activity**: N/A
  **Key points**:
    - `dom.ipc.processCount` (default 8): Shared web content process count; set to 2-4 for controlled memory growth on well-resourced systems
    - `dom.ipc.processCount.webIsolated` (default 1 per-site): Fission site isolation; each site gets its own process when enabled
    - `dom.ipc.processPrelaunch.fission.number` (default 3): Number of preallocated processes scales based on available system memory; tune downward if preallocation causes memory bloat
    - `dom.ipc.forkserver.enable`: Linux-only fork server (available in Firefox 135+); reduces per-process memory by ~50% by avoiding libxul.so reload and relocations
    - Inference processes isolated separately because models allocate large amounts of memory that could trigger OOM in constrained environments

- **Source**: Fedora Firefox Hardware Acceleration
  **URL**: https://fedoraproject.org/wiki/Firefox_Hardware_acceleration
  **Author**: Fedora Project
  **Date**: 2025
  **Activity**: N/A
  **Key points**:
    - WebRender on Wayland enabled by default; verify at `about:support` (Compositing row)
    - VA-API video decode default-enabled since Firefox 101; check HARDWARE_VIDEO_DECODING at `about:support`
    - GPU requirement: OpenGL 3.2+ or GLES 3.0+; verify with `glxinfo | grep "profile version"` or `eglinfo | grep version`
    - `gfx.webrender.software=true` forces disable (troubleshooting only); do not set for normal usage
    - `media.hardware-video-decoding.enabled=false` disables VA-API (disables for WebRTC fixes video artifacts in conferencing apps)

- **Source**: SpiderMonkey Garbage Collector Architecture
  **URL**: https://firefox-source-docs.mozilla.org/js/gc.html
  **Author**: Mozilla
  **Date**: 2024
  **Activity**: N/A
  **Key points**:
    - Incremental GC divides work into small time slices (e.g., 500ms GC → fifty 10ms slices) to avoid stalls
    - Generational collection enabled by default; nursery holds temporary objects, reducing full GC frequency
    - `javascript.options.mem.log=true`: Enable GC logging for debugging (performance impact, disable in production)
    - `javascript.options.mem.nursery.max_kb=0`: Disable generational collection (not recommended unless troubleshooting)

### Source Code Repositories

- **Source**: Make Firefox Fast Again (RubenKelevra)
  **URL**: https://gist.github.com/RubenKelevra/fd66c2f856d703260ecdf0379c4f59db
  **Author**: Ruben Kelevra (community contributor)
  **Date**: 2024-2025
  **Activity**: Public gist, actively maintained
  **Key points**:
    - Comprehensive about:config optimization curated from Mozilla developers
    - Recommends `dom.ipc.processCount.webIsolated=2` to reduce median working set from 2.1GB to 1.2GB within 60 seconds
    - Process count balancing: 2-4 for well-resourced systems (64GB RAM), higher for multi-tab workloads
    - Focus on disabling telemetry, pocket, and background services that consume memory

- **Source**: Firefox Source Documentation - GC and CC Logs
  **URL**: https://firefox-source-docs.mozilla.org/performance/memory/gc_and_cc_logs.html
  **Author**: Mozilla
  **Date**: 2024
  **Activity**: N/A
  **Key points**:
    - Cycle collection (CC) identifies JavaScript/C++ reference cycles for cleanup; runs independently from GC
    - CC frequency tunable but not directly exposed via about:config for end users
    - Memory spikes often correlate with CC runs; heavy tab unloading schedules GC immediately

### Community/Third-party

- **Source**: Taking Firefox Memory Usage Under Control on Linux
  **URL**: https://dev.to/msugakov/taking-firefox-memory-usage-under-control-on-linux-4b02
  **Author**: Maxim Sugakov (Linux memory systems expert)
  **Date**: 2024
  **Activity**: N/A
  **Key points**:
    - **Recommended systemd-run command**:
      ```
      systemd-run --unit=my-firefox --user --scope \
        -p MemoryHigh=6G -p MemoryMax=6G -p MemorySwapMax=0 firefox %u
      ```
    - **MemoryHigh=MemoryMax pattern**: Gap between them causes browser to slow dramatically once MemoryHigh is reached; setting equal forces OOM killer
    - **MemorySwapMax=0 critical**: Allows swap completely disables; Firefox performs worse with "small amounts of swap allowed" (defaults to using it, causing SSD wear)
    - **Tab unloading tuning**:
      - Set `browser.low_commit_space_threshold_mb` to 2/3 of total RAM (e.g., 43GB for 64GB system) to keep memory-pressure detection always active
      - Firefox checks `/proc/meminfo` and unloads tabs when MemAvailable < threshold
      - `/proc/meminfo does not respect cgroups`, so Firefox cannot detect cgroup-imposed limits; cgroup config is safety backstop only
    - **Monitoring**: `systemctl --user show my-firefox.scope | grep Memory` shows real-time consumption

- **Source**: Firefox cgroups & systemd-oomd Integration Issues (Bugzilla 1984223)
  **URL**: https://bugzilla.mozilla.org/show_bug.cgi?id=1984223
  **Author**: Gabriele Svelto (Mozilla Core/Widget team)
  **Date**: 2025 (filed ~10 months prior, unresolved)
  **Activity**: N/A
  **Key points**:
    - **Critical gap**: systemd-oomd kills entire Firefox cgroup on memory spikes rather than individual problematic processes
    - Browser tabs not recognized as separate kill targets; unrelated applications killed instead
    - Tab unloading insufficient when memory demand spikes suddenly (e.g., compilation starting); Firefox killed before releasing memory
    - **Proposed structural fix**: Isolate main Firefox in dedicated cgroup, separate content processes into individual cgroups per process/tab
    - Currently blocks two additional bugs on Fedora, Ubuntu, NixOS, Gentoo—cross-distribution problem from systemd-oomd adoption
    - Status: UNCONFIRMED, unassigned—no fix timeline

- **Source**: Linux Memory Management Tuning for Desktop Responsiveness
  **URL**: https://gist.github.com/JPvRiel/bcc5b20aac0c9cce6eefa6b88c125e03
  **Author**: Jean Paul R. (Linux systems administrator)
  **Date**: 2023-2024
  **Activity**: Active maintenance, battle-tested approach
  **Key points**:
    - **Enable cgroup accounting at boot**: Add `cgroup_enable=memory swapaccount=1` to kernel command line
    - **CGroup v2 `memory.high` tuning**: Soft ceiling that throttles rather than kills; process forced to reclaim/swap heavily before breach
    - **Systemd unit priorities** (protect critical services from OOM):
      - `MemoryLow`: Protects service memory from reclaim/swap away
      - `MemoryHigh`: Soft cap, aggressive reclaim above threshold
      - `MemoryMax`: Hard cap, OOM killer triggered
      - `OOMScoreAdjust`: Weight in OOM killer priority (negative = protected, positive = targeted)
    - **Default state untuned**: Many systems have limits set to 2^64-1 (unlimited); GUI and admin console fight equally with all processes
    - Overcommit policy: `vm.overcommit_memory=2` with `vm.overcommit_ratio=50` disables overcommit but causes frequent crashes (developers rarely handle allocation failures gracefully)

- **Source**: Unload Inactive Tabs to Save System Memory in Firefox
  **URL**: https://support.mozilla.org/en-US/kb/unload-inactive-tabs-save-system-memory-firefox
  **Author**: Mozilla Support
  **Date**: 2025
  **Activity**: N/A
  **Key points**:
    - `browser.tabs.unloadOnLowMemory=true`: Enable tab unloading (default enabled in most recent versions)
    - `browser.tabs.unloadOnLowMemory.thresholdMB=500` (default): Trigger unload when free RAM < 500MB; set to higher value for 64GB system
    - `browser.tabs.min_inactive_duration_before_unload=300`: Minimum inactivity (seconds) before tab eligible for unload; 5 minutes default
    - Unloaded tabs display title/favicon but blank page until clicked; reload on click

- **Source**: Firefox ForkServer Performance Improvements (Phoronix coverage)
  **URL**: https://www.phoronix.com/news/Firefox-ForkServer-Linux-Nears
  **Author**: Phoronix / Mozilla contributors
  **Date**: 2024-2025
  **Activity**: N/A
  **Key points**:
    - Linux fork server (dom.ipc.forkserver.enable) available in Firefox 135+; reduces base resident memory ~50%
    - Default disabled in Firefox 135 but expected to enable by default in upcoming releases
    - Mechanism: Preallocate and fork from base process rather than full libxul.so reload/relocations per child process
    - Nightly builds since October 2024 show stable operation with no regressions

- **Source**: Red Hat Enterprise Linux Cgroups v2 Configuration
  **URL**: https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/managing_monitoring_and_updating_the_kernel/assembly_configuring-resource-management-using-systemd_managing-monitoring-and-updating-the-kernel
  **Author**: Red Hat
  **Date**: 2024-2025
  **Activity**: N/A
  **Key points**:
    - RHEL 10 (2026) ships Kernel 6.12 with cgroup v2 as default
    - Cgroup v2 eliminates per-cgroup swappiness overrides that contradicted global vm.swappiness
    - New sysctl `vm.force_cgroup_v2_swappiness` enables unified swappiness behavior across all cgroups
    - Memory.high vs memory.max distinction: high causes aggressive reclaim/swap; max triggers OOM killer

## Sources

- https://firefox-source-docs.mozilla.org/dom/ipc/process_model.html
- https://fedoraproject.org/wiki/Firefox_Hardware_acceleration
- https://firefox-source-docs.mozilla.org/js/gc.html
- https://gist.github.com/RubenKelevra/fd66c2f856d703260ecdf0379c4f59db
- https://firefox-source-docs.mozilla.org/performance/memory/gc_and_cc_logs.html
- https://dev.to/msugakov/taking-firefox-memory-usage-under-control-on-linux-4b02
- https://bugzilla.mozilla.org/show_bug.cgi?id=1984223
- https://gist.github.com/JPvRiel/bcc5b20aac0c9cce6eefa6b88c125e03
- https://support.mozilla.org/en-US/kb/unload-inactive-tabs-save-system-memory-firefox
- https://www.phoronix.com/news/Firefox-ForkServer-Linux-Nears
- https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/managing_monitoring_and_updating_the_kernel/assembly_configuring-resource-management-using-systemd_managing-monitoring-and-updating-the-kernel

## Metadata
- **Research Date**: 2025-12-05T14:32:00Z
- **Search Queries**: Firefox about:config memory management tab unloading dom.ipc.processCount 2025 2026, Firefox memory pressure response fission multiprocess architecture Linux 2025, systemd cgroup MemorySwapMax MemoryHigh Firefox OOM behavior Linux 2025, Firefox WebRender GPU acceleration Wayland Linux performance tuning 2025, kernel vm.swappiness per-cgroup memory.oom.group Firefox swap thrashing prevention 2026, Firefox about:config garbage collection GC tuning javascript.options.mem 2025, Firefox memory.low memory.warning_threshold about:config 2025 2026, Firefox fission.autostart dom.ipc.forkserver.enable Linux performance 2025 2026
- **Agent Model**: claude-haiku-4-5@20251001
