# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
make setup      # First-time setup: install mise tools, tuist install, tuist generate
make generate   # Regenerate Xcode project after changing Project.swift
make clean      # Clean Tuist build artifacts
```

The generated `Doer.xcworkspace` / `Doer.xcodeproj` are not committed. Always run `make generate` after modifying `Project.swift`, then open `Doer.xcworkspace`.

## Tests

```bash
cd Packages/CookedHTML && swift test
# App unit tests: open Doer.xcworkspace and run the DoerTests scheme
```

## Architecture

Doer is a native iOS Discourse forum client (UIKit, iOS 15+). No SwiftUI. Source lives under `Doer/`.

**MVVM with iOS 15-compatible observation**
- ViewModels inherit `DexoObservableObject` and call `notifyChanged()` after UI-relevant state mutations
- ViewControllers subclass `ObservableViewController`, which listens for `DexoObservableObject.didChangeNotification` and calls `updateUI()`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` applies project-wide

**Key layers:**
- `Doer/Networking/` — `DiscourseAPI` (one instance per forum, Alamofire-based) + `DiscourseRouter` (all API routes as enum)
- `Doer/Core/Auth/` — Discourse User API Key OAuth flow via `ASWebAuthenticationSession` + RSA key pair in Keychain
- `Doer/Database/` — GRDB `DatabasePool` with versioned migrations, stores `ForumInstance` records
- `Doer/Core/Settings/` — `AppSettings` (`DexoObservableObject` singleton) for user preferences
- `Packages/CookedHTML/` — Local Swift package for parsing Discourse-cooked HTML into `BlockNode`/`InlineNode` trees, with `NSAttributedString` rendering support

**Topic rendering** uses both a WKWebView snapshot path (JS messaging extracts interactive regions) and native UIKit block renderers under `Doer/Features/ForumDetail/TopicDetail/NativeContent/`.

## Localization

- Source language: English (`en`); also supports Simplified Chinese (`zh-Hans`)
- Use `String(localized: "key")` for all user-facing strings — never hardcode string literals
- Xcode automatically extracts keys into `Doer/Localizable.xcstrings` at build time (`SWIFT_EMIT_LOC_STRINGS = YES`)
- Add Chinese translations directly in `Localizable.xcstrings`

## Project Configuration

- Tuist version is pinned in `.mise.toml`
- Development Team ID goes in `.mise.local.toml` (not committed) as `TUIST_DEVELOPMENT_TEAM`
- Dependencies declared in `Tuist/Package.swift`: Alamofire, GRDB, SDWebImage, Lightbox
