# State Management

> How state is managed in this project.

---

## Overview

<!--
Document your project's state management conventions here.

Questions to answer:
- What state management solution do you use?
- How is local vs global state decided?
- How do you handle server state?
- What are the patterns for derived state?
-->

(To be filled by the team)

---

## State Categories

<!-- Local state, global state, server state, URL state -->

(To be filled by the team)

---

## When to Use Global State

<!-- Criteria for promoting state to global -->

(To be filled by the team)

### App Settings

- User-facing app settings live in `AppSettings.shared` and must call `notifyChanged()` after mutation.
- Runtime visual settings that affect Topic Detail content must flow through both render paths:
  - Native content: `AppSettings` -> `NativeRenderConfig.default(...)` / `TopicDetailContentStyle`.
  - Web fallback content: `AppSettings` -> `PostContentRenderer.currentWebRenderStyle` -> fallback HTML/CSS.
- Runtime visual settings that affect Home or Topic Detail badge/chip colors must use `AppSettings.ThemeStyle` tokens, including tag colors, category colors, selected chip colors, topic-card surfaces, and count badges.
- Topic Detail controllers must listen through the existing observable update path and reload visible content when reading typography or theme settings change.
- Home controllers must observe `AppSettings.shared` when theme settings affect visible cells or header chrome, then refresh chip/header styling and reconfigure visible topic cells.
- Do not store enum settings with `UserDefaults.integer(forKey:)` alone when the first enum case is not the intended default. Check `object(forKey:)` before interpreting integer `0`.

### App Language

- Language selection is persisted in `AppSettings.appLanguage`.
- Runtime language switching is not supported; changing language writes `AppleLanguages` and shows a restart-required notice.
- Traditional Chinese language choices use regional preferred language codes (`zh-Hant-TW`, `zh-Hant-HK`) with resource fallbacks (`zh-Hant`, `zh-HK`, `zh-Hans`).
- String catalog Traditional Chinese support must be complete enough to avoid falling back to English after the bundle selects a Traditional Chinese localization. If `zh-Hans` exists for a key, `zh-Hant` and `zh-HK` should exist too.
- If adding new supported language codes to `Localizable.xcstrings`, also add them to `Project.swift` `defaultKnownRegions`.

---

## Server State

<!-- How server data is cached and synchronized -->

### Discourse Web Auth State

- Treat the `_t` cookie as the only proof of a logged-in Discourse web session.
- Do not use `_forum_session` or other `*_session` cookies as login proof; those can exist for anonymous browser sessions.
- When an authenticated API response fails with `401`, `403`, or an empty serialized body, try one forced WebView cookie refresh before clearing local auth state.
- Merge response `Set-Cookie` headers only after Cloudflare and auth-recovery checks, so a transient auth failure cannot delete the recoverable `_t` cookie before recovery runs.
- Cloudflare verification UI must sync only `cf_clearance` from its WebView; never bulk-sync `_t` or `_forum_session` from the challenge page.
- Update the stored WebView `User-Agent` only after Cloudflare verification succeeds, because `cf_clearance` is User-Agent sensitive.
- Treat `WKHTTPCookieStoreObserver` callbacks as high-frequency and potentially overlapping; completion handlers must be serialized and idempotent before posting notifications or dismissing UI.

---

## Common Mistakes

<!-- State management mistakes your team has made -->

(To be filled by the team)
