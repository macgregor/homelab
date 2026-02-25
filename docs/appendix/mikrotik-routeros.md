---
name: mikrotik-routeros
description: >
  Load this document when working with MikroTik router configuration, RouterOS scripting,
  Ansible automation, firewall rules, DHCP/DNS, or troubleshooting router-level issues.
categories: [infrastructure, networking]
tags: [mikrotik, routeros, ansible, firewall, dhcp, dns, scripting, ssh]
related_docs:
  - docs/01-infrastructure-provisioning.md
  - docs/04-networking.md
complexity: advanced
---

# MikroTik RouterOS Reference

Reference for AI agents working with MikroTik RouterOS 7.x. Covers SSH interaction, RSC scripting, Ansible automation via `community.routeros`, firewall management, and system administration. Not a tutorial — a concise working reference with links to official docs.

**Official documentation root:** https://help.mikrotik.com/docs/spaces/ROS/pages/328059/RouterOS

---

## Table of Contents

1. [Critical Gotchas](#1-critical-gotchas)
2. [SSH and CLI Interaction](#2-ssh-and-cli-interaction)
3. [RouterOS Scripting Language](#3-routeros-scripting-language)
4. [Ansible Automation](#4-ansible-automation)
5. [System Administration](#5-system-administration)
6. [DHCP and DNS](#6-dhcp-and-dns)
7. [Firewall](#7-firewall)
8. [File Operations and /tool fetch](#8-file-operations-and-tool-fetch)
9. [Documentation Links](#9-documentation-links)

---

## 1. Critical Gotchas

### RouterOS is not Linux

RouterOS has its own CLI, scripting language, and filesystem. No Unix commands (`ls`, `cat`, `echo`, `grep`, `sed`). Standard Ansible modules (`shell`, `copy`, `user`, `authorized_key`) and `ansible.netcommon.net_put` do not work. Use `community.routeros.command` for automation and `scp` (delegated to localhost) for file uploads.

### The `+cet512w` username suffix

RouterOS wraps SSH output at 80 characters, corrupting long output and causing Ansible parse failures. Append `+cet512w` to the SSH username to set 512-character width:

```
ansible_user: myuser+cet512w
```

Format: `+cet<width>w`. Other login suffixes: `c` (colors), `t` (auto-detection), `e` (dumb terminal). **Note:** SCP uses the bare username without the suffix.

### Division looks like an IP address

`10/2` is parsed as an IP address. Use spaces or parentheses: `(10 / 2)`.

### No space before `=` in parameters

`from=1` is correct. `from = 1` is a syntax error. Space IS required between separate `key=value` pairs.

### Print numbers are session-only

Numbers from `print` (0, 1, 2...) are temporary. Always use `find` in scripts:

```
# WRONG
/ip firewall filter remove 3

# CORRECT
/ip firewall filter remove [find comment="my rule"]
```

### SSH key import disables password login

Default `password-authentication=yes-if-no-key` means once an SSH key is imported for a user, password login is disabled for that user.

### Device-mode restrictions

Some models ship in `home` mode, which disables `scheduler`, `fetch`, and other features. Switching to `advanced` requires a physical button press or power cycle within 5 minutes of the mode change command — cannot be automated remotely.

### `community.routeros.command` always reports changed

Returns `changed: true` regardless of whether configuration changed. Use `changed_when` to override.

### Router identity restrictions

Identity (hostname) must be alphanumeric + dashes only, max 19 characters. Non-compliant identities cause `network_cli` connection failures.

### `check-for-updates once` is asynchronous

`/system package update check-for-updates once` starts a background HTTP request. Reading status immediately returns stale data. A `:delay 30` (or similar) is required before reading. No reliable polling mechanism exists.

### First login requires manual password change

Factory-default routers force an interactive password change on first SSH login. This cannot be automated — SSH in manually once before running automation.

### Factory default items are named `defconf`

Factory configurations name items with the `defconf` prefix (e.g., DHCP server named `defconf`, firewall rule comments starting `defconf:`).

---

## 2. SSH and CLI Interaction

### Connecting

```bash
ssh user@192.168.1.1                          # Interactive
ssh user+cet512w@192.168.1.1                  # Wide terminal for automation
ssh user@192.168.1.1 '/system identity print' # Non-interactive command
```

### CLI structure

Commands are organized in a hierarchy (`/ip/firewall/filter`). `/` moves to root, `..` moves up, `/command path` executes without changing position.

### General commands at any menu level

| Command | Purpose | Script-safe |
|---------|---------|-------------|
| `add` | Create new item. Returns internal ID. Supports `place-before`, `comment`. | Yes |
| `set` | Modify existing item properties | Yes |
| `remove` | Delete items | Yes |
| `find` | Return internal IDs matching criteria | Yes |
| `get` | Retrieve a property value from an item | Yes |
| `print` | Display items. Assigns temporary session numbers. | Read-only |
| `enable` / `disable` | Toggle item state | Yes |
| `export` | Export configuration as `.rsc` script | Read-only |

### Print parameters

| Parameter | Purpose |
|-----------|---------|
| `where` | Filter: `print where interface="ether1"` |
| `count-only` | Return count only |
| `detail` | Property=value format |
| `terse` | Compact machine-friendly format |
| `without-paging` | No screen pause |
| `as-value` | Return as array (for script use) |
| `proplist` | Comma-separated property list to show |

### Referencing items

```
/interface set ether1 mtu=1460                                 # By name
/ip route set [find dst-address="0.0.0.0/0"] gateway=3.3.3.3  # By find (preferred)
/ip firewall filter remove [find comment="my rule"]            # By comment
```

### Safe mode

`Ctrl+X` or `F4` activates safe mode — all changes auto-revert if the session terminates abnormally. TCP timeout 9 minutes, limited to ~100 recent actions.

### SSH server configuration

```
/ip ssh set strong-crypto=yes
/ip ssh set host-key-type=rsa    # or ed25519
```

### SSH key import

1. Upload public key to router filesystem (via SCP)
2. Import: `/user ssh-keys import public-key-file=user.pub user=myuser`

Supported formats: RSA, Ed25519, Ed25519-sk in PEM, PKCS#8, or OpenSSH format.

---

## 3. RouterOS Scripting Language

### Variables and scope

```
:local myVar "value"      # Block-scoped (within { })
:global myVar "value"     # Persists across scripts and scheduler invocations
:set myVar "newvalue"     # Reassign
:set myVar                # Unset (no value = remove)
```

**Scope rules:**
- `:local` visible only within enclosing `{ }` block
- Each terminal line is its own scope — `:local` on one line is invisible on the next
- To access a global from another script, re-declare without value: `:global myVar;`

### Data types

| Type | Example | Notes |
|------|---------|-------|
| `num` | `42`, `0xFF` | 64-bit signed. `[:tonum "23.8"]` returns nil (integers only). |
| `str` | `"hello"` | Escapes: `\"`, `\\`, `\n`, `\r`, `\t`, `\$`, `\_` (space) |
| `ip` / `ip-prefix` | `192.168.1.1` / `192.168.0.0/24` | |
| `time` | `1h30m`, `00:05:00` | |
| `array` | `{1;2;3}`, `{a=1; b=2}` | Semicolons separate. Empty array: `[:toarray ""]` (not `{}`). |
| `nil` | | Result of failed conversion |

**Type checking:** `:typeof $var`. **Conversion:** `:tostr`, `:tonum`, `:toip`, `:toarray`, `:tobool`, `:totime`, `:toid`.

### Operators

**String concatenation** uses `.` (dot):

```
:put ("hello" . " " . "world")
```

**Variable substitution in strings:**

```
:put "Hello $myVar"                        # Variable
:put "Result: $($a + $b)"                 # Expression
:put "Routes: $[ :len [/ip route find] ]"  # Command
```

**Array-to-string pitfall:** `.` on an array operates per-element. Convert first: `[:tostr $array]`.

**Array access** uses `->`: `$arr->0` (index), `$assoc->"key"` (key), `:set ($arr->2) "new"` (modify).

**Regex match:** `~` operator: `/ip route print where gateway~"^[0-9]"`

### Control flow

```
:if ($a = true) do={ :put "yes" } else={ :put "no" }
:for i from=1 to=10 step=1 do={ :put $i }
:foreach k,v in=$myArray do={ :put "$k=$v" }
:while ($count < 10) do={ :set count ($count + 1) }
:do { :put "once" } while=($x < 0)
```

### Error handling

```
# Legacy (all versions)
:do { /ip address add address=10.0.0.1/24 interface=ether1
} on-error={ :log warning "add failed" }

# Modern (v7.16+)
:onerror e in={ :resolve www.example.com
} do={ :put "resolver failed: $e" }
```

### Functions

Functions are global variables with `do={}` blocks:

```
:global myFunc do={ :return ($1 + $2) }
:put [$myFunc 3 4]       # 7

# Named parameters
:global myFunc do={ :return ($a + $b) }
:put [$myFunc a=3 b=4]   # 7
```

**Nested function gotcha:** A function calling another must re-declare the global:

```
:global helper do={ :return 5 }
:global main do={
    :global helper;         # MUST re-declare
    :return ([$helper] + 1)
}
```

### Import and export

```
/import file-name=myscript.rsc
/import file-name=myscript.rsc verbose=yes dry-run    # dry-run REQUIRES verbose
/export file=backup.rsc
```

Export does NOT include passwords, certificates, or SSH keys.

### Logging

`:log info "msg"`, `:log warning "msg"`, `:log error "msg"`, `:log debug "msg"`

### Additional scripting pitfalls

- **`find` type mismatch:** Use `:tostr` or quote values: `where address="1.1.1.1/24"`
- **`print as-value` returns 2D:** Use `[:pick ... 0]` before accessing properties
- **Variable naming:** Avoid names matching built-in properties (`type`, `name`, `address`)
- **Script policies:** Scheduler policies must include all policies the script requires (e.g., `read,write,ftp` for fetch)
- **Line continuation `\`:** Cannot carry a comment on the same line

---

## 4. Ansible Automation

### Connection setup

Required connection settings:

```yaml
ansible_connection: ansible.netcommon.network_cli
ansible_network_os: community.routeros.routeros
ansible_become: no    # RouterOS has no privilege escalation
```

The `+cet512w` suffix (see [Critical Gotchas](#the-cet512w-username-suffix)) should be applied to `ansible_user` for `network_cli` sessions but NOT for SCP operations.

**Dependencies:** `ansible-pylibssh` (pip), `ansible.netcommon` and `community.routeros` collections.

### The command module

```yaml
- name: Set system identity
  community.routeros.command:
    commands:
      - /system identity set name=myrouter
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `commands` | list | required | Commands to send (must start with `/`) |
| `wait_for` | list | -- | Conditions against output (e.g., `result[0] contains MikroTik`) |
| `match` | `all`/`any` | `all` | Whether all or any wait_for conditions must pass |
| `retries` | int | 10 | Retry attempts |
| `interval` | int | 1 | Seconds between retries |

**Limitations:** No check mode, no diff mode, not inherently idempotent. Commands must start with `/`.

### Inline RouterOS scripting in Ansible

For conditional logic, embed RouterOS scripting inline:

```yaml
- name: Add NTP server if not present
  community.routeros.command:
    commands:
      - >-
        :if ([:len [/system ntp client servers find address=time.cloudflare.com]] = 0)
        do={ /system ntp client servers add address=time.cloudflare.com }
```

### Idempotency patterns

RouterOS has no native "ensure state" for most objects. Two patterns:

**Check-then-act (inline scripting):**

```yaml
- name: Ensure static lease exists with correct IP
  community.routeros.command:
    commands:
      - >-
        :if ([:len [/ip dhcp-server lease find mac-address=AA:BB:CC:DD:EE:FF
        address=192.168.1.100]] = 0) do={
        /ip dhcp-server lease remove [find mac-address=AA:BB:CC:DD:EE:FF];
        /ip dhcp-server lease add address=192.168.1.100
        mac-address=AA:BB:CC:DD:EE:FF server=dhcp-lan comment="my-host"
        }
```

**Remove-then-add:**

```yaml
- name: Remove existing pool
  community.routeros.command:
    commands:
      - /ip pool remove [find name=dhcp-pool]
  ignore_errors: true

- name: Create pool
  community.routeros.command:
    commands:
      - /ip pool add name=dhcp-pool ranges=192.168.1.50-192.168.1.199
```

### File upload via SCP

RouterOS does not support standard Ansible file transfer. Use SCP delegated to localhost:

```yaml
- name: Upload file to router
  ansible.builtin.shell: >-
    scp -i {{ ssh_key_path }}
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    {{ local_file }} {{ router_user }}@{{ ansible_host }}:/{{ local_file | basename }}
  delegate_to: localhost
```

For bootstrap (password-based): use `sshpass -e scp` with `SSHPASS` environment variable and `no_log: true`.

### Running and cleaning uploaded scripts

```yaml
- name: Import script
  community.routeros.command:
    commands:
      - /import file-name=myscript.rsc

- name: Remove temp file
  community.routeros.command:
    commands:
      - /file remove myscript.rsc
  ignore_errors: true
```

### Gathering facts

```yaml
- name: Gather facts
  community.routeros.facts:
    gather_subset: all
```

Returns `ansible_net_version`, `ansible_net_hostname`, `ansible_net_model`, `ansible_net_uptime`, `ansible_net_all_ipv4_addresses`, `ansible_net_interfaces`, etc.

### API-based modules

The collection also provides API-based modules (`api`, `api_info`, `api_find_and_modify`, `api_modify`) over HTTP/HTTPS (ports 8728/8729). These offer idempotent operations, check mode, and diff mode but require `librouteros` and the API service enabled on the router.

---

## 5. System Administration

### Users and groups

```
/user add name=myuser password=secret group=full
/user remove [find name=admin]
/user set myuser address=192.168.1.0/24    # Restrict login source
```

Default groups: `read` (read-only), `write` (config changes, no user mgmt), `full` (all permissions).

### Service hardening

```
/ip service disable telnet,ftp,api,api-ssl
/ip service set ssh address=192.168.1.0/24
/ip service set winbox address=192.168.1.0/24
```

The `address` restriction is application-level, not network-level. Firewall rules provide stronger enforcement.

### Discovery hardening

```
/tool mac-server ping set enabled=no
/ip neighbor discovery-settings set discover-interface-list=LAN
/tool bandwidth-server set enabled=no
```

### Device mode

| Feature | Home | Basic | Advanced |
|---------|------|-------|----------|
| Scheduler | no | yes | yes |
| Fetch | no | yes | yes |
| Email | no | yes | yes |
| Bandwidth Test | no | no | yes |
| Container | no | no | no (ROSE only) |

Check mode: `/system/device-mode/print`. Change mode: `/system/device-mode/update mode=advanced` (requires physical confirmation — see [Critical Gotchas](#device-mode-restrictions)).

### Scheduler

```
/system scheduler add name=my-task on-event="/import file-name=my-script.rsc" \
    start-time=04:00:00 interval=1d
```

- `start-time=startup` with `interval=0` runs once per boot
- `on-event` accepts a script name (from `/system script`) or inline commands
- Scheduler policies must include all policies the script requires

### System identity, timezone, NTP

```
/system identity set name=myrouter
/system clock set time-zone-name=America/New_York
/system ntp client set enabled=yes
/system ntp client servers add address=time.cloudflare.com
```

### Package and firmware updates

Two separate mechanisms:
1. **RouterOS packages** (`/system package update`) — the operating system
2. **RouterBOARD firmware** (`/system routerboard upgrade`) — the bootloader

```
# Package updates (check-for-updates is async — see Critical Gotchas)
/system package update set channel=stable
/system package update check-for-updates once
:delay 30
:local status [/system package update get status]
:if ($status = "New version is available") do={
    /system package update install    # Triggers reboot
}

# Firmware
/system routerboard print             # Compare current-firmware vs upgrade-firmware
/system routerboard upgrade           # Stage (applies on next reboot)
/system routerboard settings set auto-upgrade=yes   # Auto-upgrade after package updates
```

Release channels: `stable` (recommended), `long-term`, `testing`, `development`.

`/system routerboard upgrade` may prompt in interactive console but executes without prompting in scripts (via `/import` or scheduler).

---

## 6. DHCP and DNS

### DHCP server

Three components: IP pool, DHCP network, DHCP server.

```
/ip pool add name=dhcp-pool ranges=192.168.1.50-192.168.1.199
/ip dhcp-server network add address=192.168.1.0/24 gateway=192.168.1.1 dns-server=192.168.1.1
/ip dhcp-server add name=dhcp-lan interface=bridge address-pool=dhcp-pool disabled=no
```

### Static DHCP leases

```
/ip dhcp-server lease add address=192.168.1.100 mac-address=AA:BB:CC:DD:EE:FF \
    server=dhcp-lan comment="my-host"
/ip dhcp-server lease set [find mac-address=AA:BB:CC:DD:EE:FF] address=192.168.1.100
/ip dhcp-server lease remove [find mac-address=AA:BB:CC:DD:EE:FF]
```

### DNS

```
/ip dns set servers=1.1.1.1
/ip dns set allow-remote-requests=yes          # Router as DNS resolver for LAN
/ip dns static add name=myhost.lan address=192.168.1.10
/ip dns cache flush
```

### Dynamic DNS (DDNS)

**MikroTik Cloud DDNS** (built-in):

```
/ip cloud set ddns-enabled=yes
/ip cloud print    # Shows dns-name: <serial>.sn.mynetname.net
```

**Custom DDNS** (Cloudflare, etc.): Write a script that detects IP changes and calls the provider API via `/tool fetch`, then schedule it. Requires `basic` or `advanced` device mode.

**Cloudflare DDNS example:**

```
:local wanIP [/ip address get [find interface=ether1] address]
:set wanIP [:pick $wanIP 0 [:find $wanIP "/"]]

/tool fetch http-method=put \
    http-header-field="Authorization:Bearer <token>,Content-Type:application/json" \
    http-data=("{\"type\":\"A\",\"name\":\"example.com\",\"content\":\"" . $wanIP . "\"}") \
    url="https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records/<record_id>" \
    mode=https
```

---

## 7. Firewall

### Chains

`input` (to router), `forward` (through router), `output` (from router). Rules evaluated top to bottom, first match wins (except `passthrough`/`log`). Default policy is **accept**.

### Connection tracking

Standard states: `established`, `related`, `new`, `invalid`. Additionally, `untracked` for packets excluded via RAW `notrack`.

**Standard opening rules** (place first in each chain for performance):

```
/ip firewall filter add chain=input connection-state=established,related,untracked action=accept
/ip firewall filter add chain=input connection-state=invalid action=drop
```

### Interface lists

```
/interface list add name=WAN
/interface list member add interface=ether1 list=WAN
```

Used in rules: `in-interface-list=WAN`, `in-interface-list=!LAN` (negation with `!`).

### Filter rules

```
/ip firewall filter add chain=input protocol=icmp action=accept
/ip firewall filter add chain=input in-interface-list=!LAN action=drop
/ip firewall filter add chain=forward connection-state=established,related action=accept
/ip firewall filter add chain=forward connection-nat-state=!dstnat \
    connection-state=new in-interface-list=WAN action=drop \
    comment="defconf: drop all from WAN not DSTNATed"
```

### Rule ordering with `place-before`

```
/ip firewall filter add chain=forward action=accept \
    src-address-list=allowed dst-address=192.168.1.100 dst-port=443 protocol=tcp \
    connection-nat-state=dstnat \
    place-before=[find where comment="defconf: drop all from WAN not DSTNATed"]
```

### NAT

```
# Masquerade (outbound)
/ip firewall nat add chain=srcnat action=masquerade out-interface-list=WAN

# DNAT / port forwarding (inbound)
/ip firewall nat add chain=dstnat action=dst-nat \
    dst-port=443 to-addresses=192.168.1.100 to-ports=443 \
    protocol=tcp in-interface-list=WAN comment="port-forward-https"
```

NAT matches only the first packet of a connection. After changing rules, clear tracking: `/ip firewall connection remove [find]`

### Address lists

```
/ip firewall address-list add list=mylist address=103.21.244.0/22
/ip firewall address-list add list=temp_block address=10.0.0.5 timeout=5m  # RAM only, lost on reboot

# Remove all entries for a list
:foreach entry in=[/ip firewall address-list find list="mylist"] do={
    /ip firewall address-list remove $entry
}

# Use in rules
/ip firewall filter add chain=forward src-address-list=mylist action=accept
```

### FastTrack

Bypasses firewall filter and mangle for established/related connections for higher throughput:

```
/ip firewall filter add chain=forward action=fasttrack-connection \
    connection-state=established,related comment="defconf: fasttrack"
```

### Factory default firewall summary

- **Input:** accept established/related, accept ICMP, drop all not from LAN
- **Forward:** FastTrack established/related, accept established/related, drop invalid, drop WAN inbound not DSTNATed
- **NAT:** masquerade on WAN

New forward-accept rules (e.g., port forwarding) must be placed **before** the "drop all from WAN not DSTNATed" rule using `place-before`.

### Managing rules by comment

```
/ip firewall filter find comment="my rule"
/ip firewall filter remove [find comment="my rule"]

# Remove-then-add for idempotency
:do { /ip firewall nat remove [find comment="my-rule"] } on-error={}
/ip firewall nat add chain=dstnat action=dst-nat ... comment="my-rule"
```

---

## 8. File Operations and /tool fetch

### Downloading files

```
/tool fetch url="https://example.com/data.txt" dst-path="data.txt"

# Capture to variable (64KB limit)
:local result [/tool fetch url="https://example.com/data" as-value output=user]
:local data ($result->"data")
```

### Output modes

| Mode | Description | Size limit |
|------|-------------|------------|
| `file` | Save to filesystem (default) | Filesystem limit |
| `user` | Store in variable | 64KB |
| `user-with-headers` | Include HTTP headers | 64KB total |
| `none` | Discard | -- |

### HTTP methods

```
/tool fetch http-method=post \
    http-header-field="Content-Type:application/json" \
    http-data="{\"key\":\"value\"}" \
    url="https://api.example.com/endpoint"
```

### Reading file contents

```
:local content [/file get [/file find name="data.txt"] contents]
```

Subject to 64KB variable size limit. For larger files, use the `read` command.

### Parsing newline-separated files

RouterOS has no built-in line splitter. Parse with `:find` and `:pick`:

```
:local content [/file get [/file find name="data.txt"] contents]
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
    # Strip trailing \r if present (some files use \r\n)
    :if ([:len $line] > 0 && [:pick $line ([:len $line] - 1)] = "\r") do={
        :set line [:pick $line 0 ([:len $line] - 1)]
    }
    :if ([:len $line] > 0) do={
        # Process $line here
    }
} while ($lastEnd < $contentLen)
```

### File management

```
/file print                            # List files
/file remove myfile.rsc                # Delete
/file print file=myFile               # Create (workaround — no direct creation)
/file set myFile.txt contents="data"   # Write
```

---

## 9. Documentation Links

### RouterOS

| Topic | URL |
|-------|-----|
| RouterOS overview | https://help.mikrotik.com/docs/spaces/ROS/pages/328059/RouterOS |
| CLI | https://help.mikrotik.com/docs/spaces/ROS/pages/328134/Command+Line+Interface |
| Scripting reference | https://help.mikrotik.com/docs/spaces/ROS/pages/47579229/Scripting |
| Scripting tips & tricks | https://help.mikrotik.com/docs/spaces/ROS/pages/283574370/Scripting+Tips+and+Tricks |
| Script examples | https://help.mikrotik.com/docs/spaces/ROS/pages/139067404/Scripting+examples |
| SSH | https://help.mikrotik.com/docs/spaces/ROS/pages/132350014/SSH |
| Firewall overview | https://help.mikrotik.com/docs/spaces/ROS/pages/250708066/Firewall |
| Filter rules | https://help.mikrotik.com/docs/spaces/ROS/pages/48660574/Filter |
| NAT | https://help.mikrotik.com/docs/spaces/ROS/pages/3211299/NAT |
| Address lists | https://help.mikrotik.com/docs/spaces/ROS/pages/130220135/Address-lists |
| Building advanced firewall | https://help.mikrotik.com/docs/spaces/ROS/pages/328513/Building+Advanced+Firewall |
| Common matchers & actions | https://help.mikrotik.com/docs/spaces/ROS/pages/250708064/Common+Firewall+Matchers+and+Actions |
| Fetch | https://help.mikrotik.com/docs/spaces/ROS/pages/8978514/Fetch |
| DHCP | https://help.mikrotik.com/docs/spaces/ROS/pages/24805500/DHCP |
| DNS | https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS |
| Cloud DDNS | https://help.mikrotik.com/docs/spaces/ROS/pages/97779929/Cloud |
| Dynamic DNS | https://help.mikrotik.com/docs/spaces/ROS/pages/139067407/Dynamic+DNS |
| Scheduler | https://help.mikrotik.com/docs/spaces/ROS/pages/40992881/Scheduler |
| Device mode | https://help.mikrotik.com/docs/spaces/ROS/pages/93749258/Device-mode |
| Services | https://help.mikrotik.com/docs/spaces/ROS/pages/103841820/Services |
| User management | https://help.mikrotik.com/docs/spaces/ROS/pages/8978504/User |
| System clock | https://help.mikrotik.com/docs/spaces/ROS/pages/40992866/Clock |
| NTP | https://help.mikrotik.com/docs/spaces/ROS/pages/40992869/NTP |
| Upgrading | https://help.mikrotik.com/docs/spaces/ROS/pages/328142/Upgrading+and+installation |
| RouterBOARD | https://help.mikrotik.com/docs/spaces/ROS/pages/40992878/RouterBOARD |
| Securing your router | https://help.mikrotik.com/docs/spaces/ROS/pages/328353/Securing+your+router |

### Ansible

| Topic | URL |
|-------|-----|
| community.routeros collection | https://docs.ansible.com/projects/ansible/latest/collections/community/routeros/index.html |
| command module | https://docs.ansible.com/projects/ansible/latest/collections/community/routeros/command_module.html |
| facts module | https://docs.ansible.com/projects/ansible/latest/collections/community/routeros/facts_module.html |
| api module | https://docs.ansible.com/projects/ansible/latest/collections/community/routeros/api_module.html |
| api_find_and_modify module | https://docs.ansible.com/projects/ansible/latest/collections/community/routeros/api_find_and_modify_module.html |
| api_modify module | https://docs.ansible.com/projects/ansible/latest/collections/community/routeros/api_modify_module.html |
