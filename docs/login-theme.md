# Login Theme Reference

This document explains the custom login theme that ships with this stack: how
Keycloak resolves a theme, how `modern.base` turns `theme.properties` entries
into CSS custom properties, and how to build your own brand on top of it without
copying a single line of CSS.

- [The idea](#the-idea)
- [Layout on disk](#layout-on-disk)
- [How Keycloak resolves a theme](#how-keycloak-resolves-a-theme)
- [The token pipeline](#the-token-pipeline)
- [Token reference](#token-reference)
- [Dark mode](#dark-mode)
- [Class-name properties](#class-name-properties)
- [The admin-console description](#the-admin-console-description)
- [Building your own child theme](#building-your-own-child-theme)
- [Applying a theme to a realm](#applying-a-theme-to-a-realm)
- [Development workflow](#development-workflow)
- [Going to production](#going-to-production)
- [Troubleshooting](#troubleshooting)

---

## The idea

A Keycloak login theme is usually built by copying the built-in `keycloak` theme
and editing its stylesheet. That works exactly once. The second brand means a
second copy, and from then on every fix has to be applied twice — with the two
copies drifting a little further apart each time.

`modern.base` splits the theme in two:

| | `modern.base` | a child theme (`acme`) |
| --- | --- | --- |
| Templates | one, `template.ftl` | none |
| Stylesheet | one, `login.css` | none |
| Design tokens | 58 defaults + 24 dark, in `common/` | 16 overrides, in `common/` |
| Logo | placeholder | its own `logo.svg` |
| Size | ~1,920 lines, mostly comments | 20 lines of properties |

Everything visual is expressed as a **design token** — a named value like
`kcTokenColorPrimary` or `kcTokenRadiusLg`. The stylesheet never hardcodes a
colour, a radius, a font or a spacing step; it only reads tokens. A child theme
therefore restyles all ~40 login pages by overriding values in a properties
file.

---

## Layout on disk

```
keycloak/themes/
├── modern.base/                     the foundation — inherit from this
│   ├── common/
│   │   └── theme.properties         THE PALETTE — 58 tokens + 24 dark
│   └── login/
│       ├── theme.properties         class names, parent, import=common/modern.base
│       ├── template.ftl             page layout + the token <style> block
│       ├── messages/
│       │   └── messages_en.properties   admin-console description
│       └── resources/
│           ├── css/login.css        the only stylesheet, reads tokens only
│           └── img/
│               ├── logo.svg         placeholder wordmark
│               └── favicon.svg
└── acme/                            example child theme
    ├── common/
    │   └── theme.properties         parent=modern.base + 16 token overrides
    └── login/
        ├── theme.properties         kcLogoAlt + import=common/acme
        ├── messages/
        │   └── messages_en.properties   its own description — not inherited
        └── resources/img/logo.svg   overrides the parent's by existing
```

The directory names are the theme names — that string is what you select in the
admin console. `login/` is the *theme type*; a theme may also provide `account/`,
`admin/`, `email/` and `welcome/`, independently of one another. This one is
login-only.

`compose.yml` bind-mounts `./keycloak/themes` read-only at
`/opt/keycloak/themes`, which is where Keycloak looks for filesystem themes.

---

## How Keycloak resolves a theme

Four resolution rules do all the work, and knowing them is most of what theme
development is:

**1. `theme.properties` is merged across the chain.** Keycloak walks
`parent=` upwards and merges every properties file, child last. A child sees all
of the parent's properties and overrides only the keys it restates.

**2. Templates resolve child-first, whole-file.** Asked for `login.ftl`,
Keycloak returns the first one it finds walking child → parent → `base`. There is
no partial override: you either inherit a template or replace it entirely. This
is why the theme keeps its markup changes in a single `template.ftl` — every
other page comes from `base` untouched.

**3. Resources resolve child-first, per file.** `acme` ships only
`img/logo.svg`, so its login page serves that file and gets `css/login.css` and
`img/favicon.svg` from `modern.base` — at URLs under `/login/acme/`, even though
the files live in the parent. Dropping a file into a child theme at the same path
overrides it, with no property to change.

**4. `import=` reaches sideways, across theme types.** `parent=` only ever
connects themes of the *same* type, so `login/theme.properties` cannot see
`email/theme.properties`. A single `import=common/<theme>` bridges that: it
merges the imported theme's properties into the importing one **and** mounts its
`resources/` under the importing theme's own resource path. Exactly one import
is honoured — space- and comma-separated lists are ignored silently — and
properties set locally win over imported ones.

The chain here is two axes. `parent=` runs vertically, `import=` horizontally:

```
             base                         keycloak
              │  parent                      │  parent
              ▼                              ▼
  modern.base/login  ◀── import ──  modern.base/common   ← the palette
              │  parent                      │  parent
              ▼                              ▼
         acme/login  ◀── import ──       acme/common     ← 16 overrides
```

Each `login` theme imports the `common` theme of its *own* theme, and the
`common` themes inherit from each other. That is what lets `acme/common` restate
16 tokens and still receive all 82: the import follows the imported theme's
parent chain too.

`base` is deliberate. It ships the FreeMarker templates for every login screen
with zero styling: each class name in its markup comes from a `kc*Class`
property. Inheriting from `keycloak` or `keycloak.v2` instead would drag in
PatternFly, whose own CSS variables would then compete with ours for control of
the page.

---

## The token pipeline

`login.css` cannot read `theme.properties` — a stylesheet is a static file,
served as-is. `template.ftl` is the bridge. It loops over every property whose
name starts with `kcToken` and emits a CSS custom property, converting camelCase
to kebab-case:

```freemarker
<style id="kc-design-tokens">
    :root {
    <#list properties?keys?sort as key>
        <#if key?starts_with("kcToken") && !key?starts_with("kcTokenDark") && properties[key]?has_content>
        --kc-${key?remove_beginning("kcToken")?replace("([a-z0-9])([A-Z])", "$1-$2", "r")?lower_case}: ${properties[key]?no_esc};
        </#if>
    </#list>
    }
</style>
```

So this, in any theme in the chain:

```properties
kcTokenColorPrimary=#0d9488
kcTokenRadiusLg=8px
```

becomes this, in the rendered page:

```css
:root {
  --kc-color-primary: #0d9488;
  --kc-radius-lg: 8px;
}
```

and `login.css` picks it up:

```css
.kc-btn--primary {
  background-color: var(--kc-color-primary, #4f46e5);
}
```

Three consequences worth spelling out:

- **The loop is generic.** It enumerates properties; it does not know their
  names. A child theme that invents `kcTokenBannerHeight=4rem` gets
  `--kc-banner-height` for free, with no change to `template.ftl` — useful when
  you add your own stylesheet alongside the parent's.
- **Token values are raw CSS.** Anything the property accepts works: a hex
  colour, a gradient, `clamp()`, `color-mix()`, or a reference to another token
  (`kcTokenFontFamilyHeading=var(--kc-font-family)`).
- **Every `var()` in `login.css` carries a fallback**, so a token that is
  emptied rather than overridden degrades to a sane value instead of an invalid
  declaration.

A note on `?no_esc`: FreeMarker HTML-escapes interpolations by default, which
would turn a font stack's quotes into `&quot;` and break the declaration.
Bypassing that is safe here because token values are CSS written by the theme
author — nothing on the page routes request data into a theme property.

---

## Token reference

Defaults live in `keycloak/themes/modern.base/common/theme.properties`, which is
commented per token. The groups:

| Group | Tokens | Notes |
| --- | --- | --- |
| Colour scheme | `kcTokenColorScheme` | `light dark`, or pin to one to disable the other |
| Surfaces | `kcTokenPageBackground`, `kcTokenColorBackground`, `kcTokenColorSurface`, `…SurfaceMuted`, `…SurfaceHover` | the page backdrop takes any `background` value |
| Lines & text | `kcTokenColorBorder`, `…BorderStrong`, `kcTokenColorText`, `…TextMuted`, `kcTokenColorLink`, `…LinkHover` | |
| Brand | `kcTokenColorPrimary`, `…PrimaryHover`, `…PrimaryActive`, `kcTokenColorOnPrimary`, `kcTokenColorFocusRing` | the usual starting point |
| Status | `kcTokenColorDanger/Success/Warning/Info` and a `…Surface` for each | foreground + tinted background per alert type |
| Typography | `kcTokenFontFamily`, `…FamilyHeading`, `kcTokenFontSizeXs…Title`, `kcTokenFontWeight*`, `kcTokenLineHeight`, `kcTokenLetterSpacingTitle` | no webfont is loaded by default |
| Shape | `kcTokenRadiusSm/Md/Lg/Full`, `kcTokenBorderWidth`, `kcTokenCardAccent`, `…AccentHeight` | set the radii to `0` for a square look |
| Elevation | `kcTokenShadowSm/Md/Lg` | |
| Spacing | `kcTokenSpaceXs…Xl` | scaling these up loosens the whole form |
| Layout | `kcTokenCardWidth`, `kcTokenCardPadding`, `kcTokenControlHeight`, `…ControlPaddingInline`, `kcTokenLogoHeight`, `kcTokenTransition` | `kcTokenControlHeight` defaults to 44px, the minimum comfortable touch target |
| Dark palette | `kcTokenDark*` | see below |

Two branding slots sit outside the token system, because they are paths rather
than CSS values: `kcLogoUrl` / `kcLogoAlt` (the header logo — leave `kcLogoUrl`
empty to fall back to the realm display name as text) and `kcFaviconUrl`.

---

## Dark mode

`kcTokenDark*` properties are emitted in a second block, under the *same*
variable names:

```properties
kcTokenColorSurface=#ffffff        ->  :root { --kc-color-surface: #ffffff }
kcTokenDarkColorSurface=#111827    ->  @media (prefers-color-scheme: dark) {
                                         :root { --kc-color-surface: #111827 }
                                       }
```

A dark palette is therefore a set of values, not a second stylesheet — no rule in
`login.css` mentions dark mode. Only colours are overridden; spacing, radii and
typography are shared.

`kcTokenColorScheme` also feeds the native `color-scheme` property, which is what
themes the widgets the browser draws itself — scrollbars, autofill backgrounds,
date pickers. Pinning it to `light` or `dark` drops the media query entirely and
locks the theme to one palette:

```properties
kcTokenColorScheme=light
```

---

## Class-name properties

The `base` templates render `class="${properties.kcInputClass!}"` and friends —
over 110 such hooks. `modern.base` maps every one to a semantic, framework-free
name (`kcInputClass=kc-input`, `kcButtonPrimaryClass=kc-btn--primary`), which is
what lets `login.css` be plain CSS rather than a stack of framework overrides.

Change these only to plug a CSS framework into the markup — set
`kcInputClass=form-control` and the rest of the Bootstrap names, and the login
pages render as Bootstrap. **For visual changes, use tokens instead**: a child
theme that renames classes also has to ship the CSS for them.

Icons are worth a note. No icon font is loaded: `kcFeedbackErrorIcon` and the
others point at `.kc-icon` classes drawn in CSS with `mask-image` and an inline
SVG. They inherit `currentColor` — so they follow the text around them, in both
palettes — and cost no extra request on the login critical path.

---

## The admin-console description

The text shown next to a theme in **Realm settings → Themes** does not live in
`theme.properties`. It is a message, read from the theme's own bundle:

```
login/messages/messages_en.properties
```

```properties
theme.modern.base.login.description=Clean, rounded sign-in card with automatic light/dark switching. Deliberately neutral — the parent to build your own brand on.
```

The key is `theme.<theme-name>.<type>.description`, the same convention
Keycloak's built-in themes use — `theme.keycloak.login.description` is where
"High contrast, sharp, utilitarian, basic." comes from.

Two things about it are easy to get wrong:

- **It does not inherit.** Message bundles merge up the parent chain, so `acme`
  does receive `theme.modern.base.login.description` from its parent — but that
  key names the *parent*, so nothing looks it up for `acme`. A child theme with
  no bundle of its own reports no description at all. Each theme needs its own
  file with its own key.
- **It is English-only.** `/admin/serverinfo`, which is what the admin console
  reads, resolves the description without regard to the requesting locale: an
  admin browsing in French still sees the `messages_en` text. A
  `messages_fr.properties` is still worth adding for the *login pages*, but it
  will not translate the description.

Write it for whoever is *choosing* a theme for a realm — what the pages look
like, what they can do — the way Keycloak's own one-liners do. The token
architecture is documentation, not a theme description.

Keycloak reads theme bundles as UTF-8, not the Latin-1 that `.properties` files
default to in Java, so accented characters and typographic dashes can be written
verbatim — no `\uXXXX` escaping. That matters far more for translated login
pages than for this one line.

To read back what the server actually resolved, rather than what you think you
wrote:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/admin/serverinfo | jq '.themes.login'
```

Note that adding `messages/` to a login theme also overlays the message bundle
used by the pages themselves — that is the same mechanism you would use to
reword `loginAccountTitle` or any other label. Keys you do not restate keep
coming from `base`.

---

## Building your own child theme

`keycloak/themes/acme/` is the worked example. To start a new brand:

```bash
cp -r keycloak/themes/acme keycloak/themes/mybrand
```

Then point the copied theme at itself — `login/theme.properties` carries the
identity and the import, nothing else:

```properties
parent=modern.base
kcLogoAlt=My Brand
import=common/mybrand
```

and `common/theme.properties` carries the brand. A realistic minimum:

```properties
parent=modern.base

kcTokenColorPrimary=#7c3aed
kcTokenColorPrimaryHover=#6d28d9
kcTokenColorPrimaryActive=#5b21b6
kcTokenColorLink=#7c3aed
kcTokenColorLinkHover=#6d28d9

# Pick a lighter tint for the dark palette: a colour chosen against a white
# card is usually too dark against a near-black one.
kcTokenDarkColorPrimary=#a78bfa
kcTokenDarkColorPrimaryHover=#c4b5fd
kcTokenDarkColorOnPrimary=#1e1b4b
```

Forgetting to repoint `import=` is the one step with no visible error: the theme
keeps rendering, in the *parent's* colours, because it is still importing
`common/acme`.

Then replace `login/resources/img/logo.svg` with your own, and rename the key in
`login/messages/messages_en.properties` to match the new theme — the copied
`theme.acme.login.description` names the theme it came from, so it will not show
up for `mybrand`:

```properties
theme.mybrand.login.description=My Brand sign-in.
```

That is the whole job — no `styles=`, no CSS, no template.

When a token genuinely cannot express what you need, add a stylesheet rather
than forking `login.css`:

```properties
styles=css/login.css css/mybrand.css
```

`styles` is replaced, not merged, so the parent's file has to be listed again.
Load order is left to right, so your rules come last.

---

## Applying a theme to a realm

In the admin console: **Realm settings → Themes → Login theme**, pick
`modern.base` or your child theme, then **Save**.

From the CLI, which is scriptable and what CI uses:

```bash
docker compose exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password admin123

docker compose exec keycloak /opt/keycloak/bin/kcadm.sh \
  update realms/master -s loginTheme=acme
```

Themes are selected **per realm and per type**, so a realm can use `acme` for
login and keep the built-in account and admin consoles.

To see the result, open a login page — the admin console at
<http://localhost:8080/admin> if you set the theme on `master`. The account
console (`/realms/<realm>/account`) redirects through one too.

---

## Development workflow

`compose.yml` runs Keycloak with `start-dev`, which disables the theme cache.
Edit a file, reload the page, see the change:

| Change | To see it |
| --- | --- |
| `login.css`, images | reload the page |
| `template.ftl` | reload the page |
| `theme.properties` | reload the page |
| a new theme *directory* | `docker compose restart keycloak` |

The mount is read-only (`:ro`), so edit on the host, never inside the container.

Two habits worth keeping:

- **Test the error states.** They are the ones users hit. A wrong password
  renders the inline field error (`.kc-input__error`); a stale login link renders
  the alert banner (`.kc-alert--error`) and the "We are sorry..." page.
- **Test dark mode.** Toggle your OS appearance, or in Chrome DevTools use
  *Rendering → Emulate CSS prefers-color-scheme*.

CI renders both themes on a real Keycloak and asserts the token block is present
and that the child actually overrode the parent's brand colour — a broken
FreeMarker template does not stop Keycloak from starting, it fails at render
time, on the login page, for the end user.

---

## Going to production

Two changes matter once you leave `start-dev`:

1. **Themes are cached.** `start` enables the theme cache, so edits require a
   restart. That is what you want in production; it is also why a theme that
   "does not update" on a production server is almost always cached, not broken.
2. **Bind mounts are a development convenience.** For a real deployment, bake
   the themes into the image instead:

   ```dockerfile
   FROM quay.io/keycloak/keycloak:26.6 AS builder
   COPY keycloak/themes /opt/keycloak/themes
   RUN /opt/keycloak/bin/kc.sh build
   ```

Also consider `spi-theme-static-max-age` for cache headers on theme resources,
and remember that `kcTokenPageBackground` pointing at a remote image would add a
third-party request to the login path.

---

## Troubleshooting

**The theme does not appear in the admin console dropdown.**
Keycloak only registers a theme it can see at startup. Check
`docker compose exec keycloak ls /opt/keycloak/themes` and confirm the structure
is `<theme>/login/theme.properties` — a `theme.properties` placed directly under
the theme directory is silently ignored. Restart after adding a directory.

**The login page renders unstyled.**
`login.css` did not load. Open its URL directly
(`/resources/<hash>/login/<theme>/css/login.css`); a 404 means the file is not at
`login/resources/css/login.css`, or `styles=` in a child theme replaced the
parent's list without restating `css/login.css`.

**The page returns a 500 after a template edit.**
A FreeMarker error. `docker compose logs keycloak | grep -i freemarker` gives the
line number. The usual causes are a missing `!` default on an interpolation
(`${properties.kcFoo!}`) and an unclosed directive.

**The theme has no description in the admin console.**
The description is a message, not a property: it belongs in
`login/messages/messages_en.properties` under the key
`theme.<theme-name>.<type>.description`. The usual cause is a copied child theme
still carrying the parent's key, which names the wrong theme. Check what the
server resolved with `curl .../admin/serverinfo | jq '.themes.login'` — a `null`
description means no matching key was found.

**A token override has no effect.**
Check the emitted block first — view source and look for
`<style id="kc-design-tokens">`. If your value is not in it, the property name is
wrong (`kcTokenColorPrimary`, not `kcTokenPrimaryColor`). If it *is* in it but
nothing changed, no rule consumes that variable: grep `login.css` for the
variable name.

**Colours look wrong in dark mode only.**
You overrode `kcTokenColorPrimary` without `kcTokenDarkColorPrimary`, so the dark
block still carries the parent's value.

**Quotes appear as `&quot;` in a font stack.**
Only possible in a stylesheet of your own — the token block bypasses HTML
escaping deliberately. Set the font family through `kcTokenFontFamily`.
