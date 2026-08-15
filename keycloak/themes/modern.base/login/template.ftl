<#--
  MODERN-BASE — page layout for every login screen.

  This is a copy of base/login/template.ftl with four deliberate changes; every
  other line is kept identical so the ~40 pages that call this macro (login,
  register, OTP, WebAuthn, consent, reset password, ...) keep working untouched:

    1. the design-token <style> block, which turns kcToken* properties from
       theme.properties into CSS custom properties (see "DESIGN TOKENS" below);
    2. a logo slot driven by kcLogoUrl, falling back to the realm display name;
    3. a favicon read from kcFaviconUrl instead of a hardcoded path;
    4. the alert icon wrapper, which base hardcodes to a PatternFly class.

  Child themes should not need to copy this file. If you find yourself forking
  it to change a colour or a radius, add a token instead.
-->
<#import "footer.ftl" as loginFooter>
<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html class="${properties.kcHtmlClass!}" lang="${lang}"<#if realm.internationalizationEnabled> dir="${(locale.rtl)?then('rtl','ltr')}"</#if>>

<head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
    <#-- A login page has nothing to offer a crawler, and indexed login URLs
         carrying client_id/redirect_uri parameters are a small privacy leak. -->
    <meta name="robots" content="noindex, nofollow" />

    <#if properties.meta?has_content>
        <#list properties.meta?split(' ') as meta>
            <meta name="${meta?split('==')[0]}" content="${meta?split('==')[1]}"/>
        </#list>
    </#if>
    <title>${msg("loginTitle",(realm.displayName!''))}</title>
    <link rel="icon" href="${url.resourcesPath}/${properties.kcFaviconUrl!'img/favicon.svg'}" />
    <#if properties.stylesCommon?has_content>
        <#list properties.stylesCommon?split(' ') as style>
            <link href="${url.resourcesCommonPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>

    <#-- =====================================================================
         DESIGN TOKENS

         Every `kcToken*` property becomes a CSS custom property on :root, with
         the name converted from camelCase to kebab-case:

             kcTokenColorPrimary=#4f46e5   ->   --kc-color-primary: #4f46e5;
             kcTokenFontSizeSm=0.875rem    ->   --kc-font-size-sm: 0.875rem;

         `kcTokenDark*` properties produce the same variable names inside a
         prefers-color-scheme:dark query, so a dark palette is a set of values,
         not a second stylesheet.

         The loop is what makes this a *base* theme: Keycloak merges parent and
         child theme.properties before handing them over, so a child overriding
         a token — or inventing a new one — needs no change here, and no CSS.

         This block is emitted after the stylesheets on purpose: same specificity
         means the later declaration wins, so tokens always beat any :root block
         a child stylesheet might define.

         ?no_esc is safe and required here: the values are CSS written by the
         theme author (a font stack's quotes would otherwise arrive as &quot;),
         never user input — nothing on this page routes request data into a
         theme property.
    -->
    <style id="kc-design-tokens">
        :root {
        <#list properties?keys?sort as key>
            <#if key?starts_with("kcToken") && !key?starts_with("kcTokenDark") && properties[key]?has_content>
            --kc-${key?remove_beginning("kcToken")?replace("([a-z0-9])([A-Z])", "$1-$2", "r")?lower_case}: ${properties[key]?no_esc};
            </#if>
        </#list>
        }
        <#-- Pinning kcTokenColorScheme to `light` (or `dark`) drops this block
             entirely and locks the theme to a single palette. -->
        <#if (properties.kcTokenColorScheme!'light dark')?contains('dark') && (properties.kcTokenColorScheme!'light dark')?contains('light')>
        @media (prefers-color-scheme: dark) {
            :root {
            <#list properties?keys?sort as key>
                <#if key?starts_with("kcTokenDark") && properties[key]?has_content>
                --kc-${key?remove_beginning("kcTokenDark")?replace("([a-z0-9])([A-Z])", "$1-$2", "r")?lower_case}: ${properties[key]?no_esc};
                </#if>
            </#list>
            }
        }
        </#if>
    </style>

    <#if properties.scripts?has_content>
        <#list properties.scripts?split(' ') as script>
            <script src="${url.resourcesPath}/${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <script type="importmap">
        {
            "imports": {
                "rfc4648": "${url.resourcesCommonPath}/vendor/rfc4648/rfc4648.js"
            }
        }
    </script>
    <script src="${url.resourcesPath}/js/menu-button-links.js" type="module"></script>
    <#if scripts??>
        <#list scripts as script>
            <script src="${script}" type="text/javascript"></script>
        </#list>
    </#if>
    <script type="module">
        import { startSessionPolling } from "${url.resourcesPath}/js/authChecker.js";

        startSessionPolling(
            "${url.ssoLoginInOtherTabsUrl?no_esc}"
        );
    </script>
    <script type="module">
        document.addEventListener("click", (event) => {
            const link = event.target.closest("a[data-once-link]");

            if (!link) {
                return;
            }

            if (link.getAttribute("aria-disabled") === "true") {
                event.preventDefault();
                return;
            }

            const { disabledClass } = link.dataset;

            if (disabledClass) {
                link.classList.add(...disabledClass.trim().split(/\s+/));
            }

            link.setAttribute("role", "link");
            link.setAttribute("aria-disabled", "true");
        });
    </script>
    <#if authenticationSession??>
        <script type="module">
            import { checkAuthSession } from "${url.resourcesPath}/js/authChecker.js";

            checkAuthSession(
                "${authenticationSession.authSessionIdHash}"
            );
        </script>
    </#if>
</head>

<body class="${properties.kcBodyClass!}" data-page-id="login-${pageId}">
<div class="${properties.kcLoginClass!}">
    <#-- Brand slot: an <img> when kcLogoUrl points at a file in
         login/resources/, otherwise the realm's display name as text. A child
         theme rebrands by dropping in its own img/logo.svg — resources resolve
         child-first, so it wins without any property change. -->
    <div id="kc-header" class="${properties.kcHeaderClass!}">
        <div id="kc-header-wrapper" class="${properties.kcHeaderWrapperClass!}">
            <#if properties.kcLogoUrl?has_content>
                <#assign logoAlt = properties.kcLogoAlt!"">
                <#if !logoAlt?has_content>
                    <#assign logoAlt = realm.displayName!"">
                </#if>
                <img class="kc-brand__logo" src="${url.resourcesPath}/${properties.kcLogoUrl}" alt="${logoAlt}" />
            <#else>
                ${kcSanitize(msg("loginTitleHtml",(realm.displayNameHtml!'')))?no_esc}
            </#if>
        </div>
    </div>
    <div class="${properties.kcFormCardClass!}">
        <header class="${properties.kcFormHeaderClass!}">
            <#if realm.internationalizationEnabled  && locale.supported?size gt 1>
                <div class="${properties.kcLocaleMainClass!}" id="kc-locale">
                    <div id="kc-locale-wrapper" class="${properties.kcLocaleWrapperClass!}">
                        <div id="kc-locale-dropdown" class="menu-button-links ${properties.kcLocaleDropDownClass!}">
                            <button tabindex="1" id="kc-current-locale-link" aria-label="${msg("languages")}" aria-haspopup="true" aria-expanded="false" aria-controls="language-switch1">${locale.current}</button>
                            <ul role="menu" tabindex="-1" aria-labelledby="kc-current-locale-link" aria-activedescendant="" id="language-switch1" class="${properties.kcLocaleListClass!}">
                                <#assign i = 1>
                                <#list locale.supported as l>
                                    <li class="${properties.kcLocaleListItemClass!}" role="none">
                                        <a role="menuitem" id="language-${i}" class="${properties.kcLocaleItemClass!}" href="${l.url}">${l.label}</a>
                                    </li>
                                    <#assign i++>
                                </#list>
                            </ul>
                        </div>
                    </div>
                </div>
            </#if>
        <#if !(auth?has_content && auth.showUsername() && !auth.showResetCredentials())>
            <#if displayRequiredFields>
                <div class="${properties.kcContentWrapperClass!}">
                    <div class="${properties.kcLabelWrapperClass!} subtitle">
                        <span class="subtitle"><span class="required">*</span> ${msg("requiredFields")}</span>
                    </div>
                    <div class="col-md-10">
                        <h1 id="kc-page-title"><#nested "header"></h1>
                    </div>
                </div>
            <#else>
                <h1 id="kc-page-title"><#nested "header"></h1>
            </#if>
        <#else>
            <#if displayRequiredFields>
                <div class="${properties.kcContentWrapperClass!}">
                    <div class="${properties.kcLabelWrapperClass!} subtitle">
                        <span class="subtitle"><span class="required">*</span> ${msg("requiredFields")}</span>
                    </div>
                    <div class="col-md-10">
                        <#nested "show-username">
                        <div id="kc-username" class="${properties.kcFormGroupClass!}">
                            <label id="kc-attempted-username">${auth.attemptedUsername}</label>
                            <a id="reset-login" href="${url.loginRestartFlowUrl}" aria-label="${msg("restartLoginTooltip")}">
                                <div class="kc-login-tooltip">
                                    <i class="${properties.kcResetFlowIcon!}"></i>
                                    <span class="kc-tooltip-text">${msg("restartLoginTooltip")}</span>
                                </div>
                            </a>
                        </div>
                    </div>
                </div>
            <#else>
                <#nested "show-username">
                <div id="kc-username" class="${properties.kcFormGroupClass!}">
                    <label id="kc-attempted-username">${auth.attemptedUsername}</label>
                    <a id="reset-login" href="${url.loginRestartFlowUrl}" aria-label="${msg("restartLoginTooltip")}">
                        <div class="kc-login-tooltip">
                            <i class="${properties.kcResetFlowIcon!}"></i>
                            <span class="kc-tooltip-text">${msg("restartLoginTooltip")}</span>
                        </div>
                    </a>
                </div>
            </#if>
        </#if>
      </header>
      <div id="kc-content">
        <div id="kc-content-wrapper">

          <#-- App-initiated actions should not see warning messages about the need to complete the action -->
          <#-- during login.                                                                               -->
          <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
              <#-- base hardcodes a PatternFly class on the icon wrapper; ours
                   comes from kcAlertIconClass so the markup stays framework-free. -->
              <div class="alert-${message.type} ${properties.kcAlertClass!} kc-alert--${message.type}" role="alert">
                  <div class="${properties.kcAlertIconClass!}">
                      <#if message.type = 'success'><span class="${properties.kcFeedbackSuccessIcon!}"></span></#if>
                      <#if message.type = 'warning'><span class="${properties.kcFeedbackWarningIcon!}"></span></#if>
                      <#if message.type = 'error'><span class="${properties.kcFeedbackErrorIcon!}"></span></#if>
                      <#if message.type = 'info'><span class="${properties.kcFeedbackInfoIcon!}"></span></#if>
                  </div>
                      <span class="${properties.kcAlertTitleClass!}">${kcSanitize(message.summary)?no_esc}</span>
              </div>
          </#if>

          <#nested "form">

          <#if auth?has_content && auth.showTryAnotherWayLink()>
              <form id="kc-select-try-another-way-form" action="${url.loginAction}" method="post">
                  <div class="${properties.kcFormGroupClass!}">
                      <input type="hidden" name="tryAnotherWay" value="on"/>
                      <a href="#" id="try-another-way"
                         onclick="document.forms['kc-select-try-another-way-form'].requestSubmit();return false;">${msg("doTryAnotherWay")}</a>
                  </div>
              </form>
          </#if>

          <#nested "socialProviders">

          <#if displayInfo>
              <div id="kc-info" class="${properties.kcSignUpClass!}">
                  <div id="kc-info-wrapper" class="${properties.kcInfoAreaWrapperClass!}">
                      <#nested "info">
                  </div>
              </div>
          </#if>
        </div>
      </div>

      <@loginFooter.content/>
    </div>
  </div>
</body>
</html>
</#macro>
