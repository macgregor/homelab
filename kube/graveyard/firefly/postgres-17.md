# PostgreSQL 17 for Firefly III

Firefly III used a dedicated PostgreSQL 17 server rather than the PostgreSQL 10 server on port 35432. The Firefly deployment report in this directory records the compatibility findings that led to that choice.

The server was created as a Synology Container Manager project named `postgres-17`, stored at `/volume5/docker/postgres-17`.

Two Container Manager quirks matter when starting the project:

1. The bind-mount source must already exist. Container Manager does not create it automatically.
2. `PGDATA` must not be the project folder itself. DSM writes `docker-compose.yml` into the project folder, so use a `data/` subfolder.

Create `/volume5/docker/postgres-17/data` in File Station before starting the project. No `chown` is needed; the `postgres` entrypoint starts as root and changes `PGDATA` ownership to uid 999.

```yaml
services:
  firefly-postgres:
    image: postgres:17-alpine
    container_name: firefly-postgres
    restart: unless-stopped
    ports:
      - "35433:5432"
    environment:
      POSTGRES_DB: firefly
      POSTGRES_USER: firefly
      POSTGRES_PASSWORD: <FIREFLY_PG_PASSWORD from .envrc>
      TZ: America/New_York
    volumes:
      - /volume5/docker/postgres-17/data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U firefly -d firefly"]
      interval: 30s
      timeout: 5s
      retries: 5
```

`POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` are only read on first start, when the data directory is empty. Changing the password later requires `ALTER USER` inside the container. Pin the image to `postgres:17-alpine`; PostgreSQL 18 changed the data-directory layout.

Back up `/volume5/docker` with Hyper Backup. The `firefly-db-backup` recipe in `justfile` takes an additional logical dump before upgrades. Use `just firefly-debug-pg` to verify connectivity from the cluster.
