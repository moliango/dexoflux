<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="Dexo App Icon" />
</p>

<h1 align="center">Dexo</h1>

<p align="center">一个原生 iOS Discourse 论坛客户端，使用 UIKit + Swift 构建。</p>

<p align="center">
  <a href="README.md">English</a> | 中文
</p>

## 截图

| 论坛首页  | 帖子详情 | 板块分类 |
|:---:|:---:|:---:|
| ![论坛首页](assets/home.png) | ![帖子详情](assets/detail.png) | ![板块分类](assets/cate.png) |


## 功能

- [x] **多论坛管理** — 添加、切换、删除多个 Discourse 实例
- [x] **帖子浏览** — 最新 / 热门话题列表，无限滚动加载
- [x] **分类 & 标签** — 按板块或标签浏览话题
- [x] **帖子详情** — HTML 内容渲染、图片查看、代码块展示、折叠内容
- [x] **回复** — 回复话题或针对特定楼层回复
- [x] **安全认证** — Web 会话登录，并将 Cookie 复用于原生请求
- [x] **外观设置** — 跟随系统 / 浅色 / 深色模式
- [ ] **通知 & 私信** — 查看论坛通知和私信
- [ ] **发贴** — 发布论坛帖子

## 技术栈

| 项目 | 说明 |
|------|------|
| 语言 | Swift 5 |
| UI 框架 | UIKit |
| 最低版本 | iOS 15.0 |
| 架构 | MVVM + `DexoObservableObject` |
| 构建工具 | [Tuist](https://tuist.dev) |
| 数据库 | SQLite ([GRDB](https://github.com/groue/GRDB.swift)) |
| 网络 | [Alamofire](https://github.com/Alamofire/Alamofire) |
| 图片加载 | [SDWebImage](https://github.com/SDWebImage/SDWebImage) |
| 图片查看 | [Lightbox](https://github.com/hyperoslo/Lightbox) |

## 快速开始

### 前置要求

- Xcode 16+
- [mise](https://mise.jdx.dev) (工具版本管理)

### 构建

```bash
# 安装工具、拉取依赖、生成 Xcode 工程（一步到位）
make setup

# 后续只需重新生成工程
make generate

# 清理
make clean
```

执行完成后打开生成的 `dexo.xcodeproj`，选择开发团队后即可编译运行。

## 项目结构

```
dexo/
├── Core/
│   ├── Auth/           # 认证流程、Keychain、RSA 加解密
│   ├── Networking/     # DoH URLProtocol
│   ├── Observable/     # ObservableViewController 基类
│   └── Settings/       # 应用偏好设置
├── Database/           # GRDB 数据库管理 & 数据模型
├── Features/
│   ├── ForumList/      # 论坛列表
│   ├── ForumDetail/
│   │   ├── Home/       # 最新 / 热门话题
│   │   ├── Categories/ # 板块分类
│   │   ├── Tags/       # 标签话题
│   │   ├── Messages/   # 私信
│   │   ├── Notifications/ # 通知
│   │   └── TopicDetail/   # 帖子详情 & 回复
│   └── Settings/       # 设置页
├── Networking/
│   ├── DiscourseAPI.swift    # API 客户端
│   ├── DiscourseRouter.swift # 路由定义
│   └── Models/               # API 响应模型
└── Assets.xcassets/
```

## 友链

- **[Linux.do](https://linux.do)** — 学 AI，上 L 站
