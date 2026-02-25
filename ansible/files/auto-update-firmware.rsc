# Auto-update firmware: check and stage routerboard firmware upgrade
#
# Runs daily via scheduler at 04:30. Safe to run manually:
#   /import file-name=auto-update-firmware.rsc
#
# Scheduled 30 minutes after package updates. If a package update reboots the router
# (~5 min), it will be back up well before 04:30.
#
# If a firmware upgrade is staged, the router reboots to apply it. The reboot is
# delayed 1 minute to allow the script to finish logging.

/log info "auto-update-firmware: starting"

:local rbfw [/system routerboard get upgrade-firmware]
:local rbcur [/system routerboard get current-firmware]
/log info ("auto-update-firmware: current=" . $rbcur . " available=" . $rbfw)

:if ($rbfw = "") do={
    /log info "auto-update-firmware: no upgrade available or check not yet run"
} else={
    :if ($rbfw != $rbcur) do={
        /log info "auto-update-firmware: staging upgrade"
        :onerror e in={
            /system routerboard upgrade
            /log info "auto-update-firmware: upgrade staged, rebooting in 1 minute"
            :delay 60
            /system reboot
        } do={
            /log error ("auto-update-firmware: upgrade staging failed: " . $e)
        }
    } else={
        /log info "auto-update-firmware: firmware up-to-date"
    }
}

/log info "auto-update-firmware: complete"
