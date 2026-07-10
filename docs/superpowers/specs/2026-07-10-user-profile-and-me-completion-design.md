# User Profile And Me Completion Design

## Goal

Complete the Dexo user preview card, other-user profile page, and current-user Me page with real Discourse or local functionality. Remove placeholder actions rather than retaining controls that only show an unavailable alert.

The implementation remains UIKit-only, supports iOS 15, follows the existing Dexo theme, and reuses current authentication, topic detail, private-message, bookmark, badge, invite, trust-requirement, settings, and WebView flows.

CDK/LDC, Connect statistics, AI services, and metaverse entries are explicitly out of scope.

## Approach

Build a shared capability and relationship layer before wiring individual pages. `DiscourseAPI` and its models own endpoint contracts. A shared user relationship state owns follow, mute, ignore, restore, and permission decisions. The preview card and profile page render the same authoritative state instead of duplicating mutation logic.

Page-by-page patches were rejected because they would duplicate network calls and allow follow or notification state to diverge. Web-only fallbacks were rejected for standard Discourse features because the requested result is a usable native flow.

## Networking And Models

Add typed contracts for the following endpoints:

- `GET /u/{username}/card.json` for card-specific identity, relationship, and action permissions.
- `PUT /follow/{username}` and `DELETE /follow/{username}` for follow state.
- `PUT /u/{username}/notification_level.json` for mute, timed ignore, and notification restoration.
- `POST /posts.json` with `archetype=private_message`, `target_recipients`, `title`, and `raw` for direct messages.
- `GET /user_actions.json` with `username`, `filter`, and `offset` for activity, topics, replies, and likes received.
- `GET /discourse-reactions/posts/reactions.json` for the reactions section.
- `GET /u/{username}/follow/following` and `GET /u/{username}/follow/followers` for social lists.
- `GET /drafts.json` and `DELETE /drafts.json` for current-user drafts.
- Existing topic-list/search contracts for created topics and seen topics where available.

Decoding must tolerate Linux.do response variants and optional plugin fields. Permission fields default to hiding or disabling a destructive action, never to assuming authorization.

## Shared User Relationship State

Introduce one state object per displayed username with:

- Current follow, mute, and ignore state.
- Server capabilities such as private-message, follow, mute, and ignore permission.
- In-flight mutation state used to disable repeated taps.
- Optimistic UI updates with rollback and a visible error when the server rejects the request.

The preview card and full profile page refresh from the same server contracts. Dismissing and reopening either page must not show a stale relationship label after a successful action.

## User Preview Card

Preserve the approved compact visual design and replace placeholder handlers:

- Private message opens the native composer with the recipient prefilled. When a topic context is supplied, the composer also prefills that topic's title and share link; otherwise it starts with an empty title and body.
- Follow toggles between follow and unfollow and shows progress while mutating.
- Overflow contains mute, timed ignore, restore notifications, share user, and other server-permitted actions.
- Actions that the server does not permit are omitted.
- Loading, retry, suspended/silenced indicators, biography, background/flair, and profile navigation remain functional.

## Other-User Profile

Keep the themed hero and rounded content panel, but reduce the oversized typography and replace the static summary-only layout with a real section controller.

The page provides:

- Summary with top topics, top replies, links, frequently interacted users, categories, and badges when returned by summary data.
- Activity using user action filters `4,5`.
- Topics using filter `4`.
- Replies using filter `5`.
- Likes received using filter `1`.
- Reactions using the reactions plugin endpoint.
- Pull to refresh, offset pagination, deduplication, loading footer, empty state, retry, and cancellation-safe state transitions.
- Search scoped to the displayed user, private message, follow, share, mute/ignore/restore, biography detail, and followers/following lists.

Tabs switch the active data source without stacking duplicate views. Topic and post results open existing native topic detail routes.

## Me Page

Retain the current card-based page and add only real entries:

- My Topics: created-topic list with refresh, pagination, scoped search, and topic-detail navigation.
- Drafts: load server drafts, open topic/reply or new-topic editing based on draft type, and delete after confirmation.
- Browsing History: use Discourse seen/read topic data, not the local embedded-browser history.
- In-App Browser: address entry, WebView navigation, local bookmarks, local visit history, delete, and clear actions.
- Profile Statistics: reorder visible metrics, change supported layout mode, persist configuration locally, and use only Discourse/profile data available in Dexo.
- Export History: list successful and failed topic export records, reopen/share existing files, delete individual records, and clear records.

Export history is delivered together with real topic Markdown and HTML export. Adding a history page without a producer is explicitly forbidden. Notion export is not included.

## Local Storage

Use small Codable records persisted below Application Support for browser bookmarks/history and export history. Use `UserDefaults` only for compact profile-stat configuration. Account-specific records include the normalized forum base URL and username to prevent cross-account leakage.

History stores are bounded and deduplicate stable URLs. Missing exported files remain visible as failed/missing records with a delete action rather than crashing or silently disappearing.

## Error And Authentication Behavior

- Auth-required operations route through the existing `AuthGating` flow.
- `401` and `403` refresh or invalidate the current relationship state and show an actionable login/permission message.
- `429` uses the existing friendly rate-limit handling.
- Pagination errors preserve already loaded content and expose a footer retry.
- Mutations disable repeated taps and restore the previous state on failure.
- Removed or unsupported features do not leave visible rows that only show a coming-soon alert.

## Compatibility And Rollout

New Swift files are included through the existing `Project.swift` source glob and require Tuist regeneration before building. Existing dirty worktree changes must be preserved.

Implementation order is shared API/models, preview actions, profile sections/actions, Me content pages, topic export/history, then integration cleanup. Each slice must build before the next slice begins so regressions remain isolated.

## Verification

- Add a lightweight `dexofluxTests` target for pure model, state, and local-store verification without UI dependencies.
- Add decoding tests for representative card, action-page, reaction, social-list, and draft responses.
- Add focused tests for relationship state transitions, pagination deduplication, and account-scoped local stores.
- Verify unavailable-action handlers are no longer connected to visible profile or Me controls.
- Run Tuist generation and an iOS Simulator Debug build.
- Manually verify logged-out, logged-in, permission-denied, empty, pagination, mutation-failure, and missing-export-file states.
