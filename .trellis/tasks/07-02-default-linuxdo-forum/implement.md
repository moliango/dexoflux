# Implementation Plan

## Checklist

### Phase 1.2 Single-Site Launch

1. Add a Linux.do default forum contract.
   - Define the canonical base URL `https://linux.do`.
   - Provide a DB helper that returns the existing Linux.do row or inserts one without network access.

2. Route app launch directly to Linux.do.
   - Update `SceneDelegate` to use the persisted Linux.do forum.
   - Use `ForumContainerViewController` as the root so users land in Home/Me/Search rather than a forum list.
   - Add a root-mode option to hide overlay minimize/close UI.

3. Remove active multi-site UI.
   - Keep existing source files if needed for later cleanup, but remove the launch path to `ForumListViewController`.
   - Hide/disable the add-forum action if `ForumListViewController` is reached accidentally.

4. Validate.
   - Parse changed Swift files.
   - Validate localization JSON if touched.
   - Attempt project generation/build if sandbox allows it.

### Phase 1.1 Home Style

1. Update `HomeViewController` header.
   - Replace the current centered segmented control with a stacked header.
   - Add a search capsule button.
   - Add a horizontal category tab strip.
   - Add compact filter/sort chip controls for latest/hot/top and category access.
   - Keep existing load, refresh, category, and segment/list-mode behavior wired.

2. Update `TopicCell` styling.
   - Add an inset rounded card container.
   - Preserve avatar, emoji title rendering, reply count, category, and time.
   - Adjust typography, spacing, colors, and badge treatment to match FluxDo's compact card feel.

3. Update localization keys as needed.
   - Add keys for search placeholder and compact filter labels if existing keys are insufficient.
   - Preserve English and Simplified Chinese values.

4. Verify behavior.
   - Build the project or run the closest available static/build validation.
   - Confirm no source files use hardcoded user-facing strings introduced by this task.
   - Confirm home topic loading, refresh, pagination, and tap-to-detail paths still compile.

## Validation Commands

- `make generate` only if `Project.swift` or Tuist project structure changes. Expected not needed.
- `xcodebuild` may be used if the generated Xcode project is available locally.
- `cd Packages/CookedHTML && swift test` is available but only covers the local HTML parser package, not the app UI.

## Risk Points

- `HomeViewController.viewDidLayoutSubviews` currently computes manual top inset around the segmented control; header changes must update this or table content will slide under the header.
- `TopicCell` currently depends on direct content-view constraints; introducing a card container requires moving constraints carefully.
- FluxDo has richer topic fields than this native model. Do not invent unread/tags/like data without API/model support.

### Phase 1.3 Home Refinement

1. Update topic-list data and cell badges.
   - Decode optional `tags` from topic-list responses.
   - Replace the plain category label with compact category/tag badge views.
   - Render only real API tags and cap visible tags if needed to keep card rows compact.

2. Replace the home filter row.
   - Use a FluxDo-style dropdown chip for `latest` / `hot` / `top`.
   - Keep category filtering available as a matching dropdown chip and continue syncing it with the horizontal category tabs.
   - Preserve existing refresh, pagination, and detail navigation.

3. Remove Home top chrome.
   - Hide the navigation bar while the Home root is visible to remove the "Home"/"首页" title and root circle affordance.
   - Restore navigation chrome for pushed screens and other tabs.

4. Validate.
   - Parse changed Swift files.
   - Validate localization JSON if touched.
   - Run whitespace diff check.

### Phase 1.4 iOS 15 Compatibility

1. Verify the root cause.
   - Confirm local target declarations still say iOS 17.0.
   - Search for iOS 17-only runtime APIs, especially Swift Observation.
   - Treat README/upstream claims as untrusted until the current code supports them.

2. Lower deployment targets.
   - Set the Tuist app target to iOS 15.0.
   - Set `Packages/CookedHTML` to iOS 15.0.
   - Update README minimum target wording to iOS 15.0.

3. Replace Observation usage.
   - Add a small iOS 15-compatible observable base.
   - Replace `@Observable` view models/auth/settings with that base.
   - Replace `withObservationTracking` in view controllers with notification observation.
   - Add `notifyChanged()` calls after async and synchronous state mutations that should refresh UI.

4. Validate.
   - Ensure no unguarded `@Observable` / `withObservationTracking` remains.
   - Parse changed Swift files.
   - Run whitespace diff check.
   - Attempt Tuist generation/build if sandbox permissions allow it.

## Rollback

- Revert changes to `HomeViewController.swift`, `TopicCell.swift`, and localization entries if the home screen regresses.

### Phase 1.5 Topic Detail FluxDo Parity

1. Compare FluxDo detail components.
   - Use `topic_detail_page.dart`, `topic_post_list.dart`, `post_item.dart`, `post_links.dart`, and default onebox builders as the visual/product reference.
   - Keep native UIKit/MVVM ownership in this app.

2. Extend detail data contracts.
   - Add a tolerant `link_counts` model to `DiscourseTopicDetail.Post`.
   - Add tolerant `boosts` / `can_boost` models to `DiscourseTopicDetail.Post`.
   - Preserve decode success when `link_counts` is absent or contains partially missing fields.
   - Preserve decode success when boost data is absent or partially missing.

3. Rework native post item presentation.
   - Add an inset rounded post surface in `PostNativeCell`.
   - Move header/content/footer/separator inside the surface while preserving current interactions.
   - Keep avatar, flair, user title, reply target, reactions, bookmark, copy link, reply, and unsupported-source copy behavior.

4. Add related-link rendering.
   - Build a collapsible related-link card below content when `link_counts` contains internal reflection links with titles.
   - Deduplicate by title/URL and route taps through `postCell(didTapLinkURL:)`.
   - Add localized labels for related links and remaining-link count.

5. Add Boost rendering.
   - Build a compact boost bubble strip below cooked content when `boosts` is non-empty.
   - Extract readable display text from boost cooked HTML and group identical boost content.
   - Show boost user avatars and a count badge for grouped boosts.
   - Defer create/delete/flag boost actions.

6. Improve onebox card styling.
   - Keep `OneboxRenderer` parser contract.
   - Update `OneboxCardView` to use FluxDo-like rounded muted preview card styling and full-card tap behavior.

7. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Validate `Localizable.xcstrings` JSON.
   - Run `git diff --check`.

### Phase 1.6 Topic Detail Content And Loading Parity

1. Record the FluxDo references.
   - Use `post_item_skeleton.dart`, `topic_detail_page.dart`, `topic_post_list.dart`, `chunked_html_content.dart`, `segmented_long_post.dart`, and the cooked-content builders as the product/visual reference.
   - Keep native UIKit ownership in `TopicDetailViewController`, `PostNativeCell`, and `NativeContent/*`.

2. Add the initial loading skeleton.
   - Create a UIKit skeleton view near topic-detail code.
   - Render a topic header skeleton plus several post item skeleton cards.
   - Show it while the topic is initially loading and no ready table data exists.
   - Hide the table and bottom actions until content is ready or an error is shown.

3. Improve native content text rhythm.
   - Add paragraph style support to the app-side render config.
   - Apply line height and paragraph spacing to paragraph, heading, list, quote, details, and table text where practical.
   - Avoid changing `CookedHTML` parser contracts unless app-side styling is insufficient.

4. Restyle native content blocks.
   - Update blockquote and Discourse quote surfaces to FluxDo-like muted cards with a left rail.
   - Update code block surface, language badge, padding, and line rhythm.
   - Update details card header/body/divider styling.
   - Update table border/header/separator styling.
   - Update image and fallback placeholders to skeleton-like rounded surfaces.

5. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Run `swift test` for `Packages/CookedHTML` only if the package code changes.
   - Validate `Localizable.xcstrings` JSON if touched.
   - Run `git diff --check`.

### Phase 1.7 Home Interaction Parity

1. Record the FluxDo references.
   - Use `topics_screen.dart` for FAB/create behavior.
   - Use `topics_page.dart` / `_TopicsHeaderDelegate` for scroll direction and collapsible header behavior.

2. Add minimal native new-topic support.
   - Add `DiscourseAPI.createTopic(title:raw:categoryId:tags:)`.
   - Reuse `/posts.json` through `DiscourseRouter.createTopic`.
   - Add `NewTopicComposerViewController` with title, body, optional category, send/cancel, and completion callback.
   - Keep drafts, preview, AI review, and tag picking deferred.

3. Add Home FAB behavior.
   - Add a right-bottom floating action button in `HomeViewController`.
   - Normal mode: plus icon opens the composer through `AuthGating`.
   - Refresh mode: refresh icon scrolls to top and reloads topics.
   - Switch modes from scroll direction: toward top = refresh, deeper = create.

4. Update Home header behavior.
   - Extend header background to `view.topAnchor` so the status area has the same surface color.
   - Move the search row closer to the safe-area top.
   - Collapse the search row based on scroll offset while keeping category/filter controls visible.
   - Keep content insets synchronized with the dynamic header height.

5. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Validate `Localizable.xcstrings` JSON.
   - Lint `dexo.xcodeproj/project.pbxproj` if a new Swift file is added.
   - Run `git diff --check`.

### Phase 1.8 Home Bugfixes

1. Confirm current regressions from the screenshot and native code.
   - Check `TopicCell` trailing count badge and card constraints.
   - Check `HomeViewController` table scroll indicator and content inset behavior.
   - Check `ForumTabBarController` for the remaining search tab / `UISearchTab`.
   - Re-check user correction: the remaining card issue is title-driven height/self-sizing behavior, not width.

2. Fix the home list visuals.
   - Hide the vertical scroll indicator.
   - Keep topic cards compact with stable Auto Layout self-sizing based on the title's actual line count.
   - Replace the plain numeric count label with an icon-plus-count chip.
   - Give the count chip an explicit width based on digit count so it cannot stretch during reuse.
   - Use gray styling for normal counts and yellow/orange styling for high counts.

3. Remove bottom search tab.
   - Keep Home and Me as the bottom tabs.
   - Keep search reachable from the Home search capsule.
   - Avoid leaving stale title arrays or navigation controller indexes that assume three tabs.

4. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Run `git diff --check`.

### Phase 1.9 Tag Badge And 429 UX

1. Compare/reference FluxDo.
   - Attempt to read FluxDo topic badge code.
   - If sandbox approval blocks it, record the blocker and use the documented FluxDo direction already captured in `design.md`.

2. Improve tag badges.
   - Keep category badges driven by real Discourse category color.
   - Add a tag icon to topic tags.
   - Add deterministic local tag colors based on tag name because the topic-list API currently exposes tag names only.
   - For Home topic-card category badges, prefer category display records from `/site.json` / FluxDo-style `site.categories`.
   - Centralize category display-name normalization in `DiscourseCategory` or the category data owner; do not append `LV` in `TopicCell`.
   - Ensure the green-marked badge row in Home renders category chips with level text when Linux.do category data provides it, while ordinary topic tag chips remain unchanged.

3. Improve rate-limit errors.
   - Detect HTTP 429 in `DiscourseAPI.request` before decoding.
   - Throw a localized `DiscourseAPIError` with `rate_limited` type.
   - Validate that Home and other existing view models surface `error.localizedDescription` without showing decode internals.

4. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse`.
   - Validate `Localizable.xcstrings` as JSON.
   - Run `git diff --check`.

### Phase 1.9.1 Home Tab Bar Scroll Animation

1. Compare/reference FluxDo.
   - Use `barVisibilityProvider` and `_AnimatedBottomNav` as the product behavior reference.
   - Keep native UIKit ownership in `ForumTabBarController` and `HomeViewController`.

2. Add a native tab bar animation API.
   - Add a `ForumTabBarController` method that hides/shows the tab bar with a vertical transform.
   - Keep hidden-state tracking inside the tab bar controller.
   - Recompute the hidden transform after layout changes.

### Phase 3 Me/Profile Card Page

1. Compare/reference FluxDo.
   - Use `profile_page.dart` for mobile card flow and action grouping.
   - Use `profile_stats_card.dart`, `profile_stats_config.dart`, and `profile_stats_provider.dart` for stats card behavior.
   - Keep native UIKit/MVVM ownership and do not port Flutter/Riverpod.

2. Replace the Me page shell.
   - Upgrade `MeViewController` from an inset grouped table to a `UIScrollView` + vertical stack card layout.
   - Keep helper views private in `MeViewController.swift` to avoid unregistered-target issues.
   - Preserve existing `MeViewModel` profile/summary loading and `AuthGating` login/logout behavior.

3. Add profile and stats cards.
   - Show avatar, display name, username, and trust-level chip in a top profile card.
   - Add a stats card fed by `DiscourseUserSummary` and `DiscourseUserProfile`.
   - Persist visible-stat selection in `UserDefaults`.
   - Defer full drag ordering, layout mode, and alternate data-source configuration pages.

4. Add account action card.
   - Route private messages to `MessagesViewController`.
   - Route bookmarks to `BookmarksViewController`.
   - Route app settings to `SettingsViewController`.
   - Use `SFSafariViewController` fallbacks for badges, trust requirements, and invite links until native pages exist.
   - Disable invite links below trust level 3 with a visible hint.

5. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse`.
   - Validate `Localizable.xcstrings` JSON.
   - Run `git diff --check`.
   - Attempt broader type/build validation if the local Xcode project and sandbox allow it.

3. Wire Home scroll direction.
   - In `HomeViewController.scrollViewDidScroll`, hide the tab bar on upward finger swipes.
   - Show the tab bar on downward finger swipes or when the list reaches the top.
   - Restore the tab bar in `viewWillDisappear` so the state does not leak to pushed screens or other tabs.

4. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse`.
   - Run `git diff --check`.

### Phase 1.9.4 Detail Tag And Scrollbar Follow-Up

1. Share tag color logic.
   - Add a small ForumDetail-level tag visual style helper for deterministic tag colors.
   - Update Home topic tags to use the shared helper instead of a private palette.

2. Restyle topic-detail tags.
   - Keep the existing topic-detail header flow layout and tag tap behavior.
   - Change detail tag chips from gray plain pills to colored `tag.fill` icon chips with a subtle border.

3. Hide detail scroll indicators.
   - Disable the main topic-detail table view's vertical and horizontal scroll indicators.
   - Leave inline code/content scroll behavior intact.

4. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse`.
   - Run `git diff --check`.

### Phase 1.9.3 Incoming Topic Banner

1. Compare/reference FluxDo.
   - Use `topics_page.dart` `_buildNewTopicIndicator`, `topic_list_provider.dart` `loadBefore`, and `message_bus/topic_tracking_providers.dart` `LatestChannelNotifier`.
   - Record that the highlighted behavior is a latest-list incoming banner, not a filter dropdown.

2. Add native incoming-topic fetch support.
   - Add a `/latest.json?topic_ids=...` route to `DiscourseRouter`.
   - Add a matching `DiscourseAPI.fetchTopicsByIds(...)` method.

3. Add Home incoming state.
   - Track incoming topic IDs in `HomeViewModel`.
   - Poll the current latest page as a temporary fallback for FluxDo's MessageBus incoming detection.
   - Detect topics that appear before the current first topic in latest mode.
   - Fetch incoming topics by ID, remove duplicates from the current list, prepend them, and clear the incoming state.

4. Add the Home banner UI.
   - Render a table header row above the first topic with localized "查看 N 个新的或更新的话题".
   - Match FluxDo's light blue surface, arrow-up icon, rounded shape, and tap behavior.
   - Keep the banner hidden outside latest mode or when no incoming topics exist.

5. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse`.
   - Validate `Localizable.xcstrings` as JSON.
   - Run `git diff --check`.

### Phase 2 Notifications

1. Compare FluxDo notification code.
   - Use `notification_quick_panel.dart` for the home-triggered panel behavior.
   - Use `notifications_page.dart` for the reusable full page behavior.
   - Use `notification_item.dart`, `notification_list_skeleton.dart`, `notification_navigation.dart`, `_notifications.dart`, and `models/notification.dart` for row shape, loading state, navigation, and API/model contracts.

2. Extend native notification data/API contracts.
   - Make `DiscourseNotificationList` tolerant of missing optional pagination metadata.
   - Add optional fields needed by rows and navigation: user id, post number, high priority, fancy title, acting-user avatar template, and richer `data` fields.
   - Add Discourse mark-read endpoints for one notification and all notifications if low-risk.

3. Build the reusable native notification page.
   - Replace the placeholder in `NotificationsViewController` with a real `UITableView`.
   - Add a private notification cell and skeleton/empty/error states in the same file to avoid new project registration churn.
   - Add title, close behavior for modal usage, pull-to-refresh, retry, login prompt, and mark-all-read action.
   - Keep the controller usable as a full page for a future tab by not hard-coding Home-specific behavior.

4. Wire Home entry.
   - Enable `notificationButton`.
   - Present `NotificationsViewController` in a navigation controller as a sheet from the Home search row.
   - On notification topic selection, dismiss/push into `TopicDetailViewController` through Home's navigation controller.

5. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse`.
   - Validate `Localizable.xcstrings` JSON.
   - Run `git diff --check`.

### Phase 2.1 Bookmarks List

1. Compare FluxDo bookmark code.
   - Use `bookmarks_page.dart` and `bookmarks_list_content.dart` to understand the product direction.
   - Keep native UIKit ownership and do not port FluxDo's workspace/search/edit architecture.

2. Upgrade the reusable native bookmarks page.
   - Keep `BookmarksViewController` as the implementation target.
   - Add an initializer suitable for a future tab root that resolves the username through `AuthGating`.
   - Preserve the existing Me-page push initializer and detail navigation.
   - Add loading, empty, error, retry, and login-required states.

3. Restyle bookmark rows.
   - Rework `BookmarkCell` into a Home-like rounded card.
   - Show avatar, title, bookmark chip/name, relative time, and cleaned excerpt when available.
   - Use automatic row height and avoid fake category/tag/reply data that the bookmark endpoint does not provide.

4. Validate.
   - Parse changed Swift files with `xcrun swiftc -frontend -parse`.
   - Validate `Localizable.xcstrings` JSON if touched.
   - Run `git diff --check`.

### Phase 4.1 Account Features And Settings

1. Compare FluxDo account pages.
   - Use `private_messages_page.dart`, `my_badges_page.dart`, `trust_level_requirements_page.dart`, `invite_links_page.dart`, and `settings_page.dart` as the behavior and layout references.
   - Keep native UIKit/MVVM ownership; do not port Flutter routing, Riverpod providers, or renderer abstractions.

2. Extend Discourse API and tolerant models.
   - Add private-message filters for inbox, sent, and archive endpoints.
   - Add user badge decoding for `/user-badges/{username}.json?grouped=true`, joining `badges`, `user_badges`, and `topics` at the model boundary.
   - Add pending-invite and create-invite routes with tolerant response decoding.
   - Fix bookmark avatar decoding for direct `avatar_template`, `post_user_avatar_template`, and nested `user.avatar_template`.

3. Upgrade Me account feature routes.
   - Replace web/Safari fallbacks for private messages, badges, trust requirements, and invite links with native or in-app pages.
   - Keep helper controllers private inside `MeViewController.swift` to avoid new Swift files missing project target registration.
   - Route private-message and badge-related topic taps into `TopicDetailViewController` when a topic id is available.

4. Build the usable account pages.
   - Private messages: one table with a segmented control for inbox, sent, and archive, reusing `TopicCell` and the existing topic-detail navigation.
   - My badges: grouped table sections by gold, silver, and bronze badge types, with empty/loading/error states.
   - Invite links: pending invite list, one-day invite creation, copy/share/open actions, and friendly empty/error states.
   - Trust requirements: in-app `WKWebView` wrapper for `https://connect.linux.do/`; defer full native parsing.

5. Restructure settings around real local settings/actions.
   - Settings root shows FluxDo-like categories: appearance design, reading design, network settings, bottom bar design, and data management.
   - Appearance exposes the existing dark-mode setting.
   - Reading exposes comfort reading and scroll-indicator behavior, wired into topic-detail rendering/chrome.
   - Network keeps the existing DoH toggle, provider, and custom URL settings.
   - Bottom bar exposes the existing Home scroll auto-hide behavior.
   - Data management clears SDWebImage image cache and preserves the existing auto-open toggle.

6. Validate.
   - Parse the touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Validate `Localizable.xcstrings` as JSON.
   - Run `git diff --check` on the touched files.
   - Do not claim a full Xcode build unless a generated project exists and sandbox constraints allow it.

### Phase 4.2 Manual Cloudflare Challenge

1. Compare FluxDo Cloudflare handling.
   - Use `cf_challenge_service.dart`, `cf_challenge_interceptor.dart`, `cf_verify_card.dart`, and boundary cookie sync code as the behavior reference.
   - Mirror the product contract, not the Flutter/Riverpod/Windows/headless architecture.

2. Extend native cookie support.
   - Keep `WebCookieStore` as the single native cookie store used by Alamofire requests.
   - Add helpers to detect whether a usable `cf_clearance` exists for Linux.do.
   - Sync `WKWebsiteDataStore` cookies into `WebCookieStore` at the verification boundary.

3. Add manual verification UI.
   - Add a Network settings row for Cloudflare verification.
   - Present a UIKit `WKWebView` controller that loads Linux.do's challenge URL.
   - Detect `cf_clearance`, persist cookies/user-agent, and show success/failure state.

4. Improve API error classification.
   - Detect `cf-mitigated: challenge` and Cloudflare HTML/body markers before decode errors.
   - Throw a localized `DiscourseAPIError` with a Cloudflare-specific type and manual verification guidance.
   - Keep existing 429 rate-limit behavior when the response is not a Cloudflare challenge.

5. Validate.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Validate `Localizable.xcstrings` JSON.
   - Run `git diff --check`.

### Phase 4.3 Home Layout And Tab Bar Fallback

1. Investigate the screenshot regression.
   - Check Home dynamic header height, table top/bottom insets, incoming-topic banner table header, and bottom tab bar appearance.
   - Confirm whether the issue is data loading, layout, or tab bar surface transparency before editing.

2. Fix Home table geometry.
   - Replace one-off top inset updates with a single `updateTableInsets()` method.
   - Update top and bottom insets together and keep scroll indicator insets aligned.
   - Preserve visible scroll position when the header height changes.

3. Stabilize incoming-topic banner layout.
   - Update the banner view/frame when needed.
   - Reassign `tableHeaderView` only when the header view is newly installed or size changes.

4. Fix tab bar fallback surface.
   - Move tab bar appearance ownership to `ForumTabBarController`.
   - Use default/Liquid Glass behavior on supported systems.
   - Use opaque `systemBackground` fallback on systems without Liquid Glass.

5. Validate.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse`.
   - Run `git diff --check`.

### Phase 4.4 Automatic Cloudflare Verification Popup

1. Compare FluxDo CF auto-popup flow.
   - Use `cf_challenge_interceptor.dart` and `cf_challenge_service.dart` as the product behavior reference.
   - Mirror detection, foreground manual verification, cookie sync, and recovery signaling without porting Dio/Riverpod architecture.

2. Add native challenge notifications.
   - Add `DiscourseAPI.cloudflareChallengeDetectedNotification` and base URL userInfo keys.
   - Post the notification from every existing CF challenge detection branch before throwing `DiscourseAPIError(errorType: "cloudflare_challenge")`.

3. Reuse the existing verification page globally.
   - Make `CloudflareVerificationViewController` module-visible while keeping it in the existing settings source file to avoid target-registration risk.
   - Add an `autoDismissOnSuccess` option for API-triggered modal presentation.
   - Broadcast `cloudflareVerificationCompletedNotification` only after `cf_clearance` is detected and synced.

4. Present from the forum container.
   - Observe CF challenge notifications in `ForumContainerViewController`.
   - Ignore notifications for other base URLs.
   - Present a navigation-controller sheet with the verification page.
   - Deduplicate concurrent API failures with an active-sheet flag and reset it on completion/dismiss.

5. Recover Home after verification.
   - Observe `cloudflareVerificationCompletedNotification` in `HomeViewController`.
   - Reload Home topics when the notification matches the current API base URL.

6. Validate.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Validate `Localizable.xcstrings` JSON.
   - Run `git diff --check`.

7. Fix stale-clearance false positives.
   - Add `WebCookieStore` helpers to read and delete a single named cookie for a base URL.
   - Snapshot the initial `cf_clearance` before loading the verification page.
   - For API-triggered automatic verification, delete only `cf_clearance` from both native and WebView cookie stores before loading `/challenge`.
   - Treat verification as complete only when a non-empty `cf_clearance` exists, differs from the initial value, and the page body no longer contains active Cloudflare challenge markers.
   - Re-run Swift parsing, localization JSON validation, and `git diff --check`.

### Phase 4.6 Avatar Loading Reliability

1. Confirm the avatar-loading root cause.
   - Search every `sd_setImage`, `avatar_template`, and avatar URL construction call site.
   - Verify whether call sites differ on `//cdn...`, absolute URL, and relative URL handling.
   - Compare FluxDo's failed-image cache eviction behavior.

2. Add one native avatar-loading boundary.
   - Create `AvatarImageLoader` near Core image-loading code.
   - Resolve `avatar_template` consistently for absolute, scheme-relative, and relative paths.
   - Use SDWebImage options that retry failed URLs and keep background/cache behavior.
   - Configure SDWebImage downloader concurrency once during app launch.

3. Replace avatar call sites.
   - Home, category, tag, private-message, bookmark, notification, search, profile, and topic-detail avatars use the shared resolver/loader.
   - Keep non-avatar content image loaders unchanged unless they are direct avatar surfaces.
   - Keep placeholders visible for missing avatars.

4. Validate.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Run `git diff --check`.

### Phase 4.7 Incoming Topic Banner Hardening

1. Re-check FluxDo's incoming topic path.
   - Confirm `/latest.json?topic_ids=1,2,3` parameter format.
   - Confirm `loadBefore(...)` removes duplicates and prepends returned topics.
   - Confirm MessageBus state tracks incoming IDs per category.

2. Harden native incoming detection.
   - Keep the existing polling fallback for now.
   - Detect topic IDs before the current first row.
   - Also detect updated existing topics by comparing post/reply count and last-post timestamp.
   - Avoid unsafe dictionary construction that could crash on duplicate topic IDs.

3. Refresh lifecycle hooks.
   - Run the detector after Home startup load, filter/category reloads, login refresh, FAB refresh, and CF verification recovery.
   - Keep the 30-second timer for ongoing background affordance.

4. Validate.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Run `git diff --check`.

### Phase 4.9 Topic Reading Tracking

1. Compare FluxDo tracking behavior.
   - Use `_topics.dart`, `_presence.dart`, and `screen_track.dart` as the product/API reference.
   - Mirror the Discourse protocol, not FluxDo's Flutter/Riverpod implementation.

2. Add topic visit tracking.
   - Extend topic detail fetch so `/t/{id}.json` can be requested with `track_visit=true`.
   - Add `Discourse-Track-View: 1` and `Discourse-Track-View-Topic-Id` headers for tracked detail loads.
   - Make `TopicDetailViewModel.loadTopic` use the tracked detail fetch.

3. Add timing upload support.
   - Add `DiscourseAPI.sendTopicTimings(topicId:topicTime:timings:)`.
   - POST `/topics/timings` as form data with `topic_id`, `topic_time`, and `timings[postNumber]`.
   - Keep Cloudflare detection and cookie/header handling consistent with existing API requests.
   - Treat timing failures as silent background sync failures.

4. Track visible posts in the native detail page.
   - Add a private tracker inside `TopicDetailViewController.swift`.
   - Tick visible `postNumber` values once per second while the screen is active.
   - Refresh visible post numbers from `indexPathsForVisibleRows`, `willDisplay`, `didEndDisplaying`, and scrolling.
   - Flush about every minute and on `viewWillDisappear` / `deinit`.

5. Validate.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Run `git diff --check` on touched files.
   - Do not claim a full Xcode build unless sandbox constraints allow it.

### Phase 5.1.1 Topic Detail Layout And Native Radial Controls

1. Re-check FluxDo and current native detail surfaces.
   - Use FluxDo `topic_detail_page.dart`, `topic_post_list.dart`, `PostItem`, `PostSegmentFrame`, `topic_bottom_bar.dart`, `topic_progress_gestures.dart`, and `progress_gesture_action_meta.dart` as product references.
   - Use native `TopicDetailViewController.swift`, `PostNativeCell.swift`, `TopicDetailBottomBar.swift`, `TopicDetailViewModel.swift`, and cooked-content renderers as implementation surfaces.
   - Confirm which existing detail actions must be preserved before replacing any UI.

2. Restyle detail reading layout.
   - Increase detail body typography and line height while respecting Dynamic Type / reading comfort behavior.
   - Tune `PostNativeCell` card padding, minimum height, separators, and avatar/header spacing toward FluxDo's compact `PostSegmentFrame` feel.
   - Keep comments/replies card-like; allow the first/main topic content to use a lighter treatment if it improves reading flow.
   - Avoid fake fixed heights for long cooked content; self-sizing remains required.

3. Replace the floating bottom action strip.
   - Convert `TopicDetailBottomBar` from four equal circular buttons into a centered floor/progress control with the current floor and total floor/progress.
   - Keep an explicit tap path to the current floor/timeline jump flow.
   - Preserve OP-only/filter behavior only if it still has a clear place; otherwise defer it rather than cramming it into the radial menu.

4. Build native radial action menu.
   - Add a UIKit overlay view near topic-detail code for upper-semicircle radial actions.
   - Use native gestures, haptics, blur/dim overlay, item highlight while dragging, release-to-trigger, and dead-zone cancellation.
   - First-pass actions: open timeline, scroll to top, reply topic, bookmark topic, share topic link.
   - Reuse existing reply composer, bookmark API where available, and `UIActivityViewController` for share-link.

5. Preserve back navigation and scrolling.
   - Keep `UINavigationController.interactivePopGestureRecognizer` working on the detail page.
   - If adding a custom left-swipe recognizer, make it directional and fail for vertical movement so table scrolling remains reliable.
   - Verify the detail page still has no visible bottom tab bar.

6. Validate behavior.
   - Open a normal topic, long topic, short-reply topic, and comment-heavy topic.
   - Check radial menu actions: timeline, top, reply, bookmark, share.
   - Check preserved post actions: reply-to-post, bookmark post, reactions, boost, links, image taps, tag taps, reading timing flush.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Run `git diff --check`.

### Phase 5.1.2 Home Topic Category Tab Manager

1. Re-check FluxDo category-tab behavior.
   - Use FluxDo `topics_page.dart`, `pinned_categories_provider.dart`, and `widgets/topic/category_tab_manager_sheet.dart` as behavior references.
   - Confirm the target is the Topic/Home category tab row below search, not the topic-detail page.

2. Add pinned-category persistence.
   - Store pinned category IDs in `AppSettings` / `UserDefaults`.
   - Keep the default pinned list empty so the search-below row starts as "全部" only, matching FluxDo's `pinned_category_ids` default behavior.

3. Update the Home category tab row.
   - Change `HomeViewController.rebuildCategoryTabs()` to render "全部" plus pinned categories resolved by `HomeViewModel`.
   - Keep the existing full category dropdown for all categories and subcategories.
   - Preserve `HomeViewModel.categoryDisplayName(for:)` so Linux.do level names remain correct.

4. Add native category manager UI.
   - Add a three-line Home header button near the notification button.
   - Present a UIKit sheet with "我的分类" and "全部分类" sections.
   - Let tapping a pinned category hide it from the search-below tabs, and tapping an available category add it.

5. Clean up wrong-scope detail work if present.
   - Remove any topic-detail right-side filter menu or action-post cell added for the mistaken requirement.
   - Keep topic-detail system action posts hidden by default through the existing visible-post filtering path.

6. Validate.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Validate `Localizable.xcstrings` JSON.
   - Run `git diff --check` on touched files.

### Phase 5.3 Dynamic Forum Bottom Bar

1. Add bottom-bar preference state.
   - Add a stable `AppSettings` enum for dynamic forum tab items.
   - Persist the ordered item id list in `UserDefaults`.
   - Sanitize unknown ids, duplicates, empty lists, and over-limit lists at the settings boundary.

2. Rebuild the forum tab bar from the registry.
   - Keep Home fixed first and Me fixed last.
   - Insert only the first three configured dynamic entries between them so UIKit never falls into the system `More` tab.
   - Reuse existing native pages for categories, search, notifications, messages, and bookmarks.
   - Preserve selected tab by stable identifier when settings change.

3. Add the settings editor.
   - Add a Bottom Bar settings row for layout.
   - Build a native editor with enabled and available sections.
   - Lock Home in the enabled list, hide Me from the editor, and support delete/add/reorder for dynamic feature entries.
   - Add a restore-default action.

4. Fix container assumptions.
   - Remove old two-tab title/index assumptions from `ForumContainerViewController`.
   - Do not clear root navigation bar actions from dynamic root pages such as notifications.

5. Validate.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Run `git diff --check` on touched files.

### Phase 6 Lightweight DoH

1. Add testable pure boundaries first.
   - Add an HTTP CONNECT request parser with tests or a repeatable parse validation.
   - Add JSON DoH response decoding with TTL extraction and address filtering.
   - Keep these pieces independent from `NWConnection` callbacks.

2. Add the DoH resolver.
   - Define provider metadata for AliDNS, DNSPod, Cloudflare, Google, Quad9, and custom URL.
   - Use JSON DoH requests for `A` and `AAAA` records.
   - Add TTL-aware cache, in-flight request coalescing, and provider failover.
   - Limit supported hostnames to Linux.do-related hosts in the first pass.

3. Add the local CONNECT proxy.
   - Use `Network.framework` (`NWListener` / `NWConnection`) on loopback with an automatically assigned port.
   - Parse `CONNECT host:port HTTP/1.1`.
   - Resolve allowed hosts through `DohResolver`.
   - Connect to the resolved IP with the requested port and pipe bytes bidirectionally.
   - Reject unsupported methods and disallowed hosts.

4. Add lifecycle service.
   - Add a shared service that starts/stops the local proxy from `AppSettings.dohEnabled` and provider changes.
   - Expose current port, running state, and last error.
   - Restart when settings change.

5. Wire Alamofire.
   - Update `DiscourseAPI.makeSession` to apply `connectionProxyDictionary` only when the local proxy is running.
   - Keep direct-session fallback if the proxy fails to start.
   - Avoid proxying WebView login/challenge flows in this phase.

6. Keep settings functional.
   - Reuse the existing DoH toggle, provider, and custom URL rows.
   - Reload/refresh affected sessions after settings change where existing architecture allows.
   - Defer a full DNS cache/status UI.

7. Validate.
   - Run pure parser/decoder tests or repeatable validation scripts.
   - Parse touched Swift files with `xcrun swiftc -frontend -parse` where practical.
   - Generate/build the project if the local Tuist/Xcode environment is available.
   - Run `git diff --check`.
