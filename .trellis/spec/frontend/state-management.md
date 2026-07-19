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
- Data Management preference backups must export/import only local app preferences such as appearance, reading, bottom-bar, pinned-category, DoH, and cache-behavior settings. Do not export login cookies, Cloudflare clearance, user profile cache, image cache, fonts, or database rows through the preferences backup file.
- Data Management cache actions must reflect real storage boundaries: image cache through `SDImageCache`, cookies through `WebCookieStore` plus the matching `WKHTTPCookieStore`, Me profile cache through `MeProfileCacheStore`, and emoji cache through `EmojiStore`.
- Clearing Cookie cache is an auth-affecting action and must invalidate the matching web session instead of only deleting the persisted cookie JSON file.
- Runtime visual settings that affect Topic Detail content must flow through both render paths:
  - Native content: `AppSettings` -> `NativeRenderConfig.default(...)` / `TopicDetailContentStyle`.
  - Web fallback content: `AppSettings` -> `PostContentRenderer.currentWebRenderStyle` -> fallback HTML/CSS.
- Content font family selection lives in `AppSettings.contentFontFamily`. Native cooked-content rendering must use `AppSettings.contentFont(...)`; Web fallback rendering must use `AppSettings.webContentFontFamilyCSS`; Topic Detail must reload visible content when the font family changes.
- Imported custom content fonts are a library, not a single replaceable slot. Store each imported font with a stable id, PostScript name, display name, file name, and import date; keep the selected imported font id separate from `contentFontFamily == .custom`.
- Custom font imports must use unique persisted file names under the app's font storage directory so importing a second custom font does not overwrite the first. Legacy single-slot custom font keys should migrate into the imported-font library.
- Appearance font UI must list system, MiSans, every imported custom font, and a separate "upload custom font" action. Do not make the custom-font choice double as the upload button, because users need to switch among already imported fonts.
- Reading content font size must use `AppSettings.effectiveContentPointSize(for:)` before native or Web fallback rendering. Do not feed `ContentFontSize.basePointSize` directly into Topic Detail text rendering, because the system PingFang font reads larger than imported content fonts at the same point size.
- Topic/Home interface labels that need to visually match imported content fonts must use `AppSettings.effectiveInterfacePointSize(for:)`, not `effectiveContentPointSize(for:)`. The content helper has a reading-body lower bound and can accidentally enlarge small badge labels; interface typography should reduce only body-sized system PingFang text.
- Content font scope lives in `AppSettings.contentFontScope`. The default scope is reading content only; when set to global, the selected content font must also apply to app UI fonts through the shared runtime font override and visible-window refresh path.
- Runtime global interface font scaling must preserve a stable source point size. When `interfaceFontScalePercent` changes, visible-control refresh must derive uncached base fonts from the previous applied multiplier or an explicit source-size marker, never from the new multiplier, and must invalidate intrinsic content size / constraints after replacing fonts.
- Reading settings must expose only settings that are wired to real behavior. `AppSettings.openExternalLinksInAppBrowser` controls whether Topic Detail and Replies open external links in `SFSafariViewController` or hand them to `UIApplication.open(...)`; `AppSettings.defaultExpandRelatedLinks` controls the initial expanded state of Topic Detail related-link cards.
- Runtime visual settings that affect Home or Topic Detail badge/chip colors must use `AppSettings.ThemeStyle` tokens, including tag colors, category colors, selected chip colors, topic-card surfaces, and count badges.
- Topic Detail controllers must listen through the existing observable update path and reload visible content when reading typography or theme settings change.
- Home controllers must observe `AppSettings.shared` when theme settings affect visible cells or header chrome, then refresh chip/header styling and reconfigure visible topic cells.
- Home topic-list cells that assign fonts during setup/configure must route those fonts through an explicit app-interface typography helper, not rely only on the global window-refresh traversal. This is required for reused or newly built cells such as the Xiaohongshu two-column card layout.
- If a Home theme changes the list layout shape, rebuild the diffable snapshot with identifiers that match the active layout. Example: the Xiaohongshu Home card layout uses row identifiers for two-column rows instead of topic-id identifiers; switching themes must call the snapshot rebuild path instead of relying on `tableView.reloadData()`.
- Do not store enum settings with `UserDefaults.integer(forKey:)` alone when the first enum case is not the intended default. Check `object(forKey:)` before interpreting integer `0`.
- App icon style selection lives in `AppSettings.appIconStyle` and must call `UIApplication.setAlternateIconName(...)` through `AppSettings.setAppIconStyle(...)`. Do not present icon choices that are not declared in `Info.plist`, `Project.swift` alternate icon build settings, and `Assets.xcassets`.
- App icon PNG files, including alternate icons, must be opaque RGB images with no alpha channel. If generated artwork is RGBA, convert it before adding it to `.appiconset`; transparent app icons can render as system placeholder/grid icons after `setAlternateIconName(...)`.
- When editing app icon build settings, remember that the generated `dexo.xcodeproj` is ignored by Git but may still be the project currently opened in Xcode. Keep `Project.swift` as the tracked source of truth, then regenerate or update the local `dexo.xcodeproj/project.pbxproj` before manual device testing.

### App Language

- Language selection is persisted in `AppSettings.appLanguage`.
- Runtime language switching is supported. `AppSettings` installs a runtime `Bundle` proxy, applies the selected language immediately, writes `AppleLanguages` for next launch consistency, then calls `notifyChanged()`.
- Visible settings pages must refresh localized titles/rows from `updateUI()` after `AppSettings` changes; pages with localized labels created only during setup should rebuild those labels when `appLanguage` changes.
- Tab bar controllers must update existing tab/root titles on language changes without rebuilding the navigation stack, so users are not kicked out of the current settings page.
- Traditional Chinese language choices use regional preferred language codes (`zh-Hant-TW`, `zh-Hant-HK`) with resource fallbacks (`zh-Hant`, `zh-HK`, `zh-Hans`).
- String catalog Traditional Chinese support must be complete enough to avoid falling back to English after the bundle selects a Traditional Chinese localization. If `zh-Hans` exists for a key, `zh-Hant` and `zh-HK` should exist too.
- Xcode can auto-extract a new `String(localized:defaultValue:)` key with only the English default value. That key compiles successfully but falls back to English in Chinese UI. Every new user-facing action key must add `zh-Hans`, `zh-Hant`, and `zh-HK` values, and profile-action keys are guarded by `LocalizationCoverageTests`.
- If adding new supported language codes to `Localizable.xcstrings`, also add them to `Project.swift` `defaultKnownRegions`.

---

## Server State

<!-- How server data is cached and synchronized -->

### GitHub Release Update Checks

- DexoFlux stable releases use `v{marketingVersion}-build.{buildNumber}` tags. Parse both numeric marketing-version components and the numeric build; do not compare tags as plain strings or drop the build number.
- `AppUpdateService` owns GitHub transport, Release decoding, ETag handling, the one-hour cache, and stale-cache fallback. UIKit controllers must consume `AppRelease` / `AppVersion` instead of decoding GitHub JSON themselves.
- Automatic checks may return a cache younger than one hour without a network request. Manual checks always issue a conditional request, and HTTP `304` refreshes the cached fetch time.
- HTTP `403`, `429`, `5xx`, and transient URL failures may return a stale cached Release. Without a cache, the service must throw so manual checks can show a recoverable localized error; automatic failures remain silent.
- Drafts and prereleases never trigger the stable update prompt. A Release without `dexoflux-unsigned.ipa` remains valid because the GitHub Release page is the supported update destination.
- The primary `ForumContainerViewController` may schedule one automatic check per process only after automatic checking is enabled. Enabling the setting during the current process should trigger the still-unscheduled check.
- Automatic update UI must wait until the launch overlay is removed and the visible controller tree has no login, Cloudflare, composer, or other modal transition. Keep the Release pending while UI is busy and consume it only after presentation succeeds.
- "Update Now" opens the GitHub Release page. Do not imply that DexoFlux can install an unsigned IPA in-app.

### Home Topic List Lifecycle Cancellation

- Home topic-list reloads may race with `DiscourseAPI.resetSession()`, because session reset calls `cancelAllRequests()` on the old Alamofire session while a foreground/background recovery load is still in flight.
- Alamofire explicit cancellation (`AFError.explicitlyCancelled` / `Request explicitly cancelled.`) is lifecycle control flow, not a user-facing network failure. Home must not write it into `errorMessage` or show it as an empty-state error.
- If Home receives an explicit cancellation while the surrounding Swift task is still active, silently clear transient Cloudflare/error state and retry the topic load once after a short delay.
- If the Swift task itself is cancelled, do not retry. Treat it as normal task teardown and keep the existing topic list state.
- This contract applies to both the preflight access check and the actual topic fetch, because either request can be the one cancelled by session reset.

### Me Profile Cache

- The Me tab caches `DiscourseCurrentUser`, `DiscourseUserProfile`, and `DiscourseUserSummary` together per normalized `baseURL + username`.
- The cache is stored on disk under Application Support and expires after 20 minutes.
- Normal Me tab loads may render a fresh cache immediately, then refresh the server data in the background and overwrite the cache on success.
- Pull-to-refresh and explicit reloads must bypass the cache, but they should not blank an already-rendered profile while the request is in flight.
- Logout and web-session invalidation must clear the Me profile cache for that base URL so stale avatar/name/dashboard data cannot appear after account changes or dropped auth.
- Auth failures from Me profile or summary requests (`not_logged_in` / `forbidden`) must clear the cache for that base URL before showing the logged-out state.

### Discourse Web Auth State

- Treat the `_t` cookie as the only proof of a logged-in Discourse web session.
- Do not use `_forum_session` or other `*_session` cookies as login proof; those can exist for anonymous browser sessions.
- When an authenticated API response fails with `401`, `403`, or an empty serialized body, try one forced WebView cookie refresh before clearing local auth state.
- Merge response `Set-Cookie` headers only after Cloudflare and auth-recovery checks, so a transient auth failure cannot delete the recoverable `_t` cookie before recovery runs.
- Cloudflare verification UI must sync only `cf_clearance` from its WebView; never bulk-sync `_t` or `_forum_session` from the challenge page.
- Update the stored WebView `User-Agent` only after Cloudflare verification succeeds, because `cf_clearance` is User-Agent sensitive.
- Treat `WKHTTPCookieStoreObserver` callbacks as high-frequency and potentially overlapping; completion handlers must be serialized and idempotent before posting notifications or dismissing UI.
- The challenge-triggered visible Cloudflare shield entry point is global forum chrome owned by `ForumContainerViewController`. Feature pages such as Home, Topic Detail, Me, Notifications, and Bookmarks must not own page-local shield buttons or challenge-triggered foreground verification presentation; they should only react to completion notifications for their own reload/retry behavior. A deliberate Settings row may still open manual verification.

#### Scenario: Cloudflare Foreground Verification Completion

1. Scope / Trigger
- Trigger: Foreground `CloudflareVerificationViewController` bridges WebView challenge completion into native API retry state.

2. Signatures
- Completion notification: `DiscourseAPI.cloudflareVerificationCompletedNotification`.
- Required `userInfo`: `DiscourseAPI.cloudflareBaseURLUserInfoKey` with the normalized base URL.
- Cookie source: `WebCookieStore.shared.syncFromWebView(..., names: ["cf_clearance"], for: baseURL)`.

3. Contracts
- Capture the initial native `cf_clearance` synchronously before registering `WKHTTPCookieStoreObserver` or starting any async WebView cookie synchronization.
- Regular pages require a usable `cf_clearance`. Dexo's original verified-landing exceptions remain authoritative: an exact same-origin `/challenge` source `404`, a same-origin `/404` redirect, or a loaded Discourse not-found page without active challenge markers may sync Cookie/User-Agent best effort and complete automatically before the WK Cookie callback surfaces the value.
- Do not open avatar, upload, or image resource URLs as the foreground verification target. Binary challenge URLs must fall back to the forum `/challenge` page so WKWebView receives a normal document navigation instead of a stalled Cloudflare image interstitial.
- Foreground completion requires all three conditions: a usable `cf_clearance`, a loaded same-origin verified page, and no active Cloudflare challenge markers.
- Background verification still requires a non-empty `cf_clearance` and a page without active challenge markers before posting completion, because there is no visible user-confirmed landing page.
- Auto-triggered verification after a native Cloudflare challenge must delete stale `cf_clearance` first, then require a fresh value before success.
- Foreground verification is exclusive per forum base URL. Cancel and await the matching background verification attempt before presenting, and ignore new background triggers while the foreground verifier is active.
- Auto-triggered verification follows the original Dexo Cookie flow: capture the initial value only for freshness comparison, delete stale native/WebView `cf_clearance`, and do not restore it after failure or close. Manual Settings verification does not proactively delete the existing value.
- After detecting a usable `cf_clearance`, capture `navigator.userAgent` from the same WebView and store it in `WebCookieStore.shared.userAgent` before native retry.
- Topic Detail and Replies should react to completion by clearing failed avatar-prefetch state, re-prefetching their author avatars with the forum base URL, and reloading only currently visible rows.

4. Validation & Error Matrix
- Exact same-origin `/challenge` source `404` without `cf-mitigated: challenge` -> sync Cookie/User-Agent and complete automatically.
- Same-origin `/404` redirect or recognized Discourse not-found page without active challenge markers -> sync Cookie/User-Agent and complete automatically.
- Other original response URLs without a usable `cf_clearance` -> keep waiting and do not post completion.
- Other redirect/page loaded but `cf_clearance` missing -> keep waiting and do not post completion.
- `cf_clearance` present but active Cloudflare challenge markers still exist -> keep waiting and do not post completion.
- Fresh `cf_clearance` present, verified page loaded, no active challenge markers -> update User-Agent, post completion once, then auto-dismiss if applicable.
- Close without successful verification -> stop verification work and do not post completion; auto-triggered stale clearance remains deleted.

5. Good/Base/Bad Cases
- Good: User completes challenge, WebView receives `cf_clearance`, `ForumContainerViewController` hides the global shield, and page controllers such as Home receive completion notification to retry native data with Cookie + User-Agent headers.
- Base: User opens the verification page from settings and closes it without solving the challenge; settings refreshes status but no completion notification is posted.
- Bad: a background `/404` probe loads without `cf_clearance`; the app must not mark verification complete because native API requests would still hit the shield.

6. Tests Required
- Assert auto verification rejects the unchanged initial `cf_clearance` and accepts a different non-empty value.
- Assert completion requires both a loaded verified page and no active challenge markers.
- Assert same-origin `/404` / Discourse not-found pages without `cf_clearance` do not complete.
- Assert background known verified probes without `cf_clearance` schedule more checks instead of posting completion.
- Assert image responses with `cf-mitigated: challenge` and Cloudflare HTML `403` / `429` / `503` are detected without requiring a response body.
- Assert completion callback execution is idempotent when cookie-store observer, navigation finish, and Done button race.

7. Wrong vs Correct
- Wrong: Treating `/404` or any non-challenge page as success before a usable Cookie exists, or letting background and foreground WebViews mutate the shared Cookie store concurrently.
- Correct: Require Cookie + verified page + no challenge for ordinary completion, serialize foreground/background verification, and keep Dexo's original delete-without-restore behavior for stale auto-triggered clearance.

### Topic Detail Reaction Toggle State

1. Scope / Trigger
- Trigger: Topic Detail toggles Discourse Reactions through the native API and updates an already-rendered post without a full topic reload.

2. Signatures
- Route: `DiscourseRouter.toggleReaction(postId:reactionId:)`.
- Path: `/discourse-reactions/posts/{postId}/custom-reactions/{reactionId}/toggle.json`.
- API: `DiscourseAPI.toggleReaction(postId:reactionId:) async throws -> DiscourseReactionToggleResponse?`.
- State update: `TopicDetailViewModel.updatePostReaction(postId:reactions:reactionUsersCount:currentUserReaction:)`.

3. Contracts
- A `200` response may be the updated Discourse post object, not a minimal reaction-only object.
- `current_user_reaction` identifies the user's selected reaction and may omit `count`; missing `count` must decode as `0`, not as a failed action.
- Reaction ids should prefer `id`, fall back to `name`, and default `type` to `emoji` when the server omits it.
- `reaction_users_count` is the authoritative total when present; otherwise derive the count from `reactions.reduce(0) { $0 + $1.count }`.
- Empty response bodies mean the caller should fall back to a topic reload.

4. Validation & Error Matrix
- `HTTP 2xx` + missing `current_user_reaction.count` -> decode successfully and update the post state.
- `HTTP 2xx` + empty body -> return `nil` so the controller can reload the topic.
- `HTTP non-2xx` -> throw `DiscourseAPIError` and keep the old post state.
- Cloudflare challenge response -> post the challenge notification and throw the Cloudflare challenge error before decoding.
- Malformed non-empty `2xx` body outside the tolerated reaction fields -> throw `DiscourseDecodingError` with route, URL, status, decode path, and body preview.

5. Good/Base/Bad Cases
- Good: User taps `laughing`, server returns a full post with `current_user_reaction` but no `count`, and the UI updates without an error alert.
- Base: Server returns a minimal reaction payload with `reactions`, `reaction_users_count`, and `current_user_reaction`; the UI updates from that payload.
- Bad: UI treats a successful `200` as failure because a display-only reaction field is absent.

6. Tests Required
- Decode a toggle response where `current_user_reaction` has `id` and `type` but no `count`; assert `count == 0`.
- Decode a full post-style toggle response with `reaction_users_count`; assert the response exposes that total.
- Verify `TopicDetailViewModel.updatePostReaction` uses `reactionUsersCount` when present and falls back to summing reaction counts when absent.
- Build the iOS app after changing reaction models because the app does not currently have an app-level XCTest target for networking models.

7. Wrong vs Correct
- Wrong: Require `DiscourseTopicDetail.Reaction.count` for every reaction object and show "Operation failed" when the server omits it from `current_user_reaction`.
- Correct: Treat reaction fields from the toggle endpoint as lossy server state, decode optional display fields defensively, and only surface an error when the request failed or the response is malformed beyond the tolerated contract.

### Scenario: Account-Scoped Me Tools And Draft Restoration

1. Scope / Trigger
- Trigger: A Me feature persists browsing/export data locally or restores a server draft into a native composer.
- Browser history, local bookmarks, profile-stat configuration, and export history are native app state; Discourse read history and drafts remain server state and must not be merged with local WebView history.

2. Signatures
- Account key: `AccountScopeKey.make(baseURL:username:) -> String`.
- Browser store: `BrowserHistoryStore(baseURL:username:directoryURL:maxHistoryCount:)`.
- Export store: `ExportHistoryStore(baseURL:username:directoryURL:)`.
- Draft list: `GET /drafts.json?offset={offset}&limit={limit}`.
- Draft deletion: `DELETE /drafts/{draftKey}.json?sequence={draftSequence}`.
- My topics: `GET /topics/created-by/{username}.json?page={page}`.
- Discourse read history: `GET /read.json?page={page}`.

3. Contracts
- Local account scope is the normalized forum base URL plus lowercased username; missing usernames use the explicit `guest` scope.
- Local browser history is capped at 200 records by default. A repeated normalized URL moves to the front instead of creating a duplicate. URL fragments do not define separate history/bookmark records.
- Browser and export JSON files live under Application Support and use atomic writes. Corrupt files load as empty and are replaced by the next successful mutation.
- Server draft `data` may be either a JSON object or a JSON string containing an object. Preserve title, reply, category id, tags, archetype, action, and target recipients.
- Draft routing is determined by `draft_key`: new-topic keys open `NewTopicComposerViewController`, topic/post keys open `ReplyComposerViewController`, and private-message keys open `PrivateMessageComposerViewController`.
- A successfully submitted restored draft is deleted with its original key and sequence. Failed submission must retain the draft and editor contents.
- Topic exports write Markdown or complete HTML under `Application Support/Exports/{accountScope}` and always add a success/failure history record.

4. Validation & Error Matrix
- Unsupported browser scheme -> reject before `WKWebView.load` and show a localized error.
- Corrupt browser/export JSON -> expose empty state; next write atomically replaces the corrupt file.
- Draft lacks private-message recipient -> do not open an empty recipient composer; show a recoverable error and keep/delete choices.
- Reply draft target is not in the initial topic payload -> resolve the post id from `post_stream.stream`, fetch it, then open the composer; if still missing, show an error.
- Draft delete fails -> keep the row and show the server error.
- Export file is missing but history remains -> show a safe missing-file state; the record must still be deletable.
- Export generation fails -> persist a failure record with the error and do not present a fake share sheet.

5. Good/Base/Bad Cases
- Good: `HTTPS://LINUX.DO/ + Sam` and `https://linux.do + sam` read the same local history while `alex` reads an isolated history.
- Base: a guest opens the in-app browser; local records stay in the guest scope and do not leak into a later authenticated account.
- Bad: one global `UserDefaults` array stores URLs for every account, or a restored draft opens an empty composer because its string-encoded `data` was ignored.

6. Tests Required
- Assert account isolation, base-URL normalization, URL deduplication, fragment removal, history bounds, corrupt-file recovery, and bookmark uniqueness.
- Assert legacy `me.stats.selected` order migrates to `MeStatsConfiguration(layout: .grid)` and the new configuration round-trips.
- Assert new-topic, topic/post reply, private-message, and unsupported draft keys map to the correct destination.
- Assert Markdown removes cooked HTML tags while retaining readable text, and HTML escapes topic/author metadata while preserving cooked post markup.
- Run the complete app unit-test scheme plus a Simulator Debug build after changing any of these contracts.

7. Wrong vs Correct
- Wrong: Treat `/read.json` as WebView history, delete drafts through `DELETE /drafts.json`, or key local records only by username.
- Correct: Keep server and local history separate, delete `/drafts/{key}.json?sequence=N`, and scope local files by normalized `baseURL + username`.

### Scenario: Discourse User Summary Badge Sideloads

1. Scope / Trigger
- Trigger: Decode `GET /u/{username}/summary.json` for Me or another user's profile summary.

2. Signatures
- Response model: `DiscourseUserSummaryResponse`.
- Embedded field: `user_summary.badges`.
- Sideloaded definitions: root `badges`.

3. Contracts
- `user_summary.badges` may contain reference objects with only `badge_id` and `count`; it is not guaranteed to contain `DiscourseBadge.name`.
- Complete display definitions are taken from the response root `badges` array and merged into `DiscourseUserSummary.badges`.
- Partial embedded references must never fail decoding of the entire user summary.

4. Validation & Error Matrix
- Embedded badge reference lacks `name` -> ignore it as a full definition and continue decoding.
- Root badge definition contains `id`, `name`, and `badge_type_id` -> expose it in the merged summary.
- Root badge definitions are missing -> expose an empty summary badge list rather than failing Me/Profile loading.

5. Good/Base/Bad Cases
- Good: embedded `{badge_id: 1, count: 2}` plus root `{id: 1, name: "Anniversary"}` renders `Anniversary`.
- Base: no badge fields returns an empty badge section.
- Bad: decoding `user_summary.badges` directly as `[DiscourseBadge]` throws `keyNotFound(name)` and blocks the entire Me page.

6. Tests Required
- Decode a response with embedded badge references and sideloaded root definitions; assert the merged name and id.
- Keep the existing complete-root-badge summary decoding regression.

7. Wrong vs Correct
- Wrong: Make `DiscourseBadge.name` globally optional or replace missing names with empty strings.
- Correct: Tolerate reference-shaped embedded entries and preserve strict complete badge definitions at the root boundary.

---

## Common Mistakes

<!-- State management mistakes your team has made -->

(To be filled by the team)
