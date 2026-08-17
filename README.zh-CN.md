<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Doer App Icon" />
</p>

<h1 align="center">Doer</h1>

<p align="center">原生 iOS Linux.do 客户端 — UIKit + Swift,主 App 不使用 SwiftUI。</p>

<p align="center">
  <a href="README.md">English</a> | 中文
</p>

<p align="center">
  <a href="https://github.com/moliango/doer"><img src="https://img.shields.io/badge/GitHub-moliango%2Fdoer-181717?logo=github" alt="GitHub" /></a>
  <img src="https://img.shields.io/badge/iOS-15.0%2B-blue" alt="iOS 15.0+" />
  <img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift 5" />
  <img src="https://img.shields.io/badge/UIKit-native-lightgrey" alt="UIKit" />
</p>

## 截图

| 论坛首页 | 帖子详情 | 我的 |
|:---:|:---:|:---:|
| ![论坛首页](assets/home.png) | ![帖子详情](assets/detail.png) | ![我的](assets/me.png) |

| 登录页 | 默认主题 | 护眼主题 |
|:---:|:---:|:---:|
| ![登录页](assets/login.png) | ![默认主题](assets/default.png) | ![护眼主题](assets/huyan.png) |

| 小红书主题 | 微信主题 | Telegram 主题 |
|:---:|:---:|:---:|
| ![小红书主题](assets/redbook.png) | ![微信主题](assets/wechat.png) | ![Telegram 主题](assets/telegram.png) |

| 默认主题详情 | 微信主题详情 | Telegram 主题详情 |
|:---:|:---:|:---:|
| ![默认主题详情](assets/default%20detail.png) | ![微信主题详情](assets/wechat%20topic%20Detail.png) | ![Telegram 主题详情](assets/telegram%20Topic%20Detail.png) |
## 功能

- [x] **Linux.do 浏览** — 原生浏览最新话题、热门话题、板块、标签和搜索结果。
- [x] **帖子详情** — 原生渲染 cooked HTML,支持正文、图片、引用、代码块、投票、折叠、Onebox、表格、视频和时间线跳转。
- [x] **回复与互动** — 回复主题 / 楼层、点赞,以及 Linux.do 表情 / Boost。
- [x] **图片查看** — 多图预览,支持左右滑动、数量、分享、保存和关闭。
- [x] **我的页面** — 个人看板、勋章、书签、草稿、浏览历史、通知和私信。
- [x] **安全认证** — Web 登录、Cookie 复用原生请求、全局 Cloudflare 盾牌处理,以及第三方平台的静默会话恢复。
- [x] **外观设置** — 默认、护眼、小红书、Telegram 主题色,以及字体、字号和底栏布局。
- [x] **插件** — 小程序、NewAPI 签到(支持静默重新认证)、工具箱和插件坞。
- [x] **分享与小组件** — 把话题链接分享进 Doer,以及主屏幕快捷入口。
- [x] **数据管理** — 查看并清理浏览数据、图片缓存、Cookie 和应用存储。
- [x] **应用更新** — 对照 [GitHub Releases](https://github.com/moliango/doer/releases) 检查新版本。

## 技术栈

| 项目 | 说明 |
|------|------|
| 语言 | Swift 5 |
| UI 框架 | UIKit(主 App 不使用 SwiftUI) |
| 最低版本 | iOS 15.0 |
| Bundle ID | `com.naine.doer` |
| 架构 | MVVM 风格 ViewModel + `DoerObservableObject` / 可观察 ViewController |
| 构建工具 | [Tuist](https://tuist.dev),通过 `mise` 固定版本(见 `.mise.toml`) |
| 网络 | [Alamofire](https://github.com/Alamofire/Alamofire)、自定义 Router、Cookie 复用请求、DoH URLProtocol |
| Web 会话 | `WKWebView` 负责登录、Cloudflare 验证和会话刷新 |
| 数据库 | SQLite via [GRDB](https://github.com/groue/GRDB.swift) |
| HTML 渲染 | 本地 `CookedHTML` 包,底层使用 [SwiftSoup](https://github.com/scinfu/SwiftSoup) |
| 图片加载 | [SDWebImage](https://github.com/SDWebImage/SDWebImage) + [SDWebImageSVGCoder](https://github.com/SDWebImage/SDWebImageSVGCoder) |
| 图片查看 | [Lightbox](https://github.com/hyperoslo/Lightbox) + 自定义多图预览 |
| 持久化 | Keychain、Cookie、本地设置、GRDB 模型 |
| 本地化 | `Localizable.xcstrings` — en / zh-Hans / zh-Hant / zh-HK |

## 架构概览

Doer 采用 **瘦 ViewController / 胖 ViewModel** 模式,并使用兼容 iOS 15 的观察机制。工程全局设置 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,因此所有 UI 相关代码默认在主 Actor 上执行。

```text
ViewController(渲染状态)
      │  监听 DoerObservableObject.didChangeNotification
      ▼
ViewModel  (持有状态,调用 notifyChanged())
      │
      ▼
DiscourseAPI / DiscourseRouter  (每个论坛一个 Alamofire 实例)
```

关键分层:

- `Doer/Networking/` — `DiscourseAPI`(每个论坛一个实例,基于 Alamofire)+ `DiscourseRouter`(所有 API 路由以枚举表达)。
- `Doer/Core/Auth/` — 通过 `WKWebView` 的 Web 登录、原生请求的 Cookie 复用、Keychain 凭据和会话刷新。
- `Doer/Core/Plugins/` — 插件注册、运行时和内置插件(小程序、NewAPI 签到、工具箱)。
- `Doer/Database/` — GRDB `DatabasePool` 与版本化迁移,存储 `ForumInstance` 记录。
- `Doer/Core/Settings/` — `AppSettings`(`DoerObservableObject` 单例)承载用户偏好。
- `Packages/CookedHTML/` — 本地 Swift 包,把 Discourse cooked HTML 解析为 `BlockNode`/`InlineNode` 树,并提供 `NSAttributedString` 渲染支持。

**话题渲染**支持两条路径:WKWebView 快照路径(通过 JS 消息提取交互区域)和 `Doer/Features/ForumDetail/TopicDetail/NativeContent/` 下的原生 UIKit 块渲染器。

## 快速开始

### 前置要求

- Xcode 16+
- [mise](https://mise.jdx.dev) 用于工具版本管理(Tuist 版本固定在 `.mise.toml`)
- 在 `.mise.local.toml`(不入库)中以 `TUIST_DEVELOPMENT_TEAM` 配置开发团队 ID

### 构建

```bash
# 安装工具、拉取依赖、生成 Xcode 工程
make setup

# 只重新生成工程
make generate

# 通过 ci_scripts 构建未签名 IPA
make unsigned-ipa

# 清理生成产物
make clean
```

完成后打开 **`Doer.xcworkspace`**(不要只开单独的 `.xcodeproj`),Scheme 选 **Doer**,再选择开发团队即可编译运行。

> 生成的 workspace **不入库**。改过 `Project.swift` 后需要再跑一次 `make generate`。

### 测试

```bash
# CookedHTML 包测试
cd Packages/CookedHTML && swift test

# App 单元测试:打开 Doer.xcworkspace 运行 DoerTests scheme
```

## 项目结构

```text
.
├── Project.swift                 # Tuist 工程:Doer / DoerTests / DoerShare / DoerWidget
├── Tuist/                        # 外部 Swift 依赖
├── Doer/                         # App 源码
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── Info.plist
│   ├── Localizable.xcstrings     # en / zh-Hans / zh-Hant / zh-HK
│   ├── Assets.xcassets/          # 应用图标、启动图、运行时图片
│   ├── AppIcon.icon/             # Icon Composer 资源
│   ├── Components/               # 共用反馈 / 空状态组件
│   ├── Resources/Fonts/          # 内置图标字体
│   ├── Core/
│   │   ├── Auth/                 # Web 登录、Cookie、Keychain、会话刷新
│   │   ├── ImageLoading/         # 头像和图片加载
│   │   ├── Observable/           # 可观察基类控制器
│   │   ├── Plugins/              # 插件注册和内置插件
│   │   ├── Settings/             # 主题、语言、字体、底栏、DoH
│   │   └── Update/               # GitHub Release 检查更新
│   ├── Database/                 # GRDB 和 ForumInstance
│   ├── Features/
│   │   ├── ForumDetail/          # 首页、帖子、我的、通知、搜索、聊天
│   │   ├── ForumList/            # 多论坛列表
│   │   ├── Main/                 # 根底栏容器
│   │   ├── Settings/             # 外观、阅读、数据、网络、关于
│   │   ├── Plugins/              # 小程序、NewAPI 签到、工具箱
│   │   ├── Notion/               # Notion 话题同步
│   │   └── AIModelService/       # 应用内 AI 服务
│   └── Networking/               # DiscourseAPI + DiscourseRouter + DoH
├── Extensions/
│   ├── DoerShare/                # 分享扩展 → doer://
│   └── DoerWidget/               # 主屏幕小组件
├── Packages/CookedHTML/          # cooked HTML → 原生节点树
├── DoerTests/                    # App 单元测试
├── ci_scripts/                   # 未签名 IPA 构建
└── assets/                       # README 图标和截图
```

## 致谢

Doer 是面向 Linux.do 的原生 iOS 客户端。UIKit 架构源自 [Dexo](https://github.com/Eilgnaw/dexo),部分交互节奏参考 [FluxDo](https://github.com/Lingyan000/fluxdo)。产品名和仓库已经独立。

## 项目链接

- **[moliango/doer](https://github.com/moliango/doer)** — 本仓库。
- **[Linux.do](https://linux.do)** — Doer 面向的社区。
- **[Eilgnaw/dexo](https://github.com/Eilgnaw/dexo)** — Dexo。
- **[Lingyan000/fluxdo](https://github.com/Lingyan000/fluxdo)** — FluxDo。