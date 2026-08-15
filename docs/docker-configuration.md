# Docker Configuration Reference

This document explains, line by line, the Docker Compose stack that runs Keycloak
for this series. It is the reference companion to the article; the
[README](../README.md) only carries the quick start.

- [Topology](#topology)
- [Prerequisites](#prerequisites)
- [Project layout](#project-layout)
- [Service: `keycloak-database`](#service-keycloak-database)
- [Service: `keycloak`](#service-keycloak)
- [Volumes](#volumes)
- [Networks](#networks)
- [Environment variables](#environment-variables)
- [Everyday commands](#everyday-commands)
- [Development vs. production](#development-vs-production)
- [Troubleshooting](#troubleshooting)

---

## Topology

Two containers on a private bridge network. Keycloak is the only service that
_needs_ to be reachable from the host; PostgreSQL is published as well so you can
inspect the schema with `psql` or a GUI client while writing/following the
articles.

```
                     host
                       │
      :${KEYCLOAK_PORT}│              :${KEYCLOAK_POSTGRES_PORT}
                       ▼                          ▼
        ┌──────────────────────────────────────────────────┐
        │  network: keycloak-network (bridge)              │
        │                                                  │
        │   keycloak-container ──JDBC:5432──▶ keycloak-db-container
        │   quay.io/keycloak/keycloak:26.6    postgres:18   │
        │          │                                │       │
        └──────────┼────────────────────────────────┼───────┘
                   │                                │
        bind mounts (themes, providers)      volume: keycloak-database
```

Keycloak reaches the database at `keycloak-db-container:5432` — the _container
name_, resolved by Docker's embedded DNS on the shared network. That hostname is
independent of `KEYCLOAK_POSTGRES_PORT`, which only affects the host-side
publication.

## Prerequisites

- Docker Engine 20.10+ with the Compose V2 plugin (`docker compose`, not
  `docker-compose`). The file uses the top-level `name:` key and `deploy.resources`
  limits, both of which require a recent Compose.
- Roughly 2.5 GB of RAM free for the stack (see the resource limits below).
- Ports `${KEYCLOAK_PORT}` and `${KEYCLOAK_POSTGRES_PORT}` free on the host.

## Project layout

```
.
├── compose.yml            # the stack described in this document
├── .env                   # your local values (git-ignored)
├── .env.example           # template — copy to .env
├── .data/                 # scratch space for local dumps (git-ignored)
└── keycloak/              # host directory for themes and providers
    ├── themes/            # custom login/account themes, mounted read-only
    │   ├── modern.base/   # token-driven base login theme — see login-theme.md
    │   └── acme/          # example child theme: tokens only, no CSS
    └── providers/         # custom SPI JARs, mounted read-only
```

`compose.yml` declares the project name explicitly:

```yaml
name: keycloak-modern-auth
```

Without it, Compose derives the project name from the directory name, so
containers, the network and the volume would be renamed if you cloned the repo
into a differently-named folder. Pinning it keeps `keycloak-modern-auth_keycloak-database`
stable across machines — which matters, because that is where your realm data
lives.

---

## Service: `keycloak-database`

```yaml
keycloak-database:
  container_name: keycloak-db-container
  image: postgres:18
  restart: unless-stopped
```

Keycloak keeps every realm, client, user and session-persistence record in a
relational database. The default embedded H2 database is explicitly unsupported
for anything but a first look, so we start from PostgreSQL — the same engine
you would run in production.

`restart: unless-stopped` brings the container back after a Docker daemon or
host restart, but respects a deliberate `docker compose stop`.

### Health check

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -d ${KEYCLOAK_POSTGRES_DB} || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s
```

This is the contract that `depends_on: condition: service_healthy` on the
Keycloak service relies on. `pg_isready` returns 0 once the server accepts
connections for the named database.

`start_period: 30s` is the important knob: during the first 30 seconds, failing
probes do **not** count against `retries`. A first boot has to run `initdb`,
create the role and the database, and that easily exceeds a naive 5 × 10 s
budget on a cold volume.

> **Note** — `pg_isready` is invoked without `-U`, so it connects as the
> container's OS user (`postgres`) rather than `${KEYCLOAK_POSTGRES_USER}`. That
> is enough to answer "is the server accepting connections?", which is all the
> dependency gate needs. Add `-U ${KEYCLOAK_POSTGRES_USER}` if you also want the
> probe to prove that the application role can authenticate.

### Environment

```yaml
environment:
  POSTGRES_USER: ${KEYCLOAK_POSTGRES_USER}
  POSTGRES_PASSWORD: ${KEYCLOAK_POSTGRES_PASSWORD}
  POSTGRES_DB: ${KEYCLOAK_POSTGRES_DB}
  POSTGRES_INITDB_ARGS: "-E UTF8 --locale=C"
```

The three `POSTGRES_*` variables are read by the official image's entrypoint
**only on the very first start**, when the data directory is empty. Changing the
password in `.env` later has no effect on an existing volume — you have to
`ALTER ROLE` inside the database or recreate the volume (see
[Troubleshooting](#troubleshooting)).

`POSTGRES_INITDB_ARGS` is passed straight to `initdb`:

- `-E UTF8` — Keycloak stores user attributes, realm display names and
  localized messages; UTF-8 is required, not merely preferred.
- `--locale=C` — byte-order collation. It makes index behaviour deterministic
  and independent of the host locale, and it sidesteps the collation-version
  mismatches that appear when a `glibc` upgrade changes sort order under an
  existing index.

### Ports

```yaml
ports:
  - ${KEYCLOAK_POSTGRES_PORT}:5432
```

Published purely for convenience while following the series:

```bash
psql -h localhost -p ${KEYCLOAK_POSTGRES_PORT} -U keycloak -d keycloak
```

Keycloak itself does not use this mapping — it talks to the container over the
`keycloak-network` bridge. **Remove this block on any shared or public host**;
it exposes the database to everything that can reach your machine.

### Storage and limits

```yaml
volumes:
  - keycloak-database:/var/lib/postgresql
deploy:
  resources:
    limits:
      memory: 512M
    reservations:
      memory: 256M
```

A named volume, not a bind mount — it avoids the file-ownership and
`fsync` behaviour problems that bind-mounted Postgres data directories hit on
macOS and Windows.

`deploy.resources` is honoured by `docker compose up` on modern Compose V2
(it is no longer Swarm-only). `limits` is the hard ceiling — the container is
OOM-killed past it — while `reservations` is a soft scheduling hint. 512 MB is
comfortable for a local realm with a handful of users; raise it before load
testing.

---

## Service: `keycloak`

```yaml
keycloak:
  image: quay.io/keycloak/keycloak:26.6
  container_name: keycloak-container
  command: start-dev --import-realm
  restart: unless-stopped
```

The image is pulled from Quay, which is where the Keycloak project publishes its
official builds. The tag is pinned to a minor version rather than `latest`, so
the stack in the articles stays reproducible.

### The `command`

Keycloak has two start modes:

| Mode        | What it does                                                                                                                                       |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `start-dev` | Development. HTTP enabled, hostname checks relaxed, strict config validation off, no build-time optimization step required.                        |
| `start`     | Production. Requires HTTPS (or an explicit `--http-enabled=true` behind a proxy), a valid hostname configuration, and a pre-built optimized image. |

We use `start-dev` throughout the series and switch to `start` in the deployment
article — see [Development vs. production](#development-vs-production).

`--import-realm` makes Keycloak import every `*.json` realm file found in
`/opt/keycloak/data/import` at startup, which is how you get a reproducible
realm without clicking through the admin console.

> **Note** — `--import-realm` is a no-op unless that directory is populated. The
> current `volumes:` block mounts themes and providers only. To use it, export a
> realm and mount the folder:
>
> ```yaml
> volumes:
>   - ./keycloak/import:/opt/keycloak/data/import:ro
> ```
>
> Import runs on **every** start and is idempotent by default (existing realms
> are skipped, not overwritten).

### Environment, block by block

Every Keycloak setting can be given as an environment variable: the CLI option
`--db-url` becomes `KC_DB_URL`. That mapping is mechanical — uppercase, prefix
with `KC_`, replace `-` with `_` — and is worth remembering when reading the
upstream docs, which are written in CLI-option form.

**Database**

```yaml
KC_DB: postgres
KC_DB_URL: jdbc:postgresql://keycloak-db-container:5432/${KEYCLOAK_POSTGRES_DB}
KC_DB_USERNAME: ${KEYCLOAK_POSTGRES_USER}
KC_DB_PASSWORD: ${KEYCLOAK_POSTGRES_PASSWORD}
```

`KC_DB` selects the JDBC driver and dialect. The URL uses the container name and
the _internal_ port `5432` — never `${KEYCLOAK_POSTGRES_PORT}`, which is a
host-side detail.

**Hostname**

```yaml
KC_HOSTNAME: ${KEYCLOAK_HOSTNAME}
KC_HOSTNAME_STRICT: ${KEYCLOAK_HOSTNAME_STRICT}
```

`KC_HOSTNAME` is the public base URL Keycloak advertises. It ends up in the
OpenID Connect discovery document (`/realms/<realm>/.well-known/openid-configuration`),
in token issuers, and in redirects back to your applications. Get it wrong and
clients receive URLs they cannot reach — the single most common cause of
"it works in the admin console but my app can't log in".

`KC_HOSTNAME_STRICT: false` lets Keycloak infer the host from the incoming
request instead of pinning it. Convenient locally, where you might hit the server
as `localhost`, `127.0.0.1` or a LAN IP. Set it to `true` in production so that
a spoofed `Host` header cannot rewrite the issuer of your tokens.

**HTTP**

```yaml
KC_HTTP_ENABLED: ${KEYCLOAK_HTTP_ENABLED}
```

Allows plain HTTP. Acceptable locally, and acceptable in production _only_ when
TLS terminates at a reverse proxy in front of Keycloak on a trusted network.

**Proxy**

```yaml
KC_PROXY_HEADERS: ${KEYCLOAK_PROXY_HEADERS}
```

Tells Keycloak which forwarding headers to trust when reconstructing the
original request: `xforwarded` (`X-Forwarded-For` / `-Proto` / `-Host`) or
`forwarded` (RFC 7239). Without it, a proxied Keycloak sees every request as
HTTP-from-the-proxy and generates `http://` URLs behind an HTTPS front door.

Only set this when a reverse proxy actually sits in front of Keycloak **and**
strips client-supplied forwarding headers — otherwise any client can forge them.

**Logging**

```yaml
KC_LOG_LEVEL: ${KEYCLOAK_LOG_LEVEL:-info}
KC_LOG_CONSOLE_OUTPUT: json
```

`${VAR:-default}` is Compose's own shell-style default: if `KEYCLOAK_LOG_LEVEL`
is unset or empty, `info` is used. That is why these two entries do not break the
stack when they are missing from `.env`, while the variables without a default
would.

`KC_LOG_CONSOLE_OUTPUT: json` emits structured one-line-per-event JSON, ready for
`docker compose logs | jq`, Loki or an ELK pipeline. Switch it to `default` if
you prefer human-readable console output while debugging.

Useful levels: `info` (default), `debug`, and targeted forms such as
`info,org.keycloak.events:debug` to trace authentication events only.

**Health and metrics**

```yaml
KC_HEALTH_ENABLED: true
KC_METRICS_ENABLED: ${KEYCLOAK_METRICS_ENABLED:-false}
```

With health enabled, Keycloak exposes:

| Endpoint          | Meaning                                                               |
| ----------------- | --------------------------------------------------------------------- |
| `/health/live`    | The process is alive.                                                 |
| `/health/ready`   | Dependencies (database) are reachable — use this for readiness gates. |
| `/health/started` | Startup has completed.                                                |

`KC_METRICS_ENABLED` exposes Prometheus metrics at `/metrics`. Left off by
default because it is unauthenticated.

> On Keycloak 25+, these endpoints are served on the **management port `9000`**,
> not on `8080`. The management port is not published in this stack, so probe
> them from inside the container (`docker compose exec keycloak curl -s
localhost:9000/health/ready`) or add `- "9000:9000"` to `ports:` if you want
> them on the host. Note also that the image ships without a shell utility for
> HTTP by design, so a container-level `healthcheck:` for Keycloak needs either
> Java (`/opt/keycloak/bin/kcadm.sh`) or an external probe.

**Admin bootstrap**

```yaml
KC_BOOTSTRAP_ADMIN_USERNAME: ${KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME}
KC_BOOTSTRAP_ADMIN_PASSWORD: ${KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD}
```

These create the temporary admin account in the `master` realm **on first start
only**, when no admin exists yet. (They replace the older
`KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD` pair, which is deprecated since
Keycloak 26.) Once the database is initialized, changing them in `.env` does
nothing — create or update admins through the console or `kcadm.sh`.

The name is deliberate: this is a _bootstrap_ credential. In production, use it
once to create a real administrator with MFA, then delete it.

### Ports and volumes

```yaml
ports:
  - ${KEYCLOAK_PORT}:8080
volumes:
  - ./keycloak/themes:/opt/keycloak/themes:ro
  - ./keycloak/providers:/opt/keycloak/providers:ro
```

`8080` is Keycloak's internal HTTP port; `${KEYCLOAK_PORT}` is where it lands on
your host. Admin console: `http://localhost:${KEYCLOAK_PORT}/admin`.

Both mounts are read-only (`:ro`) — the container never needs to write there, and
`ro` keeps a misbehaving provider from modifying your working tree.

- `themes/` — custom login, account, email and admin themes. In `start-dev`,
  theme caching is disabled, so edits are picked up on refresh. The login themes
  in this repo are documented in [login-theme.md](login-theme.md).
- `providers/` — custom SPI implementations packaged as JARs (authenticators,
  event listeners, user storage federation). Adding a JAR requires a restart, and
  in production a rebuild (`kc.sh build`).

### Dependency and limits

```yaml
depends_on:
  keycloak-database:
    condition: service_healthy
```

The long form matters. A bare `depends_on: [keycloak-database]` only waits for
the container to be _created_, not for Postgres to accept connections — and
Keycloak exits on a failed database connection at startup. `service_healthy`
ties startup order to the health check defined above.

```yaml
deploy:
  resources:
    limits: { memory: 2G, cpus: "2" }
    reservations: { memory: 1G, cpus: "1" }
```

Keycloak is a JVM application. Modern JVMs are container-aware and size the heap
from the cgroup limit, so the 2 GB ceiling also shapes the heap. Below roughly
1 GB, startup gets slow and GC pressure shows up as sporadic latency.

---

## Volumes

```yaml
volumes:
  keycloak-database:
    driver: local
```

One named volume, holding the Postgres data directory — realms, clients, users,
roles, sessions. Because the project name is pinned, its full name is
`keycloak-modern-auth_keycloak-database`.

**Deleting this volume deletes every realm you configured.** `docker compose
down` keeps it; `docker compose down -v` destroys it.

## Networks

```yaml
networks:
  keycloak-network:
    driver: bridge
```

A user-defined bridge, which (unlike the default bridge) provides automatic DNS
resolution between containers by service and container name. That is what makes
`jdbc:postgresql://keycloak-db-container:5432/...` resolve.

---

## Environment variables

Copy the template and edit it:

```bash
cp .env.example .env
```

`.env` is git-ignored; `.env.example` is the committed contract. Variables
written as `${VAR}` in `compose.yml` are **required** — Compose substitutes an
empty string and warns if they are missing, which usually surfaces as a confusing
runtime error rather than a clean failure.

| Variable                            | Example       | Required     | Purpose                                                                                      |
| ----------------------------------- | ------------- | ------------ | -------------------------------------------------------------------------------------------- |
| `KEYCLOAK_POSTGRES_USER`            | `keycloak`    | yes          | DB role, created on first init; also `KC_DB_USERNAME`.                                       |
| `KEYCLOAK_POSTGRES_PASSWORD`        | `keycloak123` | yes          | DB password. Change it for anything non-local.                                               |
| `KEYCLOAK_POSTGRES_DB`              | `keycloak`    | yes          | Database name, used by the health check and the JDBC URL.                                    |
| `KEYCLOAK_POSTGRES_PORT`            | `5432`        | yes          | **Host** port for Postgres. Internal port is always 5432.                                    |
| `KEYCLOAK_HOSTNAME`                 | `localhost`   | yes          | Public hostname Keycloak advertises in tokens and redirects.                                 |
| `KEYCLOAK_HOSTNAME_STRICT`          | `false`       | yes          | `false` locally; `true` in production.                                                       |
| `KEYCLOAK_HTTP_ENABLED`             | `true`        | yes          | Allow plain HTTP. `true` locally or behind a TLS-terminating proxy.                          |
| `KEYCLOAK_PORT`                     | `8080`        | yes          | **Host** port for Keycloak. Internal port is always 8080.                                    |
| `KEYCLOAK_PROXY_HEADERS`            | `xforwarded`  | yes          | `xforwarded` or `forwarded`. Only meaningful behind a reverse proxy.                         |
| `KEYCLOAK_LOG_LEVEL`                | `info`        | no (`info`)  | Root log level; supports per-category overrides.                                             |
| `KEYCLOAK_METRICS_ENABLED`          | `false`       | no (`false`) | Prometheus endpoint on the management port.                                                  |
| `KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME` | `admin`       | yes          | First-start-only admin username.                                                             |
| `KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD` | `admin123`    | yes          | First-start-only admin password.                                                             |

Values in `.env.example` are local-development defaults and are intentionally
weak. Never reuse them anywhere reachable from a network you do not control.

---

## Everyday commands

```bash
# Start in the background
docker compose up -d

# Follow Keycloak logs (JSON — pipe through jq for readability)
docker compose logs -f keycloak

# Check what Compose actually resolved, variables substituted
docker compose config

# Health of the database gate
docker compose ps

# Shell into Keycloak (admin CLI lives in /opt/keycloak/bin)
docker compose exec keycloak /bin/bash

# Readiness probe from inside the container (management port 9000)
docker compose exec keycloak curl -sf localhost:9000/health/ready

# Stop, keeping data
docker compose down

# Stop and DESTROY the database volume — every realm is lost
docker compose down -v
```

Exporting a realm for version control:

```bash
docker compose exec keycloak /opt/keycloak/bin/kc.sh export \
  --dir /tmp/export --realm <realm-name> --users realm_file
docker compose cp keycloak:/tmp/export/<realm-name>-realm.json ./keycloak/import/
```

The resulting file is what `--import-realm` reads back on the next start.

---

## Development vs. production

This stack is tuned for following the articles on a laptop. The deployment
article changes the following:

| Concern              | Here (dev)           | Production                                                      |
| -------------------- | -------------------- | --------------------------------------------------------------- |
| Start command        | `start-dev`          | `start` on an image pre-built with `kc.sh build`                |
| TLS                  | none, plain HTTP     | HTTPS, terminated at Keycloak or at a trusted proxy             |
| `KC_HOSTNAME_STRICT` | `false`              | `true`, with an explicit `KC_HOSTNAME`                          |
| Admin                | bootstrap admin kept | bootstrap admin used once, then deleted; real admin with MFA    |
| Secrets              | `.env` file          | secret manager or Docker/Kubernetes secrets, never in the image |
| Postgres port        | published to host    | not published                                                   |
| Metrics              | disabled             | enabled, scraped over a private network                         |
| Database             | single container     | managed/replicated instance with backups                        |
| Caching              | default local cache  | Infinispan distributed cache across replicas                    |

`start-dev` also disables theme and template caching and turns off strict
hostname validation — behaviour you specifically do not want in front of real
users.

---

## Troubleshooting

**`WARN The "KEYCLOAK_..." variable is not set. Defaulting to a blank string.`**
A variable used in `compose.yml` is missing from `.env`. Run
`docker compose config` — the substituted output shows exactly which value came
out empty.

**Keycloak exits immediately with a connection error**
The database was not ready, or the credentials do not match what was baked into
the volume on first init. Check `docker compose ps` for the DB's health status,
then `docker compose logs keycloak-database`.

**Changed the Postgres password in `.env` and now nothing connects**
`POSTGRES_PASSWORD` applies only when the data directory is empty. Either change
it inside the database:

```bash
docker compose exec keycloak-database \
  psql -U keycloak -c "ALTER ROLE keycloak WITH PASSWORD 'new-password';"
```

or wipe and restart from scratch with `docker compose down -v` (destroys all
realms).

**`Address already in use`**
Another process holds `${KEYCLOAK_PORT}` or `${KEYCLOAK_POSTGRES_PORT}` — a
system Postgres on 5432 is the usual suspect. Change the host-side value in
`.env`; nothing inside the stack depends on it.

**Login works in the admin console but clients get unreachable redirect URLs**
`KC_HOSTNAME` does not match the URL clients actually use. Compare it against
`http://localhost:${KEYCLOAK_PORT}/realms/master/.well-known/openid-configuration`.

**Realm import does nothing**
`--import-realm` reads `/opt/keycloak/data/import`. Mount a directory there (see
[The `command`](#the-command)); themes and providers mounts do not cover it. It
also skips realms that already exist.
