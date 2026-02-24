# Auto-update firmware: check and stage routerboard firmware upgrade
#
# Runs daily via scheduler at 04:30. Safe to run manually:
#   /import file-name=auto-update-firmware.rsc
#
# Scheduled 30 minutes after package updates. If a package update reboots the router
# (~5 min), it will be back up well before 04:30.
#
# Firmware is staged here but applies on the next reboot (auto-upgrade=yes ensures this).

/log info "auto-update-firmware: starting"

:local rbfw [/system routerboard get upgrade-firmware]
:local rbcur [/system routerboard get current-firmware]
/log info ("auto-update-firmware: current=" . $rbcur . " available=" . $rbfw)

:if ($rbfw = "") do={
    /log info "auto-update-firmware: no upgrade available or check not yet run"
} else={
    :if ($rbfw != $rbcur) do={
        /log info "auto-update-firmware: staging upgrade (applies on next reboot)"
        :do {
            /system routerboard upgrade
            /log info "auto-update-firmware: upgrade staged successfully"
        } on-error={
            /log error "auto-update-firmware: upgrade staging failed"
        }
    } else={
        /log info "auto-update-firmware: firmware up-to-date"
    }
}

/log info "auto-update-firmware: complete"
