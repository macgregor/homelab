# Bootstrap: add 192.168.1.0/24 alongside factory defaults
#
# Idempotent: errors on already-existing resources are caught and logged.
# Logs all actions. Safe to run multiple times.
#
# Does NOT remove factory 192.168.88.0/24 config. Disables defconf DHCP server
# and creates dhcp-lan on 192.168.1.0/24. mikrotik-configure.yml handles all
# remaining configuration.

/log info "bootstrap: starting subnet setup"

:do {
    /ip address add address=192.168.1.1/24 interface=bridge
    /log info "bootstrap: added 192.168.1.1/24"
} on-error={ /log info "bootstrap: 192.168.1.1/24 already present" }

:do {
    /ip pool add name=dhcp-pool ranges=192.168.1.10-192.168.1.254
    /log info "bootstrap: added dhcp-pool"
} on-error={ /log info "bootstrap: dhcp-pool already present" }

:do {
    /ip dhcp-server network add address=192.168.1.0/24 gateway=192.168.1.1 dns-server=192.168.1.1
    /log info "bootstrap: added dhcp-server network 192.168.1.0/24"
} on-error={ /log info "bootstrap: dhcp-server network 192.168.1.0/24 already present" }

:do {
    /ip dhcp-server set defconf disabled=yes
    /log info "bootstrap: disabled defconf"
} on-error={ /log info "bootstrap: defconf not found" }

:do {
    /ip dhcp-server add name=dhcp-lan interface=bridge address-pool=dhcp-pool disabled=no
    /log info "bootstrap: added dhcp-lan"
} on-error={ /log info "bootstrap: dhcp-lan already present" }

/log info "bootstrap: subnet setup complete"
