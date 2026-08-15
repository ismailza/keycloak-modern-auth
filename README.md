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

## Login theme

`keycloak/themes/modern.base` is a token-driven login theme: one template, one
stylesheet, and 58 design tokens (plus 24 dark-mode overrides) declared in
`common/theme.properties`. The stylesheet never hardcodes a colour, radius or
spacing value — it only reads tokens — so a child theme rebrands every login page
by overriding values, with no CSS to copy. The palette sits in a `common` theme,
which is what lets the email theme read the very same values.

`keycloak/themes/acme` is that child theme: 20 lines of properties and a logo.
Its whole brand is one file, `acme/common/theme.properties`:

```properties
parent=modern.base

kcTokenColorPrimary=#0d9488
kcTokenRadiusLg=8px
```

Apply one in **Realm settings → Themes → Login theme**. In `start-dev` the theme
cache is off, so edits show up on the next page load.

**Full reference: [docs/login-theme.md](docs/login-theme.md)** — how Keycloak
resolves a theme, the token pipeline, the complete token list, dark mode,
building your own child theme, and troubleshooting.

## Email theme

The same themes also cover the ~17 mails Keycloak sends — verification, password
reset, action links, organization invites, security notifications. They read the
palette above, so one brand colour moves the sign-in button and the
password-reset button together.

Mail is a harsher target than a web page: no external stylesheet, no CSS custom
properties (Gmail strips `var()`), no `rem` (Outlook renders through Word). So
`modern.base/email` resolves the tokens in FreeMarker instead and interpolates
them into inline styles, in a single `html/template.ftl` — which is why themeing
all ~17 mails costs one file and leaves every one of their 36 translations
intact. `acme/email` is the child theme, and it is three lines:

```properties
parent=modern.base
import=common/acme
```

Apply one in **Realm settings → Themes → Email theme**, after configuring SMTP
under **Realm settings → Email**.

**Full reference: [docs/email-theme.md](docs/email-theme.md)** — what Keycloak
sends, the inline-vs-`<style>` split and what degrades where, the email token
list, dark mode, the logo problem, testing locally against a Mailpit sink, and
troubleshooting.

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
