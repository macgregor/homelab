#!/usr/bin/env bash
#
# Sync split-horizon DNS records from local Kubernetes ingress definitions.
#
# Scans network.yml files in kube/{sys,app,media,observation}/ for Ingress
# resources, maps ingressClassName to LoadBalancer IPs, and updates the
# router static DNS list in ansible/inventory/group_vars/router.yaml.
#
# Manual entries placed above the "# auto-managed below" marker in
# router_dns_hosts are preserved. Only entries below the marker are
# replaced by this script.
#
# Does not touch the router. Apply changes with:
#   cd ansible && ansible-playbook mikrotik-configure.yml
#
# Usage:
#   ./scripts/homelab-sync-dns.sh [--dry-run]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTER_VARS="$REPO_ROOT/ansible/inventory/group_vars/router.yaml"

EXTERNAL_IP="192.168.1.220"
INTERNAL_IP="192.168.1.221"

SCAN_DIRS=(
    "$REPO_ROOT/kube/sys"
    "$REPO_ROOT/kube/app"
    "$REPO_ROOT/kube/media"
    "$REPO_ROOT/kube/observation"
)

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# ── Parse ingress definitions from local YAML ────────────────────────

# Extract (ip, hostname) pairs from network.yml files using yq.
scan_ingress_hosts() {
    find "${SCAN_DIRS[@]}" -name 'network.yml' \
        -exec yq eval-all 'select(.kind == "Ingress") | (.spec.ingressClassName + " " + .spec.rules[0].host)' {} \; \
    | while read -r class host; do
        case "$class" in
            nginx-external) echo "$EXTERNAL_IP $host" ;;
            nginx-internal) echo "$INTERNAL_IP $host" ;;
        esac
    done
}

# Collect and sort: IP first, then hostname
ENTRIES=$(scan_ingress_hosts | sort -k1,1 -k2,2)

if [[ -z "$ENTRIES" ]]; then
    echo "Error: no ingress hosts found in network.yml files" >&2
    exit 1
fi

echo "Found ingress hosts:"
echo "$ENTRIES" | while read -r ip host; do
    printf "  %-16s %s\n" "$ip" "$host"
done
echo ""

# ── Build router DNS hosts YAML ──────────────────────────────────────

build_router_block() {
    echo "# Split-horizon DNS: per-host entries managed by homelab-sync-dns.sh"
    echo "# Manual entries above \"# auto-managed below\" are preserved by the sync script."
    echo "router_dns_hosts:"
    # Preserve manually-added entries (lines before the auto-managed marker)
    if grep -q '^router_dns_hosts:' "$ROUTER_VARS"; then
        awk '
            /^router_dns_hosts:/ { capture = 1; next }
            capture && /^  - / && !/# auto-managed/ { print; next }
            capture && /# auto-managed below/ { capture = 0 }
            capture && /^  - / { capture = 0 }
            capture && !/^  - / && !/^$/ && !/^#/ { capture = 0 }
        ' "$ROUTER_VARS"
    fi
    echo "  # auto-managed below"
    while read -r ip host; do
        echo "  - { name: \"${host}\", address: \"${ip}\" }"
    done <<< "$ENTRIES"
}

ROUTER_BLOCK=$(build_router_block)

# ── Apply or preview ─────────────────────────────────────────────────

if $DRY_RUN; then
    echo "Router DNS hosts (would write to $ROUTER_VARS):"
    echo "$ROUTER_BLOCK"
    exit 0
fi

# Update router.yaml: replace or append router_dns_hosts block
if grep -q '^router_dns_hosts:' "$ROUTER_VARS"; then
    awk -v block="$ROUTER_BLOCK" '
        /^# Split-horizon DNS:.*homelab-sync-dns/ { next }
        /^router_dns_hosts:/ {
            print block
            skip = 1
            next
        }
        skip && /^  - / { next }
        skip { skip = 0 }
        { print }
    ' "$ROUTER_VARS" > "$ROUTER_VARS.tmp"
    mv "$ROUTER_VARS.tmp" "$ROUTER_VARS"
else
    printf '\n%s\n' "$ROUTER_BLOCK" >> "$ROUTER_VARS"
fi

echo "Updated $ROUTER_VARS"
echo ""
echo "To apply:"
echo "  cd ansible && ansible-playbook mikrotik-configure.yml"
