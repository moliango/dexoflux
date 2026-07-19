# User Profile Preview Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the distorted user profile preview with the approved compact, theme-aware UIKit card.

**Architecture:** Keep the existing view controller, view model, data formatting, and presentation callbacks. Refactor only the view hierarchy, constraints, typography, button hit testing, and theme application in `UserProfilePreviewViewController.swift`.

**Tech Stack:** Swift, UIKit, Auto Layout, `UIButton.Configuration`, iOS 15, existing `AppSettings.ThemeStyle` tokens.

---

### Task 1: Compact Card Layout

**Files:**
- Modify: `dexo/Features/ForumDetail/Me/UserProfilePreviewViewController.swift`

- [x] Remove the decorative grabber and reduce card corner radius, shadow, content insets, and stack spacing.
- [x] Constrain the card to centered phone-width geometry with 22 pt minimum horizontal margins and a sensible maximum width for iPad.
- [x] Replace the 120 pt identity spacer with an avatar-sized spacer so the name block has enough width.
- [x] Reduce avatar, flair, typography, metadata, watermark, and control sizes to the approved visual scale.
- [x] Keep optional rows hidden without reserving vertical space.

### Task 2: Small Controls With Safe Hit Targets

**Files:**
- Modify: `dexo/Features/ForumDetail/Me/UserProfilePreviewViewController.swift`

- [x] Add a file-private `UIButton` subclass whose `point(inside:with:)` expands a 32-34 pt visible button to at least a 44 pt hit target.
- [x] Apply compact title fonts and SF Symbol configurations through `UIButton.Configuration`.
- [x] Keep existing button targets and unavailable-action behavior unchanged.

### Task 3: Theme Integration

**Files:**
- Modify: `dexo/Features/ForumDetail/Me/UserProfilePreviewViewController.swift`

- [x] Replace fixed white borders with accent-derived translucent borders.
- [x] Apply `topicCardBackgroundColor` and `accentColor` consistently to the card, avatar surround, level pill, watermark, buttons, and outlines.
- [x] Keep semantic `.label` and `.secondaryLabel` text colors for light/dark mode.

### Task 4: Verification

**Files:**
- Verify: `dexo/Features/ForumDetail/Me/UserProfilePreviewViewController.swift`

- [x] Run `xcrun swiftc -frontend -parse dexo/Features/ForumDetail/Me/UserProfilePreviewViewController.swift`; expect exit code 0.
- [x] Run `mise exec -- tuist generate` only if project generation is required by the workspace state.
- [x] Run `/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -workspace dexoflux.xcworkspace -scheme dexoflux -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,id=247E93F2-9DF6-4DF3-A7E2-EABF7A0FDD60' CODE_SIGNING_ALLOWED=NO build`; expect `BUILD SUCCEEDED`.
- [x] Run `git diff --check`; expect no whitespace errors.
- [x] Launch the app in the simulator and inspect the preview for compact proportions, readable theme contrast, and unclipped optional content.
