<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Doer App Icon" />
</p>

<h1 align="center">Doer</h1>

<p align="center">A native iOS Linux.do client, built with UIKit + Swift.</p>

<p align="center">
  English | <a href="README.zh-CN.md">中文</a>
</p>

<p align="center">
  <a href="https://github.com/moliango/doer"><img src="https://img.shields.io/badge/GitHub-moliango%2Fdoer-181717?logo=github" alt="GitHub" /></a>
  <img src="https://img.shields.io/badge/iOS-15.0%2B-blue" alt="iOS 15.0+" />
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5" />
  <img src="https://img.shields.io/badge/UIKit-native-lightgrey" alt="UIKit" />
</p>

## Screenshots

| Home | Topic Detail | Me |
|:---:|:---:|:---:|
| ![Home](assets/home.png) | ![Topic Detail](assets/detail.png) | ![Me](assets/me.png) |

## Features

- [x] **Linux.do browsing** — Latest, top, categories, tags, and search in a native UIKit UI.
- [x] **Topic detail** — Cooked HTML rendered as native text, images, quotes, code, polls, spoilers, oneboxes, tables, videos, and a timeline jumper.
- [x] **Replies & reactions** — Reply to topics or floors, like posts, and use Linux.do emoji / Boost.
- [x] **Image viewer** — Multi-image swipe, count, share, save, and close.
- [x] **Account & Me** — Profile, badges, bookmarks, drafts, browsing history, notifications, and private messages.
- [x] **Auth** — Web login, cookie reuse for native requests, and global Cloudflare challenge handling.
- [x] **Appearance** — Default, eye-care, Xiaohongshu, and Telegram themes, plus fonts, font size, and tab-bar layout.
- [x] **Plugins** — Mini programs, NewAPI check-in, toolbox, and a plugin dock.
- [x] **Share & widget** — Share a topic URL into Doer, plus a home-screen quick-launch widget.
- [x] **Data management** — Inspect and clear browsing data, image cache, cookies, and app storage.
- [x] **Updates** — In-app check against [GitHub Releases](https://github.com/moliango/doer/releases).

## Tech Stack

| Component | Detail |
|-----------|--------|
| Language | Swift 5 |
| UI Framework | UIKit (no SwiftUI in the main app) |
| Minimum Target | iOS 15.0 |
| Bundle ID | `com.naine.doer` |
| Architecture | MVVM-style view models + `DexoObservableObject` / observable view controllers |
| Build Tool | [Tuist](https://tuist.dev) via `mise` |
| Networking | [Alamofire](https://github.com/Alamofire/Alamofire), custom router, cookie-backed requests, DoH URLProtocol |
| Web Session | `WKWebView` for login, Cloudflare verification, and session refresh |
| Database | SQLite via [GRDB](https://github.com/groue/GRDB.swift) |
| HTML Rendering | Local `CookedHTML` package backed by [SwiftSoup](https://github.com/scinfu/SwiftSoup) |
| Image Loading | [SDWebImage](https://github.com/SDWebImage/SDWebImage) + [SDWebImageSVGCoder](https://github.com/SDWebImage/SDWebImageSVGCoder) |
| Image Viewer | [Lightbox](https://github.com/hyperoslo/Lightbox) plus custom multi-image preview |
| Persistence | Keychain, cookies, local settings, and GRDB-backed models |

## Getting Started

### Prerequisites

- Xcode 16+
- [mise](https://mise.jdx.dev) for tool versions

### Build

```bash
# Install tools, fetch dependencies, and generate the Xcode project
make setup

# Re-generate the project only
make generate

# Clean generated artifacts
make clean
```

Then open **`Doer.xcworkspace`** (not the leftover `.xcodeproj` alone), select the **Doer** scheme and your development team, and run.

The generated workspace is not committed. Run `make generate` again after changing `Project.swift`.

## Project Structure

```text
.
├── Project.swift                 # Tuist project: Doer / DoerTests / DoerShare / DoerWidget
├── Tuist/                        # External Swift packages
├── dexo/                         # App source
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── Info.plist
│   ├── Localizable.xcstrings     # en / zh-Hans / zh-Hant / zh-HK
│   ├── Assets.xcassets/          # App icon, launch art, runtime images
│   ├── Core/
│   │   ├── Auth/                 # Web login, cookie store, Keychain, session refresh
│   │   ├── ImageLoading/         # Avatar and image helpers
│   │   ├── Observable/           # Observable base controllers
│   │   ├── Plugins/              # Plugin registry and built-ins
│   │   ├── Settings/             # Theme, language, fonts, tab bar, DoH
│   │   └── Update/               # GitHub release checker
│   ├── Database/                 # GRDB pool and ForumInstance records
│   ├── Features/
│   │   ├── ForumDetail/          # Home, topic, Me, notifications, search, chat
│   │   ├── ForumList/            # Multi-forum list
│   │   ├── Settings/             # Appearance, reading, data, network, about
│   │   ├── Plugins/              # Mini programs, NewAPI check-in, toolbox
│   │   ├── Notion/               # Notion topic sync
│   │   └── AIModelService/       # In-app AI providers
│   └── Networking/               # DiscourseAPI + DiscourseRouter + DoH
├── Extensions/
│   ├── DexoShare/                # Share extension → doer://
│   └── DexoWidget/               # Home-screen widget
├── Packages/CookedHTML/          # Cooked HTML → native block/inline tree
├── dexofluxTests/                # Unit tests (DoerTests target)
├── ci_scripts/                   # Unsigned IPA build
└── assets/                       # README icon and screenshots
```

## Acknowledgements

Doer is a native iOS client for Linux.do. The UIKit architecture started from Dexo; several interaction details came from FluxDo. The product name and repository are independent.

## Project Links

- **[moliango/doer](https://github.com/moliango/doer)** — This project.
- **[Linux.do](https://linux.do)** — The community Doer is built for.
- **[Eilgnaw/dexo](https://github.com/Eilgnaw/dexo)** — Dexo.
- **[Lingyan000/fluxdo](https://github.com/Lingyan000/fluxdo)** — FluxDo.
