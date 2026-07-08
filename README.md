<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="DexoFlux App Icon" />
</p>

<h1 align="center">DexoFlux</h1>

<p align="center">A native iOS Linux.do forum client, built with UIKit + Swift.</p>

<p align="center">
  English | <a href="README.zh-CN.md">中文</a>
</p>

## Screenshots

| Home | Topic Detail | Me |
|:---:|:---:|:---:|
| ![Home](assets/home.png) | ![Topic Detail](assets/detail.png) | ![Me](assets/me.png) |

## Features

- [x] **Linux.do Browsing** — Browse latest topics, top topics, categories, tags, and search results in a native UIKit experience.
- [x] **Topic Detail** — Render cooked HTML with native text, images, quotes, code blocks, polls, spoilers, oneboxes, tables, videos, and timeline navigation.
- [x] **Replies & Reactions** — Reply to topics or posts, like posts, and use Linux.do emoji / boost interactions.
- [x] **Image Viewer** — Preview topic and comment images with multi-image swipe, image count, share, save, and close controls.
- [x] **Account & Me** — Profile overview, avatar / username cache, bookmarks, browsing history, notifications, and private messages.
- [x] **Secure Auth** — Web login, cookie reuse for native requests, and global Cloudflare challenge handling.
- [x] **Appearance Settings** — Default, eye-care, Xiaohongshu, and Telegram theme colors, plus app icon, custom fonts, global font size, content font size, and tab bar customization.
- [x] **Data Management** — Cache visibility and cleanup for browsing data, images, cookies, and app storage.

## Tech Stack

| Component | Detail |
|-----------|--------|
| Language | Swift 5 |
| UI Framework | UIKit |
| Minimum Target | iOS 15.0 |
| Architecture | MVVM-style view models + `DexoObservableObject` / observable view controllers |
| Build Tool | [Tuist](https://tuist.dev) |
| Networking | [Alamofire](https://github.com/Alamofire/Alamofire), custom router, cookie-backed requests, and DoH URLProtocol |
| Web Session | `WKWebView` for login, Cloudflare verification, and session refresh |
| Database | SQLite via [GRDB](https://github.com/groue/GRDB.swift) |
| HTML Rendering | Local `CookedHTML` package backed by [SwiftSoup](https://github.com/scinfu/SwiftSoup) |
| Image Loading | [SDWebImage](https://github.com/SDWebImage/SDWebImage) + [SDWebImageSVGCoder](https://github.com/SDWebImage/SDWebImageSVGCoder) |
| Image Viewer | [Lightbox](https://github.com/hyperoslo/Lightbox) plus custom multi-image preview UI |
| Persistence | Keychain, cookies, local settings, and GRDB-backed models |

## Getting Started

### Prerequisites

- Xcode 16+
- [mise](https://mise.jdx.dev) for tool version management

### Build

```bash
# Install tools, fetch dependencies, and generate the Xcode project
make setup

# Re-generate the project only
make generate

# Clean generated artifacts
make clean
```

Open the generated `dexoflux.xcodeproj`, select your development team, then build and run.

## Project Structure

```text
dexo/
├── AppDelegate.swift
├── Core/
│   ├── Auth/                 # Web login, cookie store, Keychain, session refresh
│   ├── ImageLoading/         # Avatar and image loading helpers
│   ├── Observable/           # Observable base controllers and state binding
│   └── Settings/             # App settings, theme, language, fonts, tab bar preferences
├── Database/
│   └── Models/               # GRDB database manager and persisted models
├── Features/
│   ├── ForumDetail/
│   │   ├── Home/             # Topic lists and topic cards
│   │   ├── Categories/       # Category browsing
│   │   ├── Tags/             # Tag browsing
│   │   ├── TopicDetail/      # Native topic detail renderer, replies, image preview, polls
│   │   ├── Me/               # Profile, bookmarks, history, and account dashboard
│   │   ├── Notifications/    # Forum notifications
│   │   ├── Messages/         # Private messages
│   │   └── Search/           # Search UI and results
│   ├── Main/                 # Main tab container and entry routing
│   └── Settings/             # Appearance, reading, data, network, and tab bar settings
├── Networking/
│   ├── DoH/                  # DNS-over-HTTPS URLProtocol support
│   ├── Models/               # API response models
│   ├── DiscourseAPI.swift    # Linux.do / Discourse API client
│   └── DiscourseRouter.swift # Route definitions
├── Assets.xcassets/          # Runtime app assets
└── Localizable.xcstrings     # Simplified Chinese, Traditional Chinese, and English strings

Packages/
└── CookedHTML/               # Local HTML parser / native rendering model package

assets/                       # README screenshots and repository images
```

## Acknowledgements

DexoFlux is a second-stage project built on the native UIKit foundation of Dexo, while also taking visual and interaction inspiration from FluxDo. Dexo and FluxDo are both excellent apps: Dexo provides a solid native iOS architecture, and FluxDo shows a smoother, more polished direction for forum reading. DexoFlux tries to bring those strengths together and reshape the experience into a Linux.do-focused native client.

## Project Links

- **[Linux.do](https://linux.do)** — The community DexoFlux is built for.
- **[Eilgnaw/dexo](https://github.com/Eilgnaw/dexo)** — Dexo.
- **[Lingyan000/fluxdo](https://github.com/Lingyan000/fluxdo)** — FluxDo.
