# Real trust requirements and invite links

## Background

The Me tab has two entries that are currently not real:

1. **信任要求 (Trust Requirements)** — `TrustRequirementsViewController` is a bare
   `WKWebView` hard-loading `https://connect.linux.do/`. With no session cookies the
   page is stuck behind the Cloudflare challenge ("Just a moment…"), so the feature
   never shows real data.
2. **邀请链接 (Invite Links)** — `InviteLinksViewController` calls real endpoints, but
   `DiscourseInviteLink.effectiveURLString` hardcodes `https://linux.do` (wrong for
   other forums) and creation is a bare alert with a fixed 1-day expiry.

Reference implementation: FluxDo (Flutter linux.do client) at
`/Users/naine/Documents/AndroidWorkspace/fluxdo`, files:
- `lib/pages/trust_level_requirements_page.dart` — fetches connect.linux.do with the
  forum session, parses HTML into native cards (rings / bars / quotas / vetos), and
  falls back to `/u/{username}/summary.json`-based requirement progress when connect
  returns an empty state.
- `lib/pages/invite_links_page.dart` + `lib/services/discourse/_users.dart` — GET
  `/u/{username}/invited/pending`, POST `/invites` with
  `max_redemptions_allowed=1`, expiry presets 1/7/30/90 days or never, link built as
  `{baseURL}/invites/{invite_key}` when the response has no link field.

## Requirements

1. Native trust-requirements page fed by real data:
   - For linux.do forums: GET `https://connect.linux.do/` with `WebCookieStore`
     cookie header (parent-domain cookies incl. `cf_clearance` flow to the connect
     subdomain) + stored User-Agent; parse via SwiftSoup into native cards
     (活动 rings, 互动 progress bars, 合规 quota/veto cards, status footer).
   - Fallback (connect blocked / empty-state / non-linux.do forum): build the
     requirement list from `fetchUserSummary` using FluxDo's per-trust-level
     threshold table, rendered as native progress rows.
   - Pull-to-refresh, loading state, error + retry.
2. Invite links made forum-correct and FluxDo-equivalent:
   - `effectiveURLString` uses the forum baseURL instead of hardcoded linux.do.
   - Create flow offers expiry presets (1/7/30/90 天 / 永久) plus optional
     description; keeps `max_redemptions_allowed = 1`.

## Non-goals

- No port of FluxDo's Cloudflare-challenge / cookie-priming machinery.
- No invite revocation (FluxDo does not have it either).
- No change to the TL3 gating of the invite entry.

## Acceptance Criteria

- [ ] Trust page renders native cards from live connect.linux.do data when the web
      session cookies allow it.
- [ ] Trust page renders summary-based fallback rows (with per-level thresholds)
      when connect is unavailable, blocked, or the forum is not linux.do.
- [ ] Invite list/create work against the current forum and copied links use the
      forum's own domain.
- [ ] New user-facing strings are localized (en + zh-Hans).
- [ ] Connect HTML parser and fallback threshold math covered by a unit test.

## Technical notes

- App target needs a direct `SwiftSoup` product dependency in `Project.swift`
  (already in Tuist/Package.swift graph via CookedHTML) + `make generate`.
- `DiscourseAuthInterceptor.applyWebCookieHeaders` is the model for the connect
  request headers; use `WebCookieStore.shared.cookieHeader(for:)` + `userAgent`.
- Verification is lightweight per user preference: syntax-level check only, no
  simulator test run.
