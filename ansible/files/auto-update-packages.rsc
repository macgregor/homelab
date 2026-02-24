# Auto-update packages: check and install RouterOS package updates
#
# Runs daily via scheduler at 04:00. Safe to run manually:
#   /import file-name=auto-update-packages.rsc
#
# Note: package install triggers a router reboot.
# Firmware updates run separately at 04:30 (auto-update-firmware.rsc).

/log info "auto-update-packages: starting"

:onerror e in={
    /system package update set channel=stable
    /system package update check-for-updates once
    # check-for-updates is async; delay is a blind wait for the background request to finish.
    # If the connection is slow this may read a stale status. No reliable polling mechanism
    # without knowing the exact transitional status string RouterOS uses during the check.
    :delay 30
    :local status [/system package update get status]
    /log debug ("auto-update-packages: status=" . $status)
    :if ($status = "New version is available") do={
        /log info "auto-update-packages: installing update (reboot follows)"
        /system package update install
    }
} do={ /log warning ("auto-update-packages: package update check failed: " . $e) }

/log info "auto-update-packages: complete"
