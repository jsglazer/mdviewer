# Security Policy

## Supported versions

Only the latest released version of mdview receives fixes. Please update to the
newest release before reporting an issue.

## Reporting a vulnerability

Please report security issues privately rather than opening a public issue:

- Use GitHub's **"Report a vulnerability"** button (Security tab → Privately report
  a vulnerability): <https://github.com/jsglazer/mdviewer/security/advisories/new>
- or open a regular issue **without** sensitive details and ask for a private channel.

Please include reproduction steps and the app version. We aim to acknowledge reports
within 14 days and to release a fix in a subsequent version.

## Scope & threat model

mdview is a macOS app that opens and renders **untrusted** Markdown files, including
files handed to it by other applications.

- Markdown is rendered in a sandboxed `WKWebView`; the renderer and math/syntax
  assets are bundled locally. The app makes **no network requests** and does not
  transmit document contents anywhere.
- Image and local-file references resolved while rendering are constrained to the
  document's directory; path-traversal (`../`) outside that directory is rejected
  (see `ImageSchemeHandler`).
- The Markdown input path is additionally exercised by fuzz targets under `Fuzz/`
  (see the OSS-Fuzz setup) to catch crashes on malformed input.
