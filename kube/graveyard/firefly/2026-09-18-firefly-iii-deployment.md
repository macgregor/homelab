# Research Report: Firefly III on k3s with SimpleFIN Data Import

## Objective

Determine how to run [Firefly III](https://www.firefly-iii.org/) (personal finance manager) on the homelab k3s cluster, internal-network only, with: (1) a storage design that fits the cluster's existing patterns; (2) a resource budget the Raspberry Pi nodes can absorb; (3) automated daily transaction import from the SimpleFIN Bridge accounts already linked to the user's banks.

## Executive Summary

Firefly III is a two-to-three container system, not one: the **core** app (`fireflyiii/core`), an external **database**, and the separately-shipped **data importer** (`fireflyiii/data-importer`). Both official images publish native `arm64` manifests, so they run on the Pi nodes unmodified. Both are built on the `serversideup/php` v3 base (nginx + php-fpm), listen on **port 8080**, and run as the unprivileged **`www-data` user (uid/gid 33:33)**. Critically, serversideup v3 **dropped `PUID`/`PGID` support** — uid can only be changed at image build time — which is the single biggest storage gotcha for this cluster, since every existing app here sets `PUID`/`PGID` to match NFS ownership.

Storage needs are modest and, importantly, **contain no SQLite**. Firefly III keeps everything in the relational database; the only persistent filesystem path is `/var/www/html/storage/upload` (user-uploaded transaction attachments — receipts, statements). That means the cluster's NFS-vs-iSCSI file-locking constraint does not apply, and NFS is a legitimate choice. Database options are MySQL/MariaDB, PostgreSQL, or SQLite; the upstream project recommends against SQLite for anything but trivial use, and the homelab already runs a PostgreSQL instance on the Synology at `192.168.1.200:35432` (used by Mealie). Reuse looked like the lowest-effort option until that server was probed and found to be **PostgreSQL 10.20, EOL since November 2022**; Firefly III instead gets a dedicated `postgres:17-alpine` container on port `35433` (see the database findings below).

SimpleFIN is a **first-class, officially supported provider** in the data importer (no third-party tooling required). The flow is a one-time exchange: a base64-encoded **Setup Token** is decoded to a claim URL and POSTed once to obtain a permanent **Access URL**, which the importer persists into its configuration JSON as the `access_token` field. Because that JSON is self-contained (flow, access URL, account mappings, date window), automated recurring imports work: drop the JSON in a directory on the importer and either POST to `/autoimport` or run `php artisan importer:import <config.json>`. Source review of `app/Console/AutoImports.php` confirms standalone `.json` config files are picked up with no companion data file, and that the `flow` key in the JSON selects the import routine — so `flow: "simplefin"` drives a bank pull, not a file parse.

Two independent scheduled jobs are needed, not one. Firefly III core has its own cron endpoint (`/api/v1/cron/{STATIC_CRON_TOKEN}`) for recurring transactions, bill reminders and auto-budgets; the importer's `/autoimport` is separate. Upstream's compose file runs both as an always-on alpine `crond` sidecar — on Kubernetes these are better expressed as two `CronJob` resources.

## Findings

### Container images and architecture support

- **Source**: Docker Hub registry manifests (queried directly, 2026-09-18)
  **URL**: https://hub.docker.com/r/fireflyiii/core
  **Key points**:
    - `fireflyiii/core:latest` — multi-arch `amd64` + `arm64`, ~340 MB compressed arm64 layer, pushed 2026-09-18 (actively maintained)
    - `fireflyiii/data-importer:latest` — multi-arch `amd64` + `arm64`, ~269 MB arm64, pushed 2026-07-22
    - Both images: `User: www-data`, `ExposedPorts: 8080/tcp, 8443/tcp, 9000/tcp`, `WorkingDir: /var/www/html`
    - Core image ships PHP 8.5.10, entrypoint `docker-php-serversideup-entrypoint`, cmd `/init`
    - No `arm/v7` manifest — 64-bit OS required. The cluster's Rocky Linux 9 aarch64 nodes qualify.

- **Source**: Baked-in PHP defaults read from the arm64 image config blob
  **Key points**:
    - `PHP_MEMORY_LIMIT=256M` (per php-fpm worker)
    - `PHP_FPM_PM_CONTROL=ondemand`, `PHP_FPM_PM_MAX_CHILDREN=20`, `PHP_FPM_PM_START_SERVERS=2`, `PHP_FPM_PM_MIN_SPARE_SERVERS=1`, `PHP_FPM_PM_MAX_SPARE_SERVERS=3`
    - `PHP_OPCACHE_ENABLE=1`, `PHP_OPCACHE_MEMORY_CONSUMPTION=128`, `PHP_OPCACHE_JIT=off`
    - `PHP_UPLOAD_MAX_FILE_SIZE=100M`, `PHP_POST_MAX_SIZE=100M`, `PHP_MAX_EXECUTION_TIME=300`
    - Sizing implication: `ondemand` means idle memory is low (opcache ~128 MB + a couple of workers), but the *worst case* is `max_children × memory_limit` = 20 × 256M. On a shared Pi node that ceiling should be lowered explicitly via `PHP_FPM_PM_MAX_CHILDREN`.

- **Source**: Firefly III Docker FAQ
  **URL**: https://docs.firefly-iii.org/references/faq/docker/
  **Key points**:
    - Recommends starting the container with `PHP_MEMORY_LIMIT=512M` or more (higher than the image default of 256M)
    - Warns that the database image in the stock `docker-compose.yml` (`mariadb:lts`) may not publish the same architectures as the Firefly III image — a known ARM stumbling block. Not relevant if an external database is used.

### File permissions: the `serversideup/php` v3 uid problem

- **Source**: serversideup/php — Understanding File Permissions
  **URL**: https://serversideup.net/open-source/docker-php/docs/guide/understanding-file-permissions
  **Key points**:
    - All v3 images run as `www-data`: **33:33 on Debian**, 82:82 on Alpine. Firefly III uses the Debian variant.
    - **`PUID`/`PGID` were deliberately removed in v3** because honouring them requires a privileged (root) container. Setting them on a v3 image is silently ignored.
    - The replacement is a build-time script, `docker-php-serversideup-set-id www-data <uid>:<gid>`, plus `docker-php-serversideup-set-file-permissions` — i.e. you must build a derived image to change the uid.
    - Pinning `-v2.2.1` on the base image restores v2 behaviour, but Firefly III does not publish such tags.
  **Consequence for this cluster**: every other app here (Mealie `PUID=666`, the arr suite, etc.) adapts the container to the NFS share's ownership. Firefly III cannot. The share must instead be adapted to the container — `chown 33:33` on the Synology path, or a volume type where Kubernetes can set ownership itself.

- **Relevant Kubernetes behaviour**: `securityContext.fsGroup` only takes effect on volume plugins that support ownership management. The in-tree **NFS plugin does not**, so `fsGroup: 33` on an NFS PV is a no-op. It **does** work on **iSCSI** PVs, because Kubernetes owns the formatted ext4 filesystem and chowns the mount. This is the deciding factor between the two storage patterns for the upload volume.

### Storage requirements

- **Source**: Official `docker-compose.yml` / `docker-compose-importer.yml`
  **URL**: https://github.com/firefly-iii/docker
  **Key points**:
    - The **core** container declares exactly one volume: `firefly_iii_upload:/var/www/html/storage/upload`. Nothing else is persisted outside the database.
    - The **database** container persists `/var/lib/mysql` — not needed when using an external DB server.
    - The **importer** container declares **no volume by default**. A `/import` mount is commented out and only needed for directory-based (automated) imports.
    - The **cron** container is a bare `alpine` running `crond`, holding no state.
  **Consequence**: Firefly III stores **no SQLite database**. The homelab's documented "SQLite needs iSCSI for POSIX locking" rule (which forced Jellyfin and the arr apps off NFS) does not apply here. The upload volume is write-rarely, read-rarely attachment blobs.

- **Sizing**: the upload volume grows only with attachments the user manually adds to transactions. A few hundred MB is generous for years of receipts; the database itself is the larger artifact and lives on the Synology.

### Database options

- **Source**: Firefly III `.env.example`
  **URL**: https://raw.githubusercontent.com/firefly-iii/firefly-iii/main/.env.example
  **Key points**:
    - `DB_CONNECTION=mysql` by default; `pgsql` and `sqlite` are the alternatives
    - Connection vars: `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`, `DB_SOCKET`
    - `APP_KEY` must be **exactly 32 characters**
    - `STATIC_CRON_TOKEN` must be **exactly 32 characters**
    - Other notable vars: `SITE_OWNER`, `APP_URL`, `TZ`, `TRUSTED_PROXIES`, `DEFAULT_LANGUAGE`, `APP_ENV=production`, `APP_DEBUG=false`, `CACHE_STORE=file`, `SESSION_DRIVER=file`, `AUTHENTICATION_GUARD=web`, `DISABLE_FRAME_HEADER`, `LOG_CHANNEL=stack`, `APP_LOG_LEVEL=notice`
    - Schema migrations run automatically on container start; the DB user needs DDL rights on its own database.

- **Existing homelab capacity** (verified 2026-09-18): a PostgreSQL server is reachable at `192.168.1.200:35432` on the Synology and already backs Mealie (`MEALIE_PG_*` in `.envrc`, with a separate `MEALIE_PG_ADMIN_USER` used by the `mealie-debug-pg` just recipe). The `k3s` datastore MariaDB on the same NAS is deliberately tuned for *low write throughput and reduced disk noise* (see `docs/03-persistence.md`) and is a poor co-tenant for an application schema.

- **That server turned out to be unusable for Firefly III** (probed 2026-09-18 with the Mealie credentials):
    ```
    version = PostgreSQL 10.20 on x86_64-pc-linux-musl
    me   = mealie   super=false createdb=false createrole=false
    role = postgres super=true  createdb=true
    databases: postgres, template0, template1, odoo, mealie
    ```
    - **PostgreSQL 10.20 reached end of life in November 2022** — unpatched for roughly four years.
    - Firefly III publishes no database version floor of its own. Its constraint is inherited: `composer.json` requires `laravel/framework: ^13`, and the Laravel 13 docs list first-party support as "PostgreSQL 10.0+" — so 10.20 sits *exactly* on the supported floor rather than being outright incompatible.
    - Nothing current is tested there, though: upstream's own compose file provisions PostgreSQL 18, and the TrueNAS package offers only 17/18 and refuses to start on older releases.
    - The `musl` build string shows this is an Alpine **container** in Container Manager, not a DSM package, so "upgrade it" would mean a `pg_dump`/restore of Mealie *and* Odoo across seven major versions.
    - The `mealie` role also lacks `CREATEDB`, so provisioning a `firefly` database there would have needed the `postgres` superuser password, which is not recorded in `.envrc`.
    - **Resolution:** Firefly III gets its own `postgres:17-alpine` container on port `35433`, leaving the 35432 container untouched. It self-provisions its database and role from `POSTGRES_*` on first start, so no superuser step is required. See [PostgreSQL 17 for Firefly III](postgres-17.md).

### SimpleFIN import — official support and token flow

- **Source**: Firefly III documentation — How to use SimpleFIN / Import from SimpleFIN
  **URL**: https://docs.firefly-iii.org/how-to/data-importer/import/simplefin/ , https://docs.firefly-iii.org/tutorials/data-importer/simplefin/
  **Key points**:
    - SimpleFIN is an officially supported provider in the data importer, targeting North American institutions
    - Configured in the UI, or non-interactively via the `SIMPLEFIN_TOKEN` environment variable
    - During account selection you choose which SimpleFIN accounts to import, and Firefly III asset accounts can be auto-created if they don't exist
    - The importer is a *separate application* from Firefly III by design (security/maintenance separation); it talks to Firefly III over the REST API

- **Source**: Data importer source — `app/Services/Shared/Configuration/Configuration.php` (read directly)
  **URL**: https://github.com/firefly-iii/data-importer
  **Key points**:
    - Two-phase auth: a base64-encoded **Setup Token** decodes to a claim URL; `SimpleFINService` POSTs it once to exchange for a **permanent Access URL**, stored on the Configuration object as `$accessToken` and serialised to the config JSON as **`access_token`**
    - The config JSON also carries `flow`, `accounts` (SimpleFIN account id → Firefly asset account id mapping), `new_accounts`, `date_not_before`, `date_not_after`, `identifier`
    - Account fetch uses `balances-only=1`; transaction fetch passes `start-date` / `end-date` and an optional `pending` flag
    - Duplicate suppression is handled by generating an `external_id` and `internal_reference` per transaction, so overlapping date windows on repeated runs do not create duplicates
  **Consequence**: a downloaded config JSON is fully self-contained and replayable — which is what makes unattended daily imports possible. It also means **the JSON contains a live bank-data credential** and must be handled as a secret, not committed to git.

- **Source**: Data importer `.env.example` (read directly)
  **Key points** — SimpleFIN tuning knobs available:
    - `SIMPLEFIN_TOKEN`, `SIMPLEFIN_DEMO_URL`, `SIMPLEFIN_DEMO_TOKEN`
    - `SIMPLEFIN_CONNECTION_TIMEOUT=30`, `SIMPLEFIN_REQUEST_TIMEOUT=60`, `SIMPLEFIN_RETRY_ATTEMPTS=3`, `SIMPLEFIN_RETRY_DELAY`
    - `SIMPLEFIN_MAX_TRANSACTIONS=10000`, `SIMPLEFIN_DEFAULT_DATE_RANGE=90` (days), `SIMPLEFIN_ENABLE_CACHING=true`, `SIMPLEFIN_CACHE_DURATION=3600`
    - Heuristics, on by default: `SIMPLEFIN_SMART_EXPENSE_MATCHING=true` / `SIMPLEFIN_EXPENSE_MATCHING_THRESHOLD=0.7`, `SIMPLEFIN_AUTO_CREATE_EXPENSE_ACCOUNTS=true`, `SIMPLEFIN_ENABLE_TRANSACTION_CLUSTERING=true` / `SIMPLEFIN_CLUSTERING_SIMILARITY_THRESHOLD=0.7`
    - Importer → Firefly III auth: `FIREFLY_III_URL`, `FIREFLY_III_ACCESS_TOKEN` (Personal Access Token), optional `VANITY_URL` for the browser-facing URL when it differs from the in-cluster URL
    - Also: `TRUSTED_PROXIES`, `EXPECT_SECURE_URL`

- **Known issue**: a recurring support thread, ["SimpleFIN bridge URL not found in session"](https://github.com/orgs/firefly-iii/discussions/10599), affects UI setup — the maintainer notes that with the demo token both values must be supplied, and that the resolved access URL is in the downloadable config file. Reinforces the "run the UI once, save the config JSON" approach.

- **Third-party alternative** (not recommended, noted for completeness): [helpcomp/firefly-iii-simplefin-importer](https://github.com/helpcomp/firefly-iii-simplefin-importer) — standalone SimpleFIN→Firefly importer with optional OpenAI transaction categorisation and a Prometheus exporter. Only interesting for those two extras; the official importer covers the core need.

### Automating the import

- **Source**: How to automate the import / How to import using POST
  **URL**: https://docs.firefly-iii.org/how-to/data-importer/import/automated/ , https://docs.firefly-iii.org/how-to/data-importer/advanced/post/
  **Key points**:
    - Auto-import endpoints are **disabled by default** and each must be enabled individually:
      - `AUTO_IMPORT_SECRET` — required, **minimum 16 characters**
      - `CAN_POST_AUTOIMPORT=true` — enables `/autoimport` (directory-based)
      - `CAN_POST_FILES=true` — enables `/autoupload` (upload file + config)
      - `IMPORT_DIR_ALLOWLIST=/import` — directory the importer may read from; subdirectories are implicitly allowed
      - `FALLBACK_IN_DIR=true` + `_fallback.json` — shared config for files lacking a companion JSON
    - `AUTO_IMPORT_SECRET` and `IMPORT_DIR_ALLOWLIST` both support the `_FILE` suffix convention for reading from a file (Docker/Kubernetes secrets)
    - Trigger form: `POST https://importer/autoimport?directory=/import&secret=<AUTO_IMPORT_SECRET>`
    - CLI equivalent, no HTTP needed: `php artisan importer:import /import/<config>.json`
    - Upstream's example crontab runs the two jobs at different times:
      `40 2 * * *` importer `/autoimport`, then `0 3 * * *` Firefly core `/api/v1/cron/$STATIC_CRON_TOKEN`
    - Renaming note: `IMPORT_DIR_ALLOWLIST` was previously `IMPORT_DIR_WHITELIST`

- **Source**: Data importer source — `app/Console/AutoImports.php` and `app/Console/Commands/Import.php` (read directly)
  **Key points**:
    - The directory scan collects two sets: importable files *with* a companion JSON, **and standalone `.json` files**, which are added to the import list on their own (`"Add JSON file to the list of things to import"`). This is what makes a data-file-less SimpleFIN import work.
    - `importFileAsImportJob()` reads `$json['flow'] ?? 'file'` from the config and sets it on the import job — carrying an in-code comment acknowledging this is a workaround for the normally-interactive flow selection. Functional, but flagged by upstream as a hack, so treat it as a place that could shift between releases.
    - `Import.php` validates the config path against `IMPORT_DIR_ALLOWLIST` and returns distinct exit codes: `NO_CONNECTION`, `INVALID_PATH`, `CANNOT_READ_CONFIG`, `CANNOT_PARSE_CONFIG`, `GENERAL_ERROR`, `NOTHING_WAS_IMPORTED`, `SUCCESS` — usable as CronJob success/failure signals.
  **Caveat**: a `NOTHING_WAS_IMPORTED` exit code on a quiet day is a normal outcome, not a failure, and should not be allowed to mark a CronJob unhealthy.

- **Known issue**: [Data Importer loses Secrets from Variables after clicking "Start over"](https://github.com/firefly-iii/firefly-iii/issues/10099) — after using "Start over" in the UI, `/autoimport` can begin logging `Bad secret, not allowed to import.` until the container is restarted. Worth knowing before debugging a broken CronJob.

- **Multi-user caveat**: the `AUTO_IMPORT_SECRET` authenticates *to* the importer and is not user-specific, but the Firefly III Personal Access Token is. A multi-user importer deployment cannot use POST-import or the CLI at all. Single-user here, so not a constraint.

### Firefly III's own cron (separate from importing)

- Firefly III core needs a periodic hit on `GET /api/v1/cron/{STATIC_CRON_TOKEN}` to fire recurring transactions, bill reminders, and auto-budget rollover. Without it, those features silently never run.
- `STATIC_CRON_TOKEN` must be **exactly 32 characters**.
- Upstream implements this as an always-on `alpine` + `crond` container purely because compose has no scheduler. On Kubernetes this is redundant — a `CronJob` with a small curl image is the direct equivalent and costs nothing when idle.

### Cluster capacity (measured 2026-09-18)

| Node | Role | CPU alloc | Mem alloc | Mem requested | Mem in use | CPU in use |
|------|------|-----------|-----------|---------------|------------|------------|
| `k3-m1` | control-plane | 4 | 3936 Mi | 915 Mi (23%) | 2282 Mi (59%) | 429 m (10%) |
| `k3-n1` | worker | 4 | 8050 Mi | 2264 Mi (28%) | 3551 Mi (45%) | 279 m (6%) |

- `k3-n1` has roughly **4.4 GB of unused RAM** and is 94% CPU-idle. A Firefly III stack sized at ~400 Mi of requests is comfortably absorbed with no need to displace anything.
- Both nodes are `v1.33.1+k3s1` on Rocky Linux 9.8 aarch64.
- MetalLB allocations in use: `.220`, `.221` (ingress controllers), `.224`–`.233`. Firefly III needs no LoadBalancer IP — the internal ingress controller at `192.168.1.221` already fronts internal-only services.
- iSCSI LUNs 1–6 are assigned (`docs/03-persistence.md`); LUN 7 is the next free ID if a block volume is chosen.

## Sources

- [Firefly III — Docker FAQ](https://docs.firefly-iii.org/references/faq/docker/)
- [Firefly III — Using Docker (installation)](https://docs.firefly-iii.org/how-to/firefly-iii/installation/docker/)
- [Firefly III — How to use SimpleFIN](https://docs.firefly-iii.org/how-to/data-importer/import/simplefin/)
- [Firefly III — Import from SimpleFIN (tutorial)](https://docs.firefly-iii.org/tutorials/data-importer/simplefin/)
- [Firefly III — How to automate the import](https://docs.firefly-iii.org/how-to/data-importer/import/automated/)
- [Firefly III — How to import using POST](https://docs.firefly-iii.org/how-to/data-importer/advanced/post/)
- [Firefly III — Data importer, about](https://docs.firefly-iii.org/explanation/data-importer/introduction/)
- [firefly-iii/docker — compose files](https://github.com/firefly-iii/docker)
- [firefly-iii/data-importer — source](https://github.com/firefly-iii/data-importer)
- [SimpleFIN Import — DeepWiki walkthrough of the importer source](https://deepwiki.com/firefly-iii/data-importer/3.4-simplefin-import)
- [Data importer: SimpleFIN — original feature request](https://github.com/firefly-iii/firefly-iii/issues/5396)
- [Discussion #10599 — "SimpleFIN bridge URL not found in session"](https://github.com/orgs/firefly-iii/discussions/10599)
- [Issue #10099 — importer loses secret after "Start over"](https://github.com/firefly-iii/firefly-iii/issues/10099)
- [Discussion #12054 — automatic imports in a multi-user configuration](https://github.com/orgs/firefly-iii/discussions/12054)
- [serversideup/php — Understanding File Permissions](https://serversideup.net/open-source/docker-php/docs/guide/understanding-file-permissions)
- [serversideup/php — Migrating from v2 to v3](https://serversideup.net/open-source/docker-php/docs/guide/migrating-from-v2-to-v3)
- [helpcomp/firefly-iii-simplefin-importer — third-party alternative](https://github.com/helpcomp/firefly-iii-simplefin-importer)
- [fireflyiii/core on Docker Hub](https://hub.docker.com/r/fireflyiii/core)

## Metadata

- **Date**: 2026-09-18
- **Cluster state verified against**: k3s `v1.33.1+k3s1`, nodes `k3-m1` / `k3-n1`
- **Image digests at time of research**: `fireflyiii/core:latest` `sha256:ce60c4b9…`, `fireflyiii/data-importer:latest` `sha256:26459e1f…`
- **Method**: upstream documentation, direct reads of data-importer source on `main`, and direct queries against the Docker Hub registry API for per-architecture image configs
