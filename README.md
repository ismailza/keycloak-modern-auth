# Keycloak Modern Authentication

Companion repository for the "Modern Authentication with Keycloak" series.

A reproducible local Keycloak stack: **Keycloak 26.6** backed by **PostgreSQL 18**,
defined in a single `compose.yml` and driven entirely by environment variables.

## Quick start

```bash
cp .env.example .env      # adjust ports/credentials if needed
docker compose up -d
docker compose logs -f keycloak
```

Then open the admin console at <http://localhost:8080/admin> and sign in with
`KEYCLOAK_BOOTSTRAP_ADMIN_USERNAME` / `KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD`
(`admin` / `admin123` by default).

Stop the stack with `docker compose down`. Add `-v` only if you want to delete
the database volume — that erases every realm you configured.

## What is in the stack

| Service | Image | Host port | Role |
| --- | --- | --- | --- |
| `keycloak` | `quay.io/keycloak/keycloak:26.6` | `${KEYCLOAK_PORT}` → 8080 | Identity provider, started in dev mode |
| `keycloak-database` | `postgres:18` | `${KEYCLOAK_POSTGRES_PORT}` → 5432 | Persistent storage for realms, clients and users |

Keycloak waits for the database's health check before starting, and connects to
it over the private `keycloak-network` bridge. Data lives in the named volume
`keycloak-database`; `keycloak/themes` and `keycloak/providers` are bind-mounted
read-only for custom themes and SPI JARs.

## Configuration

All settings come from `.env` (git-ignored). `.env.example` is the committed
template and documents every variable inline.

**Full reference: [docs/docker-configuration.md](docs/docker-configuration.md)** —
service-by-service walkthrough, the complete variable table, everyday commands,
the dev-vs-production checklist, and troubleshooting.

## Requirements

- Docker Engine 20.10+ with the Compose V2 plugin
- ~2.5 GB of free RAM
- Ports `8080` and `5432` available (both configurable in `.env`)

## Note on defaults

The credentials in `.env.example` are deliberately weak development defaults.
This stack runs Keycloak in `start-dev` mode over plain HTTP and is meant for
local use only — see the
[development vs. production](docs/docker-configuration.md#development-vs-production)
section before deploying anything.

## License

[MIT](LICENSE)
