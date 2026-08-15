<#--
  MODERN.BASE — HTML EMAIL SHELL

  Every mail Keycloak sends goes through this macro. The ~17 html/<type>.ftl
  files in `base` all look like this, and none of them are overridden here:

      <#import "template.ftl" as layout>
      <@layout.emailLayout>
      ${kcSanitize(msg("passwordResetBodyHtml", link, ...))?no_esc}
      </@layout.emailLayout>

  So `<#nested>` below is the localized body copy, straight out of base's
  message bundles — untouched, in all 36 languages. This file supplies the
  chrome around it: the card, the brand header, the button styling, the footer
  and the dark palette.

  ---------------------------------------------------------------------------
  TWO STYLING LAYERS, AND WHY

  Chrome is styled INLINE. Every element this template emits carries its own
  `style` attribute, because inline styles are the only thing every mail client
  honours. Nothing structural depends on the <style> block below surviving.

  Body copy is styled from the <style> BLOCK. It has to be: the copy arrives as
  a finished HTML string from a message bundle, and there is no point at which
  a style attribute could be inserted into it. Clients that support embedded
  CSS (Apple Mail, iOS, Gmail, Outlook.com, Thunderbird, Yahoo) get the styled
  paragraphs and the call-to-action button; the rest fall back to the client's
  default paragraph and a plain blue link, which still works. That degradation
  is the reason the link is never *only* a button — see the fallback block.

  Outlook on Windows renders through Word: it keeps the tables, the colours and
  the padding, and drops `display:inline-block`, so the button arrives as
  coloured text rather than a filled rectangle. Making it a filled rectangle
  there needs a VML rectangle wrapped around the anchor, which cannot be done
  from out here — the anchor is inside the message string.

  ---------------------------------------------------------------------------
  TOKENS

  Values come from ../theme.properties and, through `import=common/modern.base`,
  from the palette the login theme reads. They are resolved here, at render
  time: Gmail strips declarations containing var(), so CSS custom properties
  are not an option in mail.

  Each `properties.kcX!'default'` carries a fallback, exactly as every var() in
  login.css does, so emptying a token degrades to a sane value instead of an
  empty declaration.

  Comments inside the <style> block below are kept to section markers on
  purpose. FreeMarker comments like this one are stripped at render time; CSS
  comments would be delivered, in every mail, to every recipient.

  Full walkthrough: docs/email-theme.md
-->
<#macro emailLayout preheader="" proseClass="kc-prose">

<#-- ---- Palette (shared with the login theme) ------------------------- -->
<#local colorScheme      = properties.kcTokenColorScheme!'light dark'>
<#local colorBackground  = properties.kcTokenColorBackground!'#f8fafc'>
<#local colorSurface     = properties.kcTokenColorSurface!'#ffffff'>
<#local colorSurfaceMuted= properties.kcTokenColorSurfaceMuted!'#f8fafc'>
<#local colorBorder      = properties.kcTokenColorBorder!'#e2e8f0'>
<#local colorText        = properties.kcTokenColorText!'#0f172a'>
<#local colorTextMuted   = properties.kcTokenColorTextMuted!'#64748b'>
<#local colorPrimary     = properties.kcTokenColorPrimary!'#4f46e5'>
<#local colorOnPrimary   = properties.kcTokenColorOnPrimary!'#ffffff'>
<#local colorLink        = properties.kcTokenColorLink!'#4f46e5'>

<#-- ---- Dark palette -------------------------------------------------- -->
<#local darkBackground   = properties.kcTokenDarkColorBackground!'#0f172a'>
<#local darkSurface      = properties.kcTokenDarkColorSurface!'#111827'>
<#local darkSurfaceMuted = properties.kcTokenDarkColorSurfaceMuted!'#1e293b'>
<#local darkBorder       = properties.kcTokenDarkColorBorder!'#293548'>
<#local darkText         = properties.kcTokenDarkColorText!'#e2e8f0'>
<#local darkTextMuted    = properties.kcTokenDarkColorTextMuted!'#94a3b8'>
<#local darkPrimary      = properties.kcTokenDarkColorPrimary!'#6366f1'>
<#local darkOnPrimary    = properties.kcTokenDarkColorOnPrimary!'#0b1020'>
<#local darkLink         = properties.kcTokenDarkColorLink!'#a5b4fc'>

<#-- ---- Font stacks ---------------------------------------------------
     A font stack is the one token whose value can contain double quotes, and
     it is needed in two places that quote differently:

       fontFamilyCss  raw, for the <style> element. Character references are
                      not parsed inside <style>, so "Segoe UI" has to arrive
                      verbatim — hence ?no_esc, which also keeps FreeMarker
                      from turning it into &quot;Segoe UI&quot;.
       fontFamily     for style="..." attributes, where an unescaped double
                      quote would END the attribute. CSS accepts single-quoted
                      family names, so swapping the quote characters is enough
                      and leaves no entities behind for a client's HTML
                      sanitizer to re-escape.
-->
<#local fontStack        = properties.kcTokenFontFamily!'system-ui, -apple-system, "Segoe UI", Roboto, Arial, sans-serif'>
<#local fontFamilyCss    = fontStack?no_esc>
<#local fontFamily       = fontStack?replace('"', "'")?no_esc>
<#local fontFamilyCode   = (properties.kcTokenEmailFontFamilyCode!'ui-monospace, Menlo, Consolas, monospace')?no_esc>

<#-- ---- Shape & type (px in the shared palette, so reused as-is) ------- -->
<#local fontWeightBold   = properties.kcTokenFontWeightBold!'650'>
<#local lineHeight       = properties.kcTokenLineHeight!'1.5'>
<#local radiusMd         = properties.kcTokenRadiusMd!'10px'>
<#local radiusLg         = properties.kcTokenRadiusLg!'16px'>
<#local borderWidth      = properties.kcTokenBorderWidth!'1px'>
<#local accentHeight     = properties.kcTokenCardAccentHeight!'3px'>
<#local hasAccent        = !(accentHeight == '0' || accentHeight == '0px')>

<#-- ---- Email-only geometry ------------------------------------------- -->
<#local width            = properties.kcTokenEmailWidth!'600px'>
<#local pagePadding      = properties.kcTokenEmailPagePadding!'24px'>
<#local cardPadding      = properties.kcTokenEmailCardPadding!'32px'>
<#local gap              = properties.kcTokenEmailGap!'16px'>
<#local fontSize         = properties.kcTokenEmailFontSize!'16px'>
<#local fontSizeSm       = properties.kcTokenEmailFontSizeSm!'14px'>
<#local fontSizeXs       = properties.kcTokenEmailFontSizeXs!'12px'>
<#local codeFontSize     = properties.kcTokenEmailCodeFontSize!'28px'>
<#local codeTracking     = properties.kcTokenEmailCodeLetterSpacing!'6px'>
<#local buttonPadding    = properties.kcTokenEmailButtonPadding!'13px 24px'>

<#-- ---- Branding ------------------------------------------------------
     realmName is the realm's display name when it has one, its technical name
     otherwise. Every mail Keycloak sends provides it. -->
<#local brandName        = realmName!''>
<#local logoUrl          = properties.kcEmailLogoUrl!''>
<#local logoAlt          = properties.kcEmailLogoAlt!''>
<#local logoHeight       = properties.kcEmailLogoHeight!'32'>
<#local showFallback     = (properties.kcEmailLinkFallback!'true') == 'true' && link?? && link?has_content>
<#local lang             = (locale.language)!'en'>
<#local dir              = ((ltr!true)?then('ltr','rtl'))>
<!DOCTYPE html>
<html lang="${lang}" dir="${dir}" xmlns="http://www.w3.org/1999/xhtml">
<head>
    <meta charset="utf-8" />
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <#-- Tells the client which palettes this mail has been designed for.
         Without it, Apple Mail and Outlook auto-invert the colours themselves
         and the @media block below never gets a chance to run. -->
    <meta name="color-scheme" content="${colorScheme}" />
    <meta name="supported-color-schemes" content="${colorScheme}" />
    <title>${brandName}</title>

    <style>
        /* reset */
        body { margin: 0 !important; padding: 0 !important; width: 100% !important; }
        table { border-collapse: collapse; }
        img { border: 0; outline: none; text-decoration: none; -ms-interpolation-mode: bicubic; }
        <#-- Stops iOS and Outlook.com from auto-linking dates, addresses and
             phone numbers in blue — an unwanted second "call to action". -->
        a[x-apple-data-detectors], .kc-email-footer a { color: inherit !important; text-decoration: none !important; }

        <#-- The one part of the mail this template cannot reach with a style
             attribute: it arrives as finished HTML from a message bundle. -->
        /* body copy */
        .kc-prose { font-family: ${fontFamilyCss}; font-size: ${fontSize}; line-height: ${lineHeight}; color: ${colorText}; }
        .kc-prose p { margin: 0 0 ${gap}; }
        .kc-prose p:last-child { margin-bottom: 0; }

        <#-- Every base message body contains exactly one link, and it is
             always the action — so the anchor IS the call-to-action button.
             Rewrite a body message to carry links inside a sentence and you
             will want to narrow this selector. -->
        /* call to action */
        .kc-prose a {
            display: inline-block;
            padding: ${buttonPadding};
            background-color: ${colorPrimary};
            border-radius: ${radiusMd};
            color: ${colorOnPrimary} !important;
            font-weight: ${fontWeightBold};
            text-decoration: none !important;
        }

        <#-- Selected by html/email-verification-with-code.ftl, where the
             message wraps the one-time code in <b>. -->
        /* one-time code */
        .kc-prose--code b {
            display: inline-block;
            margin-top: 4px;
            padding: 12px 20px;
            background-color: ${colorSurfaceMuted};
            border: ${borderWidth} solid ${colorBorder};
            border-radius: ${radiusMd};
            font-family: ${fontFamilyCode};
            font-size: ${codeFontSize};
            letter-spacing: ${codeTracking};
            color: ${colorText};
        }

        /* small screens */
        @media only screen and (max-width: 620px) {
            .kc-email-card td { padding-left: 20px !important; padding-right: 20px !important; }
            .kc-prose a { display: block !important; text-align: center !important; }
        }
<#if colorScheme?contains('dark') && colorScheme?contains('light')>
        <#-- Same tokens as the login theme's dark mode, one layer down: these
             rules have to override INLINE styles, hence !important on every
             declaration. Honoured by Apple Mail, iOS, Outlook for Mac/iOS and
             Thunderbird. Gmail ignores it and applies its own inversion to the
             light palette instead, which is why the light palette has to stand
             on its own. Pin kcTokenColorScheme to `light` to drop this block. -->
        /* dark palette */
        @media (prefers-color-scheme: dark) {
            .kc-email-page { background-color: ${darkBackground} !important; }
            .kc-email-card { background-color: ${darkSurface} !important; border-color: ${darkBorder} !important; }
            .kc-email-card td { color: ${darkText} !important; }
            .kc-email-wordmark { color: ${darkText} !important; }
            .kc-email-rule { border-color: ${darkBorder} !important; }
            .kc-email-muted, .kc-email-footer, .kc-email-footer td { color: ${darkTextMuted} !important; }
            .kc-prose { color: ${darkText} !important; }
            .kc-prose a { background-color: ${darkPrimary} !important; color: ${darkOnPrimary} !important; }
            .kc-prose--code b { background-color: ${darkSurfaceMuted} !important; border-color: ${darkBorder} !important; color: ${darkText} !important; }
            .kc-email-url a { color: ${darkLink} !important; }
        }
</#if>
    </style>

    <#-- Word has no system-ui and silently falls back to Times New Roman.
         Read only by Outlook on Windows. -->
    <!--[if mso]>
    <style>
        body, table, td, p, a, span { font-family: Arial, Helvetica, sans-serif !important; }
    </style>
    <![endif]-->
</head>

<body class="kc-email-page" style="margin: 0; padding: 0; width: 100%; background-color: ${colorBackground};">
<#if preheader?has_content>
    <#-- The grey line the inbox list shows after the subject. Hidden in the
         message itself; the entities pad it so the client does not spill the
         first words of the body into the preview instead. -->
    <div style="display: none; max-height: 0; overflow: hidden; mso-hide: all; font-size: 1px; line-height: 1px; color: ${colorBackground};">
        ${preheader}&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;
    </div>
</#if>

<#-- A full-width table rather than styling <body>: Outlook.com rewrites the
     body element's background away. -->
<table class="kc-email-page" role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width: 100%; background-color: ${colorBackground};">
    <tr>
        <td align="center" style="padding: ${pagePadding};">

            <#-- The card. `width` attribute for Word, max-width for everyone
                 else, so it is fixed at 600px on a desktop client and fluid on
                 a phone. The top accent is the card's own border-top — the
                 same strip as the login card, without an extra table row. -->
            <table class="kc-email-card" role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width: 100%; max-width: ${width}; background-color: ${colorSurface}; border: ${borderWidth} solid ${colorBorder};<#if hasAccent> border-top: ${accentHeight} solid ${colorPrimary};</#if> border-radius: ${radiusLg};">

                <#-- Brand header: the logo when kcEmailLogoUrl points at an
                     absolute https:// URL, the realm display name as a text
                     wordmark otherwise. -->
                <tr>
                    <td align="${(dir == 'rtl')?then('right','left')}" style="padding: ${cardPadding} ${cardPadding} 0; font-family: ${fontFamily};">
                        <#if logoUrl?has_content>
                            <img src="${logoUrl}" alt="${logoAlt?has_content?then(logoAlt, brandName)}" height="${logoHeight}" style="display: block; height: ${logoHeight}px; width: auto; border: 0;" />
                        <#else>
                            <span class="kc-email-wordmark" style="font-family: ${fontFamily}; font-size: 18px; font-weight: ${fontWeightBold}; letter-spacing: -0.01em; color: ${colorText};">${brandName}</span>
                        </#if>
                    </td>
                </tr>

                <#-- The message body. The inline styles here are the floor:
                     they are what the copy inherits in a client that dropped
                     the <style> block. -->
                <tr>
                    <td style="padding: ${cardPadding}; font-family: ${fontFamily}; font-size: ${fontSize}; line-height: ${lineHeight}; color: ${colorText};">
                        <div class="${proseClass}">
                            <#nested>
                        </div>

                        <#if showFallback>
                        <div class="kc-email-rule" style="margin-top: 28px; padding-top: ${gap}; border-top: ${borderWidth} solid ${colorBorder};">
                            <p class="kc-email-muted" style="margin: 0 0 6px; font-family: ${fontFamily}; font-size: ${fontSizeSm}; line-height: ${lineHeight}; color: ${colorTextMuted};">${msg("modernEmailLinkFallback")}</p>
                            <#-- word-break keeps a long signed action URL
                                 inside the card instead of stretching it. -->
                            <p class="kc-email-url" style="margin: 0; font-family: ${fontFamily}; font-size: ${fontSizeXs}; line-height: 1.4; word-break: break-all;"><a href="${link}" style="color: ${colorLink};">${link}</a></p>
                        </div>
                        </#if>
                    </td>
                </tr>
            </table>

            <#-- Footer, outside the card and on the page background: no
                 rounded corner to clip, and it reads as metadata rather than
                 as part of the message. -->
            <table class="kc-email-footer" role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width: 100%; max-width: ${width};">
                <tr>
                    <td align="center" style="padding: ${gap} ${pagePadding} 0; font-family: ${fontFamily}; font-size: ${fontSizeXs}; line-height: 1.6; color: ${colorTextMuted};">
                        ${msg("modernEmailFooter", brandName)}
                    </td>
                </tr>
            </table>

        </td>
    </tr>
</table>
</body>
</html>
</#macro>
