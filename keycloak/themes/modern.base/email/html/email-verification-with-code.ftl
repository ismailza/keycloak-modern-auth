<#--
  The one mail whose body is not a link but a code the user has to read off the
  screen and type. base's message wraps it in <b>:

      emailVerificationBodyCodeHtml=<p>Please verify ...</p><p><b>{0}</b></p>

  Bold at body size is not enough for six characters that have to be
  transcribed without a typo, so this override asks the shell for the `code`
  prose variant, which renders that <b> as a monospaced, letter-spaced block.
  The message itself — and its translations — is untouched.

  This is the pattern for any per-mail tweak: copy the file of that name from
  `base` (they are four lines each), and pass the shell a different variant.
  Overriding this template does not disturb the other sixteen.
-->
<#import "template.ftl" as layout>
<@layout.emailLayout proseClass="kc-prose kc-prose--code">
${kcSanitize(msg("emailVerificationBodyCodeHtml",code))?no_esc}
</@layout.emailLayout>
