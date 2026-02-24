# Configure auto-update schedulers (packages and firmware)
#
# Idempotent: removes and recreates schedulers to ensure current version.
# Logs all actions. Safe to run multiple times.
#
# Requires auto-update-packages.rsc and auto-update-firmware.rsc in router storage
# (uploaded alongside this script by mikrotik-configure.yml).

/log info "configure: setting up auto-update schedulers"

:do {
    /system scheduler remove [find name=auto-update-packages]
    /log debug "configure: removed existing auto-update-packages scheduler"
} on-error={ /log debug "configure: no existing auto-update-packages scheduler to remove" }

:do {
    /system scheduler add name=auto-update-packages on-event="/import file-name=auto-update-packages.rsc" start-time=04:00:00 interval=1d
    /log debug "configure: created auto-update-packages scheduler"
} on-error={
    /log error "configure: FAILED to create auto-update-packages scheduler — device-mode may not allow scheduler. Run: /system device-mode update mode=advanced then press reset button within 5 minutes"
}

:do {
    /system scheduler remove [find name=auto-update-firmware]
    /log debug "configure: removed existing auto-update-firmware scheduler"
} on-error={ /log debug "configure: no existing auto-update-firmware scheduler to remove" }

# Scheduled 30 minutes after packages: if package update reboots router (~5 min),
# router is back before 04:30 and firmware check runs as expected.
:do {
    /system scheduler add name=auto-update-firmware on-event="/import file-name=auto-update-firmware.rsc" start-time=04:30:00 interval=1d
    /log debug "configure: created auto-update-firmware scheduler"
} on-error={
    /log error "configure: FAILED to create auto-update-firmware scheduler — device-mode may not allow scheduler. Run: /system device-mode update mode=advanced then press reset button within 5 minutes"
}

/system routerboard settings set auto-upgrade=yes
/log debug "configure: enabled auto-upgrade"

/log info "configure: auto-update setup complete"
