#!/bin/bash
# {{ ansible_managed }}
#
# Daily node maintenance: GPG keys, cache cleanup, log cleanup, conditional reboot.
# Usage: node-maintenance.sh [--check]
#   --check  Print what would happen without rebooting

CHECK_ONLY=false
if [ "$1" = "--check" ]; then
    CHECK_ONLY=true
fi

log() { logger -t node-maintenance "$1"; echo "$1"; }

# --- Maintenance tasks (always run) ---

# Import all GPG keys from installed repos (handles future key rotations)
for key in /etc/pki/rpm-gpg/RPM-GPG-KEY-*; do
    rpm --import "$key" 2>/dev/null
done

# Clean DNF package cache to prevent accumulation on SD card
dnf clean packages -q

# Warn if root filesystem is getting full (no monitoring on these nodes)
usage=$(df --output=pcent / | tail -1 | tr -dc '0-9')
if [ "$usage" -gt 80 ]; then
    log "WARNING: Root filesystem ${usage}% full"
fi

# --- Conditional reboot ---

# Check if core system libraries were updated since boot.
# Avoids needs-restarting -r which falsely detects kernel updates on RPi
# builds where the kernel is not an RPM package (RHBZ#2137935).
boot_ts=$(date -d "$(uptime -s)" +%s)
for pkg in glibc systemd-libs dbus openssl-libs linux-firmware; do
    install_ts=$(rpm -q --qf '%{INSTALLTIME}\n' "$pkg" 2>/dev/null | sort -rn | head -1)
    if [ -n "$install_ts" ] && [ "$install_ts" -gt "$boot_ts" ]; then
        if $CHECK_ONLY; then
            log "Reboot needed: $pkg updated since boot (dry run, not rebooting)"
            exit 0
        fi
        log "Rebooting: $pkg updated since boot"
        shutdown -r +5 'Rebooting after core library updates'
        exit 0
    fi
done

log "No reboot required"
