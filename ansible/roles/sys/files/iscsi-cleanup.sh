#!/bin/bash
# iSCSI cleanup script - called when iscsid is stopped/disabled
# Logs out all active sessions and removes discovery records/database
# This ensures iSCSI stays disabled even if socket activation is triggered

echo "Cleaning up iSCSI sessions and discovery records..."

# Logout all active sessions
/usr/sbin/iscsiadm -m session -u 2>/dev/null || true
sleep 1

# Purge the entire iSCSI database to prevent auto-login on next start
# This is the most reliable way to ensure iSCSI stays disabled
rm -rf /etc/iscsi/nodes 2>/dev/null || true
rm -rf /etc/iscsi/send_targets 2>/dev/null || true
rm -rf /var/lib/iscsi 2>/dev/null || true

# Kill any stray iscsid processes
pkill -9 iscsid 2>/dev/null || true

echo "iSCSI cleanup complete"
exit 0
