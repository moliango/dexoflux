# User Profile And Me Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all placeholder actions in the user preview/profile surfaces and complete the current-user Me tools with real Discourse or account-scoped local behavior.

**Architecture:** Extend the typed Discourse boundary first, then share relationship state between the preview and full profile pages. Build profile paging, current-user content tools, browser storage, and export storage as focused modules that existing UIKit controllers compose. Existing authentication, topic detail, message, badge, invite, bookmark, trust, settings, and theme infrastructure remains authoritative.

**Tech Stack:** Swift 5, UIKit, iOS 15, Alamofire, WebKit, Codable, UserDefaults/Application Support, Tuist, XCTest.

---

## File Map

- Create `dexo/Networking/Models/DiscourseUserActivity.swift` for card capability, relationship, action-page, reaction, social-list, and draft models.
- Modify `dexo/Networking/Models/DiscourseUser.swift` and `DiscourseUserSummary.swift` for card/profile/full-summary fields.
- Modify `dexo/Networking/DiscourseRouter.swift` and `DiscourseAPI.swift` for all new typed endpoints and empty-response mutations.
- Create `UserRelationshipController.swift` and `PrivateMessageComposerViewController.swift` for shared relationship actions.
- Modify `UserProfileViewModel.swift`, `UserProfilePreviewViewController.swift`, and `UserProfileViewController.swift` to consume real state.
- Create `UserProfileContentViewModel.swift`, `UserProfileContentView.swift`, and `UserSocialListViewController.swift` for profile tabs and social lists.
- Create `MeContentViewControllers.swift`, `DraftsViewController.swift`, `InAppBrowserViewController.swift`, `BrowserHistoryStore.swift`, and `ProfileStatsEditorViewController.swift` for Me tools.
- Modify `NewTopicComposerViewController.swift` and `ReplyComposerViewController.swift` to restore draft content.
- Create `dexo/Features/ForumDetail/Export/TopicExportService.swift`, `ExportHistoryStore.swift`, and `ExportHistoryViewController.swift`.
- Modify `TopicDetailViewController.swift`, `MeViewController.swift`, `Localizable.xcstrings`, and `Project.swift` for integration.
- Create `dexofluxTests` model/state/store tests and fixtures.

### Task 1: Test Target And Typed Models

**Files:**
- Modify: `Project.swift`
- Create: `dexo/Networking/Models/DiscourseUserActivity.swift`
- Modify: `dexo/Networking/Models/DiscourseUser.swift`
- Modify: `dexo/Networking/Models/DiscourseUserSummary.swift`
- Create: `dexofluxTests/UserProfileModelsTests.swift`

- [ ] **Step 1: Add the test target and failing decoding tests**

Add a Tuist unit-test target with `@testable import dexoflux`. Cover a card payload with absent plugin fields, `user_actions`, array-wrapped reactions, followers, drafts whose `data` is a JSON string, and full summary sideloads.

```swift
func testCardDefaultsMissingCapabilitiesToNil() throws {
    let data = Data(#"{"user":{"id":1,"username":"sam","trust_level":2}}"#.utf8)
    let response = try JSONDecoder().decode(DiscourseUserCardResponse.self, from: data)
    XCTAssertEqual(response.user.username, "sam")
    XCTAssertNil(response.user.canFollow)
}
```

- [ ] **Step 2: Verify the tests fail before models exist**

Run `mise exec -- tuist generate`, then:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -workspace dexoflux.xcworkspace -scheme dexofluxTests -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: failure because the new response/model types are undefined.

- [ ] **Step 3: Implement exact model contracts**

Define card, action, reaction, follow-user, draft-list, draft, and draft-data models. Reactions must decode a top-level array or object wrapper. Draft `data` must decode from either a JSON string or object.

```swift
struct DiscourseUserActionResponse: Decodable {
    let userActions: [DiscourseUserAction]
    enum CodingKeys: String, CodingKey { case userActions = "user_actions" }
}

struct DiscourseDraftData: Codable {
    let title: String?
    let reply: String?
    let categoryId: Int?
    let tags: [String]
    let action: String?
    let archetypeId: String?
    let targetRecipients: String?
}
```

Extend `DiscourseUserProfile` with biography variants, seen/read fields, relationship permissions/state, moderation fields, and flair colors. Extend summary decoding with replies, links, interacted users, categories, and sideloaded badges/topics.

- [ ] **Step 4: Run model tests**

Expected: the `dexofluxTests` scheme builds and decoding tests pass.

### Task 2: Discourse Routes And API Methods

**Files:**
- Modify: `dexo/Networking/DiscourseRouter.swift`
- Modify: `dexo/Networking/DiscourseAPI.swift`
- Modify: `dexofluxTests/UserProfileModelsTests.swift`

- [ ] **Step 1: Add route expectation tests**

```swift
XCTAssertEqual(DiscourseRouter.userCard(username: "sam").path, "/u/sam/card.json")
XCTAssertEqual(DiscourseRouter.follow(username: "sam").method, .put)
XCTAssertEqual(DiscourseRouter.unfollow(username: "sam").method, .delete)
```

- [ ] **Step 2: Add router cases and shared empty-response handling**

Add card, follow/unfollow, notification-level, actions, reactions, social-list, drafts, created-topic, and paged-read routes. Add `requestVoid(route:parameters:)` that preserves cookie merge, auth recovery, Cloudflare detection, 429 handling, and decoded API errors while accepting an empty successful body.

- [ ] **Step 3: Add public API contracts**

```swift
func fetchUserCard(username: String) async throws -> DiscourseUserProfile
func followUser(username: String) async throws
func unfollowUser(username: String) async throws
func updateUserNotificationLevel(username: String, level: String, expiringAt: Date?) async throws
func sendPrivateMessage(to username: String, title: String, raw: String) async throws -> DiscourseCreatePostResponse
func fetchUserActions(username: String, filter: String, offset: Int) async throws -> [DiscourseUserAction]
func fetchUserReactions(username: String, beforeReactionUserId: Int?) async throws -> [DiscourseUserReaction]
func fetchFollowing(username: String) async throws -> [DiscourseFollowUser]
func fetchFollowers(username: String) async throws -> [DiscourseFollowUser]
func fetchDrafts(offset: Int, limit: Int) async throws -> DiscourseDraftListResponse
func deleteDraft(key: String, sequence: Int) async throws
func fetchCreatedTopics(username: String, page: Int) async throws -> DiscourseTopicList
```

- [ ] **Step 4: Build the app target**

Expected: `BUILD SUCCEEDED` before any UI wiring.

### Task 3: Shared Relationship State And Private Messages

**Files:**
- Create: `dexo/Features/ForumDetail/Me/UserRelationshipController.swift`
- Create: `dexo/Features/ForumDetail/Me/PrivateMessageComposerViewController.swift`
- Create: `dexofluxTests/UserRelationshipControllerTests.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] **Step 1: Write state transition tests**

Test follow success, rollback, mute, ignore with expiry, restore, permission visibility, and repeated-tap suppression through an injected service protocol.

```swift
protocol UserRelationshipServicing {
    func followUser(username: String) async throws
    func unfollowUser(username: String) async throws
    func updateUserNotificationLevel(username: String, level: String, expiringAt: Date?) async throws
}
```

- [ ] **Step 2: Implement the relationship controller**

```swift
enum UserRelationshipMutation { case toggleFollow, mute, ignore(until: Date), restore }

@MainActor
final class UserRelationshipController: DexoObservableObject {
    private(set) var state: State
    func apply(profile: DiscourseUserProfile)
    func perform(_ mutation: UserRelationshipMutation) async
}
```

Use optimistic updates, disable repeated mutations, restore the previous state on failure, and retain the error for UI display.

- [ ] **Step 3: Implement native direct-message composer**

Add recipient, title, and body fields; require non-empty title/body; disable dismissal while sending; keep text after failure; call `sendPrivateMessage`; dismiss on success.

- [ ] **Step 4: Run relationship tests and app build**

### Task 4: Wire The User Preview Card

**Files:**
- Modify: `dexo/Features/ForumDetail/Me/UserProfileViewModel.swift`
- Modify: `dexo/Features/ForumDetail/Me/UserProfilePreviewViewController.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] **Step 1: Load card/profile/summary without duplicated ownership**

Load card capabilities, full profile, and summary in parallel. Merge card-only relationship values into one `UserRelationshipController`.

- [ ] **Step 2: Replace all unavailable handlers**

Message opens the composer. Follow toggles follow state. Overflow contains only permitted mute, ignore, restore, and share actions. Ignore presets are one day, one week, one month, and custom date.

- [ ] **Step 3: Render relationship and moderation state**

Update follow labels/icons, show suspended/silenced status, and hide relationship actions for the current user's own card or denied permissions.

- [ ] **Step 4: Build and inspect card geometry**

Expected: approved compact dimensions remain and no visible preview action calls `unavailableActionTapped`.

### Task 5: Profile Section Paging

**Files:**
- Create: `dexo/Features/ForumDetail/Me/UserProfileContentViewModel.swift`
- Create: `dexo/Features/ForumDetail/Me/UserProfileContentView.swift`
- Modify: `dexo/Features/ForumDetail/Me/UserProfileViewController.swift`
- Modify: `dexo/Features/ForumDetail/Me/UserProfileUI.swift`

- [ ] **Step 1: Add paging-state tests**

Cover filter mapping (`4,5`, `4`, `5`, `1`), action deduplication, reaction cursor paging, refresh reset, preserved content after load-more failure, and end-of-list detection.

- [ ] **Step 2: Implement section state**

```swift
enum UserProfileSection: CaseIterable { case summary, activity, topics, replies, likesReceived, reactions }

@MainActor
final class UserProfileContentViewModel: DexoObservableObject {
    private(set) var section: UserProfileSection = .summary
    private(set) var rows: [UserProfileContentRow] = []
    func select(_ section: UserProfileSection) async
    func refresh() async
    func loadMoreIfNeeded(currentIndex: Int) async
}
```

- [ ] **Step 3: Implement typed table rows**

Render summary topics/replies/links/users/categories/badges, actions, and reactions. Resolve topic id/post number and open the existing topic detail route.

- [ ] **Step 4: Replace static tabs**

Keep the themed hero/panel, reduce oversized hero fonts, make tabs horizontally scrollable on narrow phones, and swap actual content instead of pushing placeholders.

- [ ] **Step 5: Verify refresh, pagination, retry, and empty states**

### Task 6: Complete Profile Actions And Social Lists

**Files:**
- Create: `dexo/Features/ForumDetail/Me/UserSocialListViewController.swift`
- Modify: `dexo/Features/ForumDetail/Me/UserProfileViewController.swift`
- Modify: `dexo/Features/ForumDetail/Search/SearchViewController.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] **Step 1: Implement followers/following list**

Show avatar/name/username with refresh, retry, empty state, and navigation to another native profile.

- [ ] **Step 2: Wire hero/navigation actions**

Follow uses shared state, message opens the composer, overflow exposes permitted relationship actions plus share, biography opens a cooked-HTML/plain-text sheet, and social stats open their lists.

- [ ] **Step 3: Add user-scoped search**

Allow `SearchViewController` to accept `@{username} order:latest` as its editable initial query.

- [ ] **Step 4: Audit fake profile handlers**

Run `rg -n "unavailableActionTapped" dexo/Features/ForumDetail/Me/UserProfileViewController.swift`.

Expected: no visible action target remains.

### Task 7: My Topics And Discourse Browsing History

**Files:**
- Create: `dexo/Features/ForumDetail/Me/MeContentViewControllers.swift`
- Modify: `dexo/Features/ForumDetail/Me/MeViewController.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] **Step 1: Implement reusable paged topic list**

Configure it with a loader closure. Reuse `TopicCell`, refresh, next-page loading, topic-id deduplication, error footer, and topic-detail navigation.

- [ ] **Step 2: Add My Topics**

Load `/topics/created-by/{username}.json?page=N` and expose scoped search.

- [ ] **Step 3: Add Discourse browsing history**

Load `/read.json?page=N`; keep it separate from local WebView history.

- [ ] **Step 4: Add auth-gated Me rows**

### Task 8: Drafts And Composer Restoration

**Files:**
- Create: `dexo/Features/ForumDetail/Me/DraftsViewController.swift`
- Modify: `dexo/Features/ForumDetail/Home/NewTopicComposerViewController.swift`
- Modify: `dexo/Features/ForumDetail/TopicDetail/ReplyComposerViewController.swift`
- Modify: `dexo/Features/ForumDetail/Me/MeViewController.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] **Step 1: Implement draft list and deletion**

Load `/drafts.json?offset=0&limit=20`, render title/excerpt/time/type, refresh, and confirm `DELETE /drafts/{draftKey}.json?sequence=N`.

- [ ] **Step 2: Add initial-value composer contracts**

```swift
init(api: DiscourseAPI, categories: [DiscourseCategory], initialCategoryId: Int?, initialTitle: String = "", initialRaw: String = "", initialTags: [String] = [])
init(api: DiscourseAPI, topicId: Int, replyToPost: DiscourseTopicDetail.Post?, initialRaw: String = "")
```

- [ ] **Step 3: Route draft types**

New topic opens the topic composer. Topic/post reply keys load the topic and open the reply composer with the correct target. Private-message keys open the message composer. Corrupt drafts show an error plus delete option.

- [ ] **Step 4: Verify restore and delete**

### Task 9: In-App Browser And Local Browser Data

**Files:**
- Create: `dexo/Features/ForumDetail/Me/BrowserHistoryStore.swift`
- Create: `dexo/Features/ForumDetail/Me/InAppBrowserViewController.swift`
- Create: `dexofluxTests/AccountScopedStoreTests.swift`
- Modify: `dexo/Features/ForumDetail/Me/MeViewController.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] **Step 1: Test account scope, deduplication, and bounds**

Records are keyed by normalized base URL and username. Repeat visits move to the front. History is capped at 200; bookmarks are unique by URL.

- [ ] **Step 2: Implement atomic Codable storage**

Persist JSON under Application Support. Corrupt files decode as empty and are replaced on the next write.

- [ ] **Step 3: Implement browser home and WebView**

Provide address input, Linux.do shortcut, bookmarks, visit history, progress, back/forward/reload/share, delete/clear, cookie compatibility, `https://` normalization, and unsupported-scheme rejection.

- [ ] **Step 4: Add Me navigation and build**

### Task 10: Profile Statistics Editor

**Files:**
- Create: `dexo/Features/ForumDetail/Me/ProfileStatsEditorViewController.swift`
- Modify: `dexo/Features/ForumDetail/Me/MeViewController.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] **Step 1: Migrate selection-only preferences**

```swift
enum MeStatsLayout: String, Codable { case grid, horizontal }
struct MeStatsConfiguration: Codable { var orderedMetrics: [MeStatType]; var layout: MeStatsLayout }
```

Preserve existing `me.stats.selected` order and default layout to grid.

- [ ] **Step 2: Implement edit UI**

Use drag handles, visibility checkmarks, minimum-two validation, reset, and layout picker.

- [ ] **Step 3: Apply changes live**

Only native Discourse/profile metrics appear; Connect data does not.

- [ ] **Step 4: Verify migration and both layouts**

### Task 11: Topic Export And Export History

**Files:**
- Create: `dexo/Features/ForumDetail/Export/TopicExportService.swift`
- Create: `dexo/Features/ForumDetail/Export/ExportHistoryStore.swift`
- Create: `dexo/Features/ForumDetail/Export/ExportHistoryViewController.swift`
- Modify: `dexo/Features/ForumDetail/TopicDetail/TopicDetailViewController.swift`
- Modify: `dexo/Features/ForumDetail/Me/MeViewController.swift`
- Modify: `dexofluxTests/AccountScopedStoreTests.swift`
- Modify: `dexo/Localizable.xcstrings`

- [ ] **Step 1: Test record persistence and output escaping**

Cover account isolation, missing-file state, delete/clear, Markdown text, and HTML metadata escaping.

- [ ] **Step 2: Implement Markdown and HTML generation**

Export the first post or all currently loaded posts. Markdown derives normalized readable text from cooked content. HTML preserves cooked HTML in a complete themed document. Save sanitized files below Application Support/Exports.

- [ ] **Step 3: Add topic export action**

Expose format/range choices, share the result, and record success/failure with topic id, title, format, path, post count, and timestamp.

- [ ] **Step 4: Implement export history**

List newest first, filter, share existing files, show missing files, delete one, and clear all.

- [ ] **Step 5: Verify producer/consumer flow**

Export, reshare from history, remove the file, and verify the missing state remains safe and deletable.

### Task 12: Integration And Verification

**Files:**
- Modify: `dexo/Localizable.xcstrings`
- Modify: `.trellis/tasks/07-02-default-linuxdo-forum/implement.md`
- Modify: `.trellis/tasks/07-02-default-linuxdo-forum/prd.md`

- [ ] **Step 1: Audit fake actions**

```bash
rg -n "unavailableActionTapped|action_unavailable|comingSoon|敬请期待" dexo/Features/ForumDetail/Me dexo/Features/ForumDetail/Export
```

Expected: no visible A+B action is wired to a fake alert.

- [ ] **Step 2: Regenerate and run tests**

```bash
mise exec -- tuist generate
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -workspace dexoflux.xcworkspace -scheme dexofluxTests -sdk iphonesimulator -configuration Debug test CODE_SIGNING_ALLOWED=NO
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Build the app**

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -workspace dexoflux.xcworkspace -scheme dexoflux -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`; no new warnings originate from Phase 7 files.

- [ ] **Step 4: Manual smoke matrix**

Verify logged-out gating, own/other user cards, relationship mutations, private message, all profile tabs, pagination retry, social lists, My Topics, Discourse history, drafts, browser, statistics migration/layout, topic export, missing export files, and theme variants.

- [ ] **Step 5: Update Trellis acceptance state**

Mark only verified Phase 7 items complete. A server-denied action is hidden by capability rather than replaced with a fake alert.
