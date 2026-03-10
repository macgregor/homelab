#!/usr/bin/env bash
#
# Sync split-horizon DNS records from local Kubernetes ingress definitions.
#
# Scans network.yml files in kube/{sys,app,media,observation}/ for Ingress
# resources, maps ingressClassName to LoadBalancer IPs, and updates:
#   - CoreDNS hosts block in kube/sys/coredns/coredns.yml
#   - Router static DNS list in ansible/inventory/group_vars/router.yaml
#
# Does not touch the cluster or router. Apply changes with:
#   cd kube && just coredns-deploy
#   cd ansible && ansible-playbook mikrotik-configure.yml
#
# Usage:
#   ./scripts/homelab-sync-dns.sh [--dry-run]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COREDNS_FILE="$REPO_ROOT/kube/sys/coredns/coredns.yml"
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

# ── Build CoreDNS hosts block ────────────────────────────────────────

# Group hostnames by IP, one line per IP with an alias prefix.
build_coredns_block() {
    local prev_ip=""
    local hosts=""

    while read -r ip host; do
        if [[ "$ip" != "$prev_ip" && -n "$prev_ip" ]]; then
            emit_coredns_line "$prev_ip" "$hosts"
            hosts=""
        fi
        prev_ip="$ip"
        hosts="$hosts $host"
    done <<< "$ENTRIES"

    emit_coredns_line "$prev_ip" "$hosts"
}

emit_coredns_line() {
    local ip="$1"
    local hosts="$2"
    local alias=""

    case "$ip" in
        "$EXTERNAL_IP") alias="ext-lb" ;;
        "$INTERNAL_IP") alias="int-lb" ;;
    esac

    # Trim leading space from accumulated hosts
    hosts="${hosts# }"
    echo "    ${ip}${alias:+ $alias} ${hosts}"
}

COREDNS_BLOCK=$(build_coredns_block)

# ── Build router DNS hosts YAML ──────────────────────────────────────

build_router_block() {
    echo "# Split-horizon DNS: per-host entries managed by homelab-sync-dns.sh"
    echo "router_dns_hosts:"
    while read -r ip host; do
        echo "  - { name: \"${host}\", address: \"${ip}\" }"
    done <<< "$ENTRIES"
}

ROUTER_BLOCK=$(build_router_block)

# ── Apply or preview ─────────────────────────────────────────────────

if $DRY_RUN; then
    echo "CoreDNS hosts block (would write to $COREDNS_FILE):"
    echo "    # ingress-hosts-start (managed by homelab-sync-dns.sh)"
    echo "$COREDNS_BLOCK"
    echo "    # ingress-hosts-end"
    echo ""
    echo "Router DNS hosts (would write to $ROUTER_VARS):"
    echo "$ROUTER_BLOCK"
    exit 0
fi

# Update CoreDNS: replace content between markers
MARKER_START="# ingress-hosts-start"
MARKER_END="# ingress-hosts-end"

if ! grep -q "$MARKER_START" "$COREDNS_FILE"; then
    echo "Error: marker '$MARKER_START' not found in $COREDNS_FILE" >&2
    exit 1
fi

awk -v start="$MARKER_START" -v end="$MARKER_END" -v block="$COREDNS_BLOCK" '
    $0 ~ start {
        print "    " start " (managed by homelab-sync-dns.sh)"
        print block
        skip = 1
        next
    }
    $0 ~ end {
        print "    " end
        skip = 0
        next
    }
    !skip { print }
' "$COREDNS_FILE" > "$COREDNS_FILE.tmp"
mv "$COREDNS_FILE.tmp" "$COREDNS_FILE"

echo "Updated $COREDNS_FILE"

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
echo "  cd kube && just coredns-deploy"
echo "  cd ansible && ansible-playbook mikrotik-configure.yml"
