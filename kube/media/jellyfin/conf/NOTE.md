These are advanced settings not exposed by the admin UI. Currently my workflow is to stop jellyfin, download these files from the NAS volume (jellyfin-config in the Pod), edit them, then upload them back and restart jellyfin. Care should be taken in case these files change over time.

# Logging
https://jellyfin.org/docs/general/administration/troubleshooting#debug-logging

jellyfin-config volume -> logging.json

# Database Locking
https://jellyfin.org/docs/general/administration/troubleshooting#database-locked-errors

jellyfin-config volume -> database.xml

Previously set to `Optimistic` as a workaround for NFS lacking proper POSIX file locking. With the config volume on iSCSI/ext4 block storage, SQLite can use filesystem-level locks correctly and `Default` locking behavior is appropriate.
