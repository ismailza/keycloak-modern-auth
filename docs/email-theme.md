# Email Theme Reference

This document explains the custom email theme that ships with this stack: what
Keycloak actually sends, why an email theme cannot be built the way a login
theme is, how `modern.base` themes all ~17 mails by overriding a single
template, and how to test the result locally before a real recipient sees it.

- [The idea](#the-idea)
- [Layout on disk](#layout-on-disk)
- [What Keycloak sends](#what-keycloak-sends)
- [Why an email theme is not a login theme](#why-an-email-theme-is-not-a-login-theme)
- [The two styling layers](#the-two-styling-layers)
- [Token reference](#token-reference)
- [Dark mode](#dark-mode)
- [The logo problem](#the-logo-problem)
- [Messages and translations](#messages-and-translations)
- [The admin-console description](#the-admin-console-description)
- [Building your own child theme](#building-your-own-child-theme)
- [Applying a theme to a realm](#applying-a-theme-to-a-realm)
- [Testing locally](#testing-locally)
- [Client support and known degradations](#client-support-and-known-degradations)
- [Going to production](#going-to-production)
- [Troubleshooting](#troubleshooting)

---

## The idea

The same idea as [the login theme](login-theme.md), under much harsher
constraints. `modern.base/email` ships one template and no stylesheet, reads
the *same* palette the login pages read, and lets a child theme rebrand every
mail Keycloak sends by overriding token values:

| | `modern.base/email` | a child theme (`acme/email`) |
| --- | --- | --- |
| Templates | one, `html/template.ftl` (+ one 4-line variant) | none |
| Stylesheet | none — there is no `<link>` in mail | none |
| Design tokens | the shared palette + 12 email-only ones | 0 of its own |
| Messages | 1 description + 2 shell strings | 1 description |
| Size | ~300 lines, mostly comments | 3 effective lines |

The brand colour lives in `common/theme.properties`, which both types import, so
the login button and the mail button are the same teal because there is one
definition of it.

---

## Layout on disk

```
keycloak/themes/
├── modern.base/
│   ├── common/
│   │   └── theme.properties              THE PALETTE — shared with login/
│   ├── login/                            see docs/login-theme.md
│   └── email/
│       ├── theme.properties              parent=base, import=common/modern.base,
│       │                                 branding slots + email-only geometry
│       ├── html/
│       │   ├── template.ftl              the shell every mail is rendered into
│       │   └── email-verification-with-code.ftl   one 4-line variant
│       └── messages/
│           └── messages_en.properties    description + 2 shell strings
└── acme/
    ├── common/
    │   └── theme.properties              parent=modern.base + token overrides
    ├── login/
    └── email/
        ├── theme.properties              parent=modern.base + import=common/acme
        └── messages/
            └── messages_en.properties    its own description — not inherited
```

There is no `email/resources/` directory, and adding one would achieve nothing:
mail is rendered outside any HTTP request, so a theme's email resources are
never published at a URL a mail client could fetch. See
[the logo problem](#the-logo-problem).

Note also what is *absent*: no `text/` directory. The plain-text alternative of
every mail is inherited from `base` untouched, which is the right default —
plain text should stay plain. Keycloak sends both parts as a
`multipart/alternative` message, and some clients, filters and screen readers
read the text one.

---

## What Keycloak sends

Seventeen mails, all built the same way. `base/email/html/password-reset.ftl` is
representative — it is the whole file:

```freemarker
<#import "template.ftl" as layout>
<@layout.emailLayout>
${kcSanitize(msg("passwordResetBodyHtml", link, linkExpiration, realmName, linkExpirationFormatter(linkExpiration)))?no_esc}
</@layout.emailLayout>
```

Two things follow from that shape, and they are the whole design of this theme:

**The body copy is a message, not markup.** `passwordResetBodyHtml` is a string
in a message bundle — a few `<p>` elements with one `<a>` in them — that
Keycloak ships translated into 36 languages. It is finished HTML by the time the
template sees it.

**The chrome is a macro.** Every one of the seventeen imports `template.ftl` by
name, and templates resolve child-first, so overriding that one file themes all
of them at once. Nothing else has to be copied, and every translation keeps
working.

The mails, grouped by what they carry:

| Carries an action link | Carries a code | Notification only |
| --- | --- | --- |
| `password-reset`, `email-verification`, `email-update-confirmation`, `executeActions`, `identity-provider-link`, `org-invite` | `email-verification-with-code` | `event-login_error`, `event-update_password`, `event-update_totp`, `event-remove_totp`, `event-update_credential`, `event-remove_credential`, `event-user_disabled_by_*_lockout`, `workflow-notification`, `email-test` |

The first column is the one users act on; it is also the column where the
call-to-action button and the raw-URL fallback appear.

---

## Why an email theme is not a login theme

The login theme publishes its tokens as CSS custom properties and lets
`login.css` read them. Neither half of that survives in a mail client:

| | Login page | Email |
| --- | --- | --- |
| External stylesheet | `<link>` to `css/login.css` | dropped by every client — there is no stylesheet file at all |
| CSS custom properties | `--kc-color-primary`, read by every rule | Gmail strips any declaration containing `var()` |
| Units | `rem`, `clamp()`, `color-mix()` | Outlook for Windows renders through Word: px only |
| Layout | flexbox and grid | tables, with a fixed `width` attribute and a `max-width` |
| Where CSS applies | one cascade | inline styles always; a `<style>` block only sometimes |

So tokens are resolved **at render time, in FreeMarker**, and interpolated
straight into `style` attributes:

```freemarker
<#local colorPrimary = properties.kcTokenColorPrimary!'#4f46e5'>
...
<table style="... border-top: ${accentHeight} solid ${colorPrimary}; ...">
```

The fallback in `properties.kcX!'default'` plays exactly the role the second
argument of `var()` plays in `login.css`: a token that is emptied rather than
overridden degrades to a sane value instead of an empty declaration.

Three tokens from the shared palette are deliberately **not** used by the mail
shell, because their values are CSS that mail clients cannot parse:

| Token | Value | What the mail uses instead |
| --- | --- | --- |
| `kcTokenPageBackground` | a `radial-gradient()` | `kcTokenColorBackground` |
| `kcTokenCardAccent` | contains `var()` | `kcTokenColorPrimary` |
| `kcTokenFontFamilyHeading` | `var(--kc-font-family)` | `kcTokenFontFamily` |

Everything else in the palette is a hex colour or a px value, and travels fine.

### One trap worth its own paragraph

A font stack contains double quotes — `system-ui, -apple-system, "Segoe UI", …`
— and it is needed in two places that quote differently:

```freemarker
<#local fontStack     = properties.kcTokenFontFamily!'…'>
<#local fontFamilyCss = fontStack?no_esc>                    <#-- for <style>      -->
<#local fontFamily    = fontStack?replace('"', "'")?no_esc>  <#-- for style="…"    -->
```

Inside `<style>` the value has to arrive verbatim, because character references
are not parsed there — hence `?no_esc`, which also stops FreeMarker turning the
quotes into `&quot;`. Inside a `style="…"` attribute that same unescaped quote
would **end the attribute**, silently truncating the declaration and everything
after it. CSS accepts single-quoted family names, so swapping the quote
characters fixes it and leaves no entities behind for a client's HTML sanitizer
to re-escape.

---

## The two styling layers

**Chrome is styled inline.** Every element `template.ftl` emits carries its own
`style` attribute. Inline styles are the only thing every mail client honours,
so nothing structural depends on the `<style>` block surviving.

**Body copy is styled from the `<style>` block.** It has to be: the copy arrives
as a finished HTML string from a message bundle, and there is no point at which
a style attribute could be inserted into it. The shell wraps it in a `div` and
styles it by class:

```css
.kc-prose p { margin: 0 0 16px; }
.kc-prose a {
    display: inline-block;
    padding: 13px 24px;
    background-color: #4f46e5;
    border-radius: 10px;
    color: #ffffff !important;
    ...
}
```

That second rule is what turns the action link into a call-to-action button. It
works because **every base message body contains exactly one link, and it is
always the action** — so the anchor *is* the button. If you rewrite a body
message to carry links inside a sentence, narrow the selector before you do.

Clients that support embedded CSS (Apple Mail, iOS Mail, Gmail, Outlook.com,
Thunderbird, Yahoo) get the button. The rest fall back to the client's default
paragraph spacing and a plain blue link — which still works, and is the reason
the link is never *only* a button. Under the copy, on every mail that carries a
link, the shell prints the raw URL:

> Trouble opening the link above? Copy this address into your browser:
> `http://localhost:8080/realms/master/login-actions/action-token?key=…`

Set `kcEmailLinkFallback=false` to drop that block.

One more asymmetry worth knowing: CSS comments would be delivered to every
recipient, in every mail, so the explanatory comments inside the `<style>` block
are FreeMarker comments (`<#-- … -->`), which are stripped at render time. A
rendered mail from this theme is about 8.5 KB — comfortably under the 102 KB at
which Gmail clips a message and hides the end of it behind a "View entire
message" link.

---

## Token reference

Colours, radii, border width, font family and the accent height come from
`modern.base/common/theme.properties` — the same values the login pages use,
documented per token there. Geometry that has to be px lives in
`modern.base/email/theme.properties`:

| Token | Default | Notes |
| --- | --- | --- |
| `kcTokenEmailWidth` | `600px` | what the Outlook reading pane fits without scrolling; the card is fluid below it |
| `kcTokenEmailPagePadding` | `24px` | between the card and the client viewport |
| `kcTokenEmailCardPadding` | `32px` | inside the card |
| `kcTokenEmailGap` | `16px` | between paragraphs |
| `kcTokenEmailFontSize` | `16px` | the floor for body copy: iOS auto-enlarges anything smaller and breaks the layout |
| `kcTokenEmailFontSizeSm` | `14px` | the fallback-block lead-in |
| `kcTokenEmailFontSizeXs` | `12px` | footer, raw URL |
| `kcTokenEmailFontFamilyCode` | monospace stack | the one-time code |
| `kcTokenEmailCodeFontSize` | `28px` | |
| `kcTokenEmailCodeLetterSpacing` | `6px` | |
| `kcTokenEmailButtonPadding` | `13px 24px` | vertical then horizontal |

And four branding slots, which are paths and flags rather than CSS values:

| Property | Default | Notes |
| --- | --- | --- |
| `kcEmailLogoUrl` | *(empty)* | absolute `https://` URL; empty renders the realm display name as a text wordmark |
| `kcEmailLogoAlt` | *(empty)* | falls back to the realm display name |
| `kcEmailLogoHeight` | `32` | bare number — feeds both the `height` attribute Outlook needs and the inline style |
| `kcEmailLinkFallback` | `true` | the raw-URL block under the body |

---

## Dark mode

Same tokens as the login theme's dark mode, one layer down. `kcTokenDark*`
values are emitted into a `prefers-color-scheme` block, with `!important` on
every declaration — because in mail these rules have to override *inline*
styles, not just a stylesheet:

```css
@media (prefers-color-scheme: dark) {
    .kc-email-card { background-color: #111827 !important; border-color: #293548 !important; }
    .kc-prose a    { background-color: #6366f1 !important; color: #0b1020 !important; }
}
```

The `<head>` also carries `<meta name="color-scheme">`, without which Apple Mail
and Outlook invert the colours themselves and the media query never gets a
chance to run.

Honoured by Apple Mail, iOS Mail, Outlook for Mac/iOS and Thunderbird. **Gmail
ignores it** and applies its own inversion to the light palette instead, which
is why the light palette has to look right on its own — never encode meaning in
a colour that only the dark block sets. Pinning `kcTokenColorScheme=light` drops
the block entirely, for both the login pages and the mails.

---

## The logo problem

A login theme points `kcLogoUrl` at `img/logo.svg` and Keycloak serves it from
`${url.resourcesPath}`. In an email template there is no `url` object at all:
mail is rendered outside any HTTP request, and the theme's email resources are
never published. The other two ways of embedding an image are also closed —
Keycloak attaches no CID parts to these mails, and Gmail, Outlook and Apple Mail
all refuse `data:` URIs in `<img src>`.

So an email logo must be an **absolute, publicly reachable URL**, hosted by you:

```properties
kcEmailLogoUrl=https://acme.example.com/assets/email-logo.png
kcEmailLogoAlt=Acme
kcEmailLogoHeight=32
```

Use PNG or JPEG — Gmail and Outlook do not render SVG in mail. Serve it at twice
the rendered height for retina screens; the `height` attribute scales it down.

Both themes here leave it empty on purpose, so the mails show the realm's
display name as a text wordmark. That is not just a placeholder: **most clients
block remote images by default**, so for a large share of recipients the
wordmark — or, once you set a logo, the alt text — is what actually arrives at
the top of a password-reset mail. A broken image icon there costs more trust
than a missing logo.

---

## Messages and translations

Overriding `html/template.ftl` and nothing else is what keeps `base`'s subjects
and bodies — and their 36 translations — intact. Verify it in one command once
you have [a local SMTP sink](#testing-locally): set a user's locale to `ar` and
the mail arrives with an Arabic subject, Arabic body and `dir="rtl"` on the
`<html>` element, through this theme's shell.

The shell does add two strings of its own, in
`modern.base/email/messages/messages_en.properties`:

```properties
modernEmailLinkFallback=Trouble opening the link above? Copy this address into your browser:
modernEmailFooter=This message was sent automatically by {0}. Please do not reply to it.
```

New keys are the one thing to be careful with. An English-only key is not a
hole: Keycloak walks the locale chain and merges what it finds, `fr` → `en` →
the key name itself, so an untranslated key still resolves to its English text
for every recipient. It just arrives in the wrong language, inside an otherwise
correctly translated mail. Add a `messages_<locale>.properties` next to the
English one for each language your realm actually offers.

Two `.properties` details specific to email bundles:

- These strings go through `java.text.MessageFormat`, where an apostrophe is a
  quoting character. A literal one has to be **doubled** — Keycloak's own bundle
  writes `don''t` for exactly that reason.
- Bundles are read as UTF-8, so accented characters and typographic dashes are
  safe verbatim; no `\uXXXX` escaping.

The same bundle is where you would reword any inherited mail without touching a
template — restate `passwordResetBodyHtml` and yours wins.

---

## The admin-console description

As with the login theme, the text next to a theme in **Realm settings → Themes →
Email theme** is a message, not a property:

```properties
theme.modern.base.email.description=Branded HTML mail on a card, sharing the login theme's palette, …
```

The key is `theme.<theme-name>.<type>.description`. It does **not** inherit —
the key names the theme it belongs to, so a copied child theme still carrying
`theme.acme.email.description` shows no description at all under its own name.
And it is resolved in English whatever locale the admin is browsing in.

Read back what the server actually resolved:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/admin/serverinfo | jq '.themes.email'
```

---

## Building your own child theme

`keycloak/themes/acme/email/` is the worked example, and it is three effective
lines:

```properties
parent=modern.base
import=common/acme
```

That is genuinely all, because the colours are already there — `common/acme` is
the same file that rebrands the login pages. To start a new brand from it:

```bash
cp -r keycloak/themes/acme keycloak/themes/mybrand
```

then, in `mybrand/email/theme.properties`, repoint the import:

```properties
parent=modern.base
import=common/mybrand
```

Forgetting that line is the one step with no visible error: the mails keep
rendering, in the *parent's* colours, because they are still importing
`common/acme`. Rename the key in `mybrand/email/messages/messages_en.properties`
to `theme.mybrand.email.description` for the same reason — a copied key names
the wrong theme.

If a token genuinely cannot express what you need, copy the four-line
`html/<type>.ftl` for that one mail out of `base` and pass the shell a different
variant, the way `email-verification-with-code.ftl` does:

```freemarker
<#import "template.ftl" as layout>
<@layout.emailLayout proseClass="kc-prose kc-prose--code">
${kcSanitize(msg("emailVerificationBodyCodeHtml",code))?no_esc}
</@layout.emailLayout>
```

The macro takes two optional parameters:

| Parameter | Default | Purpose |
| --- | --- | --- |
| `proseClass` | `kc-prose` | the class on the body wrapper; `kc-prose kc-prose--code` renders a `<b>` as a monospaced, letter-spaced code block |
| `preheader` | *(empty)* | the grey line the inbox list shows after the subject; hidden inside the message |

Overriding one mail does not disturb the other sixteen.

---

## Applying a theme to a realm

An email theme does nothing until the realm can actually send mail. Both halves
are per realm:

**Realm settings → Email** — the SMTP server, and a `From` address.
**Realm settings → Themes → Email theme** — `modern.base` or your child theme.

From the CLI:

```bash
docker compose exec keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 --realm master --user admin --password admin123

docker compose exec keycloak /opt/keycloak/bin/kcadm.sh update realms/master \
  -s emailTheme=acme
```

Themes are selected per realm *and per type*, so a realm can run `acme` for
login and email and keep the built-in account and admin consoles.

---

## Testing locally

Do not test email themes by sending real mail. Run a sink that accepts
everything and shows you what arrived — [Mailpit](https://mailpit.axllent.org/)
on this stack's network is one container:

```bash
docker run -d --name mailpit \
  --network keycloak-modern-auth_keycloak-network \
  -p 8025:8025 axllent/mailpit
```

Point the realm at it — the host is the *container* name on the bridge network,
and the port is Mailpit's internal SMTP port, not the published web one:

```bash
docker compose exec keycloak /opt/keycloak/bin/kcadm.sh update realms/master \
  -s emailTheme=modern.base \
  -s 'smtpServer.host=mailpit' \
  -s 'smtpServer.port=1025' \
  -s 'smtpServer.from=no-reply@example.com' \
  -s 'smtpServer.fromDisplayName=Modern Auth' \
  -s 'smtpServer.auth=false' -s 'smtpServer.ssl=false' -s 'smtpServer.starttls=false'
```

Then trigger the mails. The two most useful ones, for a user that has an email
address, are an action mail and a verification mail:

```bash
USER_ID=$(docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh \
  get users -r master -q username=demo --fields id --format csv --noquotes)

# Renders executeActions.ftl — an action link, so the button and the URL fallback
curl -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '["UPDATE_PASSWORD"]' \
  "http://localhost:8080/admin/realms/master/users/$USER_ID/execute-actions-email"

# Renders email-verification.ftl
curl -X PUT -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8080/admin/realms/master/users/$USER_ID/send-verify-email"
```

Read the result at <http://localhost:8025>. Mailpit renders the HTML part, shows
the plain-text alternative next to it, and serves the raw source at
`/api/v1/message/<id>` — which is the fastest way to check that a token actually
landed:

```bash
curl -s http://localhost:8025/api/v1/message/<id> | jq -r '.HTML' | grep -o 'background-color: #[0-9a-f]*' | sort -u
```

`Realm settings → Email → Test connection` is the other trigger; it renders
`email-test.ftl` and needs the *admin* user to have an email address, or it
answers 500.

Theme edits behave as they do for login themes: `start-dev` disables the theme
cache, so an edited template or property applies to the next mail sent, while a
brand-new theme *directory* needs `docker compose restart keycloak` before
Keycloak registers it.

---

## Client support and known degradations

What this theme is designed to degrade into, rather than what it guarantees:

| Client | Result |
| --- | --- |
| Apple Mail, iOS Mail | everything, including the dark palette |
| Gmail (web, iOS, Android) | card, colours, button; its own dark inversion instead of the dark block |
| Outlook.com, Yahoo, Thunderbird | card, colours, button |
| **Outlook for Windows** (Word engine) | card, colours, padding; `display:inline-block` is dropped, so the button arrives as coloured text |
| Any client that strips `<style>` | default paragraph spacing, a plain blue link, correct fonts and colours from the inline styles |
| Images blocked (the default in most clients) | the text wordmark or the logo's alt text |
| Plain-text-only clients and filters | the `text/` part, inherited from `base` |

Making the button a filled rectangle in Outlook for Windows needs a VML
rectangle wrapped around the anchor — which cannot be done from the shell,
because the anchor is inside the message string. Wrapping it would mean giving
up the inherited, translated body copy for every mail; the coloured-text
fallback is the better trade.

---

## Going to production

The theme is the small half of shipping transactional mail.

1. **Deliverability is not a theme setting.** SPF, DKIM and DMARC on the sending
   domain, a `From` address on a domain you control, and a real SMTP relay
   rather than a container. A beautiful mail in the spam folder is a mail nobody
   read.
2. **Set a reply-to that a human reads**, or make the footer's "do not reply"
   true by pointing the `From` at an unmonitored mailbox that bounces politely.
3. **Themes are cached** under `start`, so mail template edits need a restart —
   the same rule as login themes, and the usual reason a "fixed" mail keeps
   arriving wrong. For a real deployment, bake the themes into the image:

   ```dockerfile
   FROM quay.io/keycloak/keycloak:26.6 AS builder
   COPY keycloak/themes /opt/keycloak/themes
   RUN /opt/keycloak/bin/kc.sh build
   ```
4. **Check the logo host.** It is fetched by every recipient's client, from
   networks you do not control, and it is the only external request the mail
   makes. Serve it from a stable URL you will not move.

---

## Troubleshooting

**The theme does not appear in the Email theme dropdown.**
Keycloak registers themes at startup. Confirm the structure is
`<theme>/email/theme.properties` — a `theme.properties` one level too high is
ignored silently — then `docker compose restart keycloak`.

**Nothing arrives at all.**
That is SMTP, not the theme. `docker compose logs keycloak | grep -i mail`, and
check `Realm settings → Email → Test connection`. A user with no email address
is the other common cause; the admin endpoints answer 400 or 500 rather than
sending.

**The mail arrives unstyled, or as one wall of text.**
Check whether the client kept the `<style>` block: view the source and look for
`.kc-prose`. If the block is there and the copy is still unstyled, the client
strips embedded CSS — which is the documented fallback, not a bug. If the
*inline* styles are missing too, a token is empty: view the source and look at
the `style` attribute on the card table.

**Everything after `font-family:` in a `style` attribute is gone.**
A font stack with double quotes was interpolated into an attribute without
swapping them for single quotes. See
[the trap](#one-trap-worth-its-own-paragraph).

**A token override has no effect.**
Check that you changed `common/theme.properties` and not only the login theme,
and that the email theme's `import=` points at *your* common theme. Then check
the token is one the mail shell reads — the three `var()`/gradient tokens listed
[above](#why-an-email-theme-is-not-a-login-theme) are deliberately ignored here.

**The colours are right in the login pages and wrong in the mails.**
Almost always the `import=` line: a copied child theme still importing
`common/acme` renders in Acme's teal and fails silently.

**A message shows a raw key like `modernEmailFooter`.**
The key resolved to nothing — usually a typo in
`email/messages/messages_en.properties`, or a bundle placed under `messages/`
of the wrong theme type.

**The body text is translated but the footer is English.**
Working as designed: the two shell strings only ship in English. Add
`messages_<locale>.properties` next to the English bundle.

**Gmail shows "View entire message".**
The mail exceeded 102 KB. This theme renders at about 8.5 KB, so the cause is
something added to it — usually an inlined image or a very long body message.
