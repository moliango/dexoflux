# Design — Real trust requirements and invite links

## A. Trust requirements (native)

New file `dexo/Features/ForumDetail/Me/TrustRequirementsViewController.swift`
(replaces the private WKWebView class inside `MeViewController.swift`):

- `ConnectTrustReport` — value model mirroring FluxDo's `TrustLevelData`:
  title, badgeText, badgeKind(success/warning/danger), subtitle,
  rings `[label, current, max, isMet]`, bars `[label, currentText, progress, isMet]`,
  quotas `[label, valueText, isMet, usedSlots]`, vetos `[label, desc, value, isMet]`,
  footerHint, statusText, isStatusMet, isEmptyState(+paragraphs).
- `ConnectTrustParser.parse(html:)` — SwiftSoup port of FluxDo's selector logic:
  `div.card` (throw if missing → caller falls back), `.empty-state` short-circuit,
  `h2.card-title`, `.badge` + class, `.card-subtitle`, `.tl3-ring*` with CSS vars
  `--val/--max` from `style`, `.tl3-bar-item*`, `.tl3-quota-card` (+`.tl3-slot.used`
  count, `unmet`), `.tl3-veto-item` (front/back face by `unmet`), `.text-hint`,
  `.status-met/.status-unmet`.
- `TrustFallbackCatalog.requirements(level:summary:)` — FluxDo's hardcoded
  per-level thresholds (L0/L1/L2+) driven by `DiscourseUserSummary`
  (daysVisited, postsReadCount, topicsEntered, likesGiven, likesReceived,
  postCount, timeRead/60). Reverse items (flags/suspensions) assume 0 current.
- `TrustRequirementsViewController(api:username:trustLevel:baseURL:)`:
  1. If host of baseURL is `linux.do`, fetch `https://connect.linux.do/` via
     URLSession with `Cookie: WebCookieStore.shared.cookieHeader(for:)` and stored
     User-Agent (mirrors `DiscourseAuthInterceptor.applyWebCookieHeaders`).
  2. Parse success + non-empty → native cards: 活动 rings (CAShapeLayer arcs),
     互动 bars (rounded track+fill), 合规 quota/veto tiles, status footer banner.
  3. Parse failure / CF challenge / empty-state / other forum → fallback rows
     (icon + label + `cur / target` + progress bar) from user summary; header notes
     data source. Deviation from FluxDo: network errors also fall back (summary is
     still real data) instead of a dead error page; error UI only if summary also
     fails. Retry via pull-to-refresh + error retry button.
- Layout: UIScrollView + vertical UIStackView of rounded cards, insetGrouped look
  consistent with the Me tab; UIRefreshControl.

## B. Invite links

- `DiscourseInviteLink.effectiveURLString` → `effectiveURLString(baseURL:)`;
  callers in `MeViewController` pass the forum baseURL (api.baseURL).
- Create alert gains expiry presets as alert actions (1/7/30/90 天 / 永久),
  keeping the description text field and `max_redemptions_allowed = 1`
  (FluxDo `_maxRedemptionsAllowed = 1`). `createInvite(description:expiresAt:)`
  already accepts nil expiry for 永久.

## C. Build config

- `Project.swift`: app target gains `.package(product: "SwiftSoup")`; run
  `make generate` (project generation only, no build).

## D. Strings

- New user-facing strings use `String(localized:defaultValue:)` with Chinese
  defaults, following the newest convention in `MeViewController` (plugins rows);
  keys land in `Localizable.xcstrings` at next build.

## E. Check

- `dexofluxTests/TrustRequirementsParsingTests.swift`: connect fixture HTML →
  parsed report values; empty-state fixture → isEmptyState; fallback catalog math
  (met/unmet/progress/reverse); invite URL built from key + custom baseURL.
- Verification: syntax-level only (no simulator run) per user preference.
