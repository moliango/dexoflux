# Implementation notes

## What changed

1. `dexo/Features/ForumDetail/Me/TrustRequirementsViewController.swift` (new)
   - `ConnectTrustReport` + `ConnectTrustParser` — SwiftSoup port of FluxDo's
     connect.linux.do HTML parsing (card / badge / rings / bars / quotas / vetos /
     status, `--val`/`--max` CSS vars, `empty-state` card).
   - `TrustFallbackCatalog` + `TrustFallbackRequirement` — FluxDo's per-level
     thresholds (L0 / L1 / L2+) driven by `DiscourseUserSummary`; reverse items
     (flags / suspensions) assume 0.
   - `TrustRequirementsViewController` — native page: connect fetch with
     `WebCookieStore` cookie header + stored UA over a no-cookie-jar URLSession
     (mirrors `DiscourseAuthInterceptor`), native cards for report state, summary
     fallback state (any connect failure → fallback; error only if summary also
     fails), pull-to-refresh, retry.
2. `MeViewController.swift`
   - Old WKWebView-based trust page deleted (with the now-unused WebKit import).
   - `openTrustRequirements` passes api / username / trustLevel.
   - Invite creation alert now offers expiry presets 1/7/30/90 天 / 永久
     (`max_redemptions_allowed` stays 1, matching FluxDo).
   - Invite URL call sites use `effectiveURLString(baseURL: api.baseURL)`.
3. `DiscourseUser.swift` — `DiscourseInviteLink.effectiveURLString` is now
   `effectiveURLString(baseURL:)`; hardcoded `https://linux.do` removed.
4. `Project.swift` — app target depends on `.external(name: "SwiftSoup")`;
   `make generate` run.
5. `Localizable.xcstrings` — `invites.create.message` reworded for the new
   expiry-preset flow (en / zh-Hans / zh-Hant / zh-HK). Other new strings use
   `String(localized:defaultValue:)` and will be extracted on next build.
6. `dexofluxTests/TrustRequirementsParsingTests.swift` (new) — connect fixture
   parse, empty-state detection, CF-challenge page → error, fallback threshold
   math (incl. reverse + time_read seconds→minutes), invite URL from key+base.

## Follow-up: FluxDo-style invite page (user request)

- `InviteLinksViewController` extracted from `MeViewController.swift` into its own
  file and rewritten to mirror FluxDo's `invite_links_page.dart` with native cards:
  create card (per-preset summary + 展开/收起选项 + filled create button with
  activity indicator), advanced card (描述 / 限制邮箱 / 可使用次数固定 1 / 有效期
  capsule chips 1/7/30/90 天/永久 in a 3+2 grid), inline rate-limit/error banner,
  latest-link result card (monospace link box + usage/expiry meta chips + 复制/分享
  buttons), empty card. Latest invite derived from the pending list (newest
  created_at); FluxDo's SharedPreferences cache intentionally skipped — pending
  list already recovers the latest link.
- `DiscourseAPI.createInvite` gained optional `email:` (invite restriction).
- SwiftSoup integration fixed earlier: `.external` duplicate → single SPM
  `.remote` package shared with CookedHTML ("Multiple commands produce" resolved).

## Verification

- `xcrun swiftc -parse` clean on all touched files; SwiftSoup API signatures
  verified against the checked-out 2.13.4 sources; `make generate` succeeded.
- Per user preference no simulator build/test was run. Device verification
  pending: trust page needs the user's real linux.do web-session cookies to show
  connect data (fallback shows otherwise); invite flow needs TL≥3 account.
