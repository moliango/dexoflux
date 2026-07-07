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
- Content font family selection lives in `AppSettings.contentFontFamily`. Native cooked-content rendering must use `AppSettings.contentFont(...)`; Web fallback rendering must use `AppSettings.webContentFontFamilyCSS`; Topic Detail must reload visible content when the font family changes.
- Runtime visual settings that affect Home or Topic Detail badge/chip colors must use `AppSettings.ThemeStyle` tokens, including tag colors, category colors, selected chip colors, topic-card surfaces, and count badges.
- Topic Detail controllers must listen through the existing observable update path and reload visible content when reading typography or theme settings change.
- Home controllers must observe `AppSettings.shared` when theme settings affect visible cells or header chrome, then refresh chip/header styling and reconfigure visible topic cells.
- If a Home theme changes the list layout shape, rebuild the diffable snapshot with identifiers that match the active layout. Example: the Xiaohongshu Home card layout uses row identifiers for two-column rows instead of topic-id identifiers; switching themes must call the snapshot rebuild path instead of relying on `tableView.reloadData()`.
- Do not store enum settings with `UserDefaults.integer(forKey:)` alone when the first enum case is not the intended default. Check `object(forKey:)` before interpreting integer `0`.
- App icon style selection lives in `AppSettings.appIconStyle` and must call `UIApplication.setAlternateIconName(...)` through `AppSettings.setAppIconStyle(...)`. Do not present icon choices that are not declared in `Info.plist`, `Project.swift` alternate icon build settings, and `Assets.xcassets`.
- When editing app icon build settings, remember that the generated `dexo.xcodeproj` is ignored by Git but may still be the project currently opened in Xcode. Keep `Project.swift` as the tracked source of truth, then regenerate or update the local `dexo.xcodeproj/project.pbxproj` before manual device testing.

### App Language

- Language selection is persisted in `AppSettings.appLanguage`.
- Runtime language switching is supported. `AppSettings` installs a runtime `Bundle` proxy, applies the selected language immediately, writes `AppleLanguages` for next launch consistency, then calls `notifyChanged()`.
- Visible settings pages must refresh localized titles/rows from `updateUI()` after `AppSettings` changes; pages with localized labels created only during setup should rebuild those labels when `appLanguage` changes.
- Tab bar controllers must update existing tab/root titles on language changes without rebuilding the navigation stack, so users are not kicked out of the current settings page.
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

#### Scenario: Cloudflare Foreground Verification Completion

1. Scope / Trigger
- Trigger: Foreground `CloudflareVerificationViewController` bridges WebView challenge completion into native API retry state.

2. Signatures
- Completion notification: `DiscourseAPI.cloudflareVerificationCompletedNotification`.
- Required `userInfo`: `DiscourseAPI.cloudflareBaseURLUserInfoKey` with the normalized base URL.
- Cookie source: `WebCookieStore.shared.syncFromWebView(..., names: ["cf_clearance"], for: baseURL)`.

3. Contracts
- A normal forum page, `/404`, or a non-challenge redirect is not proof of verification by itself.
- Verification success requires a non-empty `cf_clearance` matching the forum base URL before posting the completion notification.
- Auto-triggered verification after a native Cloudflare challenge must delete stale `cf_clearance` first, then require a fresh value before success.
- After detecting a usable `cf_clearance`, capture `navigator.userAgent` from the same WebView and store it in `WebCookieStore.shared.userAgent` before native retry.

4. Validation & Error Matrix
- Redirect/page loaded but `cf_clearance` missing -> keep waiting and do not post completion.
- `cf_clearance` present but active Cloudflare challenge markers still exist -> keep waiting and do not post completion.
- `cf_clearance` present, no active challenge markers -> update User-Agent, post completion once, then auto-dismiss if applicable.
- Manual close without `cf_clearance` -> close the sheet only; do not pretend native API verification succeeded.

5. Good/Base/Bad Cases
- Good: User completes challenge, WebView receives `cf_clearance`, Home receives completion notification, hides shield, and retries native topics with Cookie + User-Agent headers.
- Base: User opens the verification page from settings and closes it without solving the challenge; settings refreshes status but no completion notification is posted.
- Bad: `/404` loads without `cf_clearance`; the app must not mark verification complete because native API requests would still hit the shield.

6. Tests Required
- Assert that `completeVerification()` is reachable only after `WebCookieStore` has a non-empty `cf_clearance` for the base URL.
- Assert known verified redirects without `cf_clearance` schedule more checks instead of posting completion.
- Assert completion callback execution is idempotent when cookie-store observer, navigation finish, and Done button race.

7. Wrong vs Correct
- Wrong: Treating `webView.url?.path == "/404"` as success and posting `cloudflareVerificationCompletedNotification` immediately.
- Correct: Use `/404` only as a hint to drain WebView cookies; post completion only after `cf_clearance` is available and active challenge markers are absent.

---

## Common Mistakes

<!-- State management mistakes your team has made -->

(To be filled by the team)
