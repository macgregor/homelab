# Cloudflare firewall: fetch Cloudflare IP ranges and manage firewall rules
#
# Runs every 6 hours via scheduler (plus once at boot). Safe to run manually:
#   /import file-name=cloudflare-firewall.rsc
#
# Maintains:
#   - Address list "cloudflare" with current Cloudflare IPv4 CIDRs
#   - DNAT rule forwarding Cloudflare traffic on port 443 to the external ingress VIP
#   - Forward-accept rule placed before the defconf drop-all anchor
#
# The address list is rebuilt every run. DNAT and forward rules use check-then-create
# (only added if missing) to avoid disrupting connection tracking.

/log info "cloudflare-firewall: starting"

:onerror e in={

    # ── Fetch Cloudflare IP ranges ────────────────────────────────────
    /tool fetch url="https://www.cloudflare.com/ips-v4" dst-path="cloudflare-ips.txt"
    :local content [/file get [/file find name="cloudflare-ips.txt"] contents]

    # ── Parse lines into an array ─────────────────────────────────────
    :local cidrs [:toarray ""]
    :local contentLen [:len $content]
    :local lineEnd 0
    :local line ""
    :local lastEnd 0

    :do {
        :set lineEnd [:find $content "\n" $lastEnd]
        :if ([:typeof $lineEnd] = "nil") do={
            :set line [:pick $content $lastEnd $contentLen]
            :set lastEnd $contentLen
        } else={
            :set line [:pick $content $lastEnd $lineEnd]
            :set lastEnd ($lineEnd + 1)
        }
        # Strip trailing \r if present (HTTP download may produce \r\n)
        :if ([:len $line] > 0 && [:pick $line ([:len $line] - 1)] = "\r") do={
            :set line [:pick $line 0 ([:len $line] - 1)]
        }
        :if ([:len $line] > 0) do={
            :set ($cidrs->[:len $cidrs]) $line
        }
    } while ($lastEnd < $contentLen)

    :local cidrCount [:len $cidrs]
    /log debug ("cloudflare-firewall: parsed " . $cidrCount . " CIDRs")

    # ── Validate ──────────────────────────────────────────────────────
    :if ($cidrCount < 10) do={
        /log warning ("cloudflare-firewall: only " . $cidrCount . " CIDRs parsed (expected >= 10), aborting")
        :error "validation failed"
    }

    # ── Ensure defconf anchor rule exists (before modifying anything) ──
    :local anchorCount [:len [/ip firewall filter find comment="defconf: drop all from WAN not DSTNATed"]]
    :if ($anchorCount = 0) do={
        /log error "cloudflare-firewall: defconf drop-all anchor rule not found, aborting"
        :error "anchor rule missing"
    }

    # ── Rebuild address list (add-then-remove to avoid empty window) ──
    :local oldEntries [/ip firewall address-list find list=cloudflare]
    :foreach cidr in=$cidrs do={
        /ip firewall address-list add list=cloudflare address=$cidr
    }
    :foreach entry in=$oldEntries do={
        /ip firewall address-list remove $entry
    }
    /log info ("cloudflare-firewall: added " . $cidrCount . " entries to address list")

    # ── Ensure DNAT rule ──────────────────────────────────────────────
    :if ([:len [/ip firewall nat find comment="cloudflare-proxy-dnat"]] = 0) do={
        /ip firewall nat add chain=dstnat protocol=tcp dst-port=443 \
            src-address-list=cloudflare in-interface-list=WAN \
            action=dst-nat to-addresses=192.168.1.220 to-ports=443 \
            comment="cloudflare-proxy-dnat"
        /log info "cloudflare-firewall: created DNAT rule"
    }

    # ── Ensure forward-accept rule (before defconf drop-all) ──────────
    :if ([:len [/ip firewall filter find comment="cloudflare-proxy-forward"]] = 0) do={
        /ip firewall filter add chain=forward protocol=tcp \
            connection-nat-state=dstnat src-address-list=cloudflare \
            dst-address=192.168.1.220 dst-port=443 action=accept \
            place-before=[find where comment="defconf: drop all from WAN not DSTNATed"] \
            comment="cloudflare-proxy-forward"
        /log info "cloudflare-firewall: created forward-accept rule"
    }

    # ── Cleanup ───────────────────────────────────────────────────────
    /file remove cloudflare-ips.txt

    /log info "cloudflare-firewall: complete"

} do={
    # "validation failed" and "anchor rule missing" are logged at their source
    :if ($e = "validation failed" || $e = "anchor rule missing") do={} else={
        /log error ("cloudflare-firewall: failed: " . $e)
    }
    :onerror cleanupErr in={
        /file remove cloudflare-ips.txt
    } do={}
}
