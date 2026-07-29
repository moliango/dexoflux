# 全局列表刷新与 UX 一致性优化设计

## Scope Decision

本任务接入 Home、Me/PagedTopicList、Categories、Tags、Search、Notifications、Messages、Browsing History 八类核心论坛列表。Settings、Plugins、Invite、Drafts 等独立列表不纳入统一刷新接入，但 Observable 基础设施迁移必须保持这些既有页面的更新能力。

## Design Principles

- 渐进迁移，不重写现有 ViewModel 的状态属性和业务请求 API。
- 刷新、分页、状态展示和缓存都由明确输入驱动，不再依赖全局广播猜测业务动作。
- UI 更新限定主线程，异步任务跟随页面生命周期取消。
- 缓存只加速首屏展示，不改变网络请求、错误语义和 Discourse endpoint 合约。
- 复用现有 UIKit 页面结构，避免为了统一而重写正常工作的列表渲染和导航逻辑。

## Observable Binding

### DexoObservableObject

`DexoObservableObject` 遵循 Combine `ObservableObject`，自行持有 `ObservableObjectPublisher`。现有 `notifyChanged()` 保留，负责在主线程发送 `objectWillChange`。

不继续发布 `DexoObservableObject.didChangeNotification`。所有旧的全局监听点迁移为对具体对象的 Combine 订阅，防止任意 ViewModel 更新导致无关控制器刷新。

### ObservableViewController

基类提供：

- `observe(_ object: DexoObservableObject)`：注册控制器依赖的具体对象，支持一个控制器观察多个对象。
- `startObserving()`：页面出现时为已注册对象建立订阅，并立即执行一次 `updateUI()`。
- `stopObserving()`：页面消失时取消订阅。
- 重复注册同一实例必须去重。

控制器在初始化完成或 `viewDidLoad()` 中显式注册自身 ViewModel；需要响应主题/设置变化的页面额外注册 `AppSettings.shared`。非控制器协调器使用私有 `AnyCancellable` 直接订阅具体对象。

## Refresh And Pagination Policy

`DexoListRefreshPolicy` 改为闭包驱动的 `@MainActor` 协调器：

- 输入：`UITableView`、可选 `UIRefreshControl`、refresh/load-more 异步闭包、`isLoading`、`isLoadingMore`、`canLoadMore` 状态闭包。
- `startPullToRefresh()`：状态允许时创建唯一 refresh task，调用业务 refresh；完成后结束刷新、恢复策略管理的 inset，并在有行时无动画置顶，空列表时直接设置安全 offset。
- `handleWillDisplay(at:)`：进入末尾阈值且允许分页时创建唯一 load-more task。
- refresh 和 load-more 各自双重去重：策略任务去重 + ViewModel 状态守卫。
- refresh 开始时取消尚未完成的 load-more，避免刷新第一页与追加旧页并发污染。
- `cancel()` 在页面退出时取消并清空任务。
- 置顶使用 `-adjustedContentInset.top`/`-contentInset.top` 的安全 offset，不调用空列表会崩溃的 `scrollToRow`。

Home 已有独立的动态 Header、geometry lock 和刷新规则，保留其现有几何逻辑；统一策略只接管可安全复用的触发去重和任务生命周期，不覆盖 Home 的动态 inset 计算。

## List State View

`ListStateView` 作为可复用覆盖视图，支持：

- `loading`
- `error(message:retryTitle:)`
- `empty(message:)`
- `retry(message:retryTitle:)`
- 外部注入 `onRetry` 回调

视图使用 `UIContentSizeCategory` 兼容字体、主题 accent token 和语义系统颜色。loading 动画在 Reduce Motion 下显示静态图标，不执行旋转动画。状态视图仅控制自身内容，不修改列表 footer、refresh control 或键盘 inset。

## Topic List Cache

`TopicListCache` 使用 `NSCache` + 独立 `UserDefaults` suite/key namespace：

- Key 由规范化论坛标识与查询维度组成，调用方负责传入稳定业务 key。
- 快照包含 `version`、`savedAt`、topics、users、categories。
- 读取顺序：有效内存快照优先，其次持久化快照；恢复成功后回填内存。
- 超时、版本不匹配、解码失败时删除对应持久化条目并返回 nil。
- 写入时先编码完整快照，再一次性写入 `Data`，避免 topics/users/categories 时间不一致。
- 提供依赖注入的 `UserDefaults`、时钟和 max age，保证过期、损坏、重启恢复可测试。

为避免给复杂 Discourse 网络模型强行补全 `Encodable`，缓存层使用内部 Codable DTO，并在网络模型与 DTO 之间显式转换。DTO 只覆盖列表渲染所需的现有字段，不改变网络解码模型。

## Screen Integration

- Home：注册 `HomeViewModel` 与 `AppSettings.shared` 的实例订阅；保留动态 Header/inset 和现有刷新入口，增加任务去重与生命周期取消；有效缓存先展示，网络成功后更新快照。
- Me/PagedTopicList：以统一刷新策略替换重复的 refresh/load-more Task；使用 `ListStateView` 替换手写首屏状态栈；接入 topic/users/categories 缓存。
- Categories、Tags、Search：注册具体 ViewModel；有分页的页面交给策略触发 load-more，无分页页面只接入 refresh 和状态视图。
- Notifications、Messages、Browsing History：注册具体 ViewModel；按页面现有能力接入 refresh、空态、错误和重试，不虚构不存在的分页。

## Compatibility And Migration

- 全仓搜索 `ObservableViewController` 子类，为每个控制器补齐明确观察对象，不能只迁移八个列表。
- 全仓搜索 `didChangeNotification`，将依赖 `AppSettings`、`AuthManager`、通知协调器等对象的监听改为具体 publisher。
- 更新测试中对全局通知的断言，改为订阅目标实例的 `objectWillChange`。
- 不回退 checkpoint 中 TopicDetail、图片加载和其他用户修改。

## Failure Handling

- refresh 失败：保留已有内容；无内容时显示原业务错误和 retry。
- load-more 失败：保留已有内容，在 footer 暴露重试，不把列表切成首屏错误。
- 缓存损坏/过期：静默失效并继续网络加载。
- 页面退出：取消策略任务和 Combine 订阅；ViewModel 自身仍以既有逻辑维护状态。

## Verification

- TDD 覆盖 Observable 实例隔离与生命周期、刷新/分页去重、空列表置顶、状态视图 retry、缓存恢复/过期/损坏/版本失效。
- 定向运行相关 XCTest；如测试环境受现有工程问题阻塞，记录具体错误并继续以完整 build 为最终门槛。
- 最终运行通用 iOS Simulator SDK 的 `xcodebuild build`，`CODE_SIGNING_ALLOWED=NO`，不启动模拟器。
