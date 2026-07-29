# 技术设计：后台通知刷新

## 架构边界

- `BackgroundNotificationRefreshService` 只负责 `BGTaskScheduler` 注册、调度、过期取消和任务完成。
- `BackgroundNotificationSyncEngine` 负责从数据库读取论坛、校验 Cookie、拉取通知并形成同步结果，不依赖任何 ViewController。
- `ForumNotificationDeliveryStore` 统一管理 `baseURL + username` 通知游标，前台协调器和后台引擎共同使用。
- `ForumLocalNotificationPresenter` 继续负责系统通知和 App 图标角标，但角标状态需要跨进程持久化。

## 生命周期

1. `AppDelegate.didFinishLaunchingWithOptions` 在返回前注册 `BGAppRefreshTask` handler。
2. `SceneDelegate.sceneDidEnterBackground` 调用 `scheduleIfNeeded()`。
3. 系统唤醒任务后，服务先提交下一次请求，再启动一个可取消的 Swift `Task`。
4. `expirationHandler` 只负责取消执行任务；执行路径最终统一调用一次 `setTaskCompleted(success:)`。
5. App 回前台后现有通知协调器立即刷新，从服务端恢复可见红点状态。

## 数据流

1. 从 GRDB 读取全部 `ForumInstance`。
2. 使用持久化 `_t` Cookie 判断论坛是否仍登录，不依赖 ViewController 或内存用户名缓存。
3. 每个论坛依次请求 `/session/current.json` 与 `/notifications.json`。
4. 使用官方未读数作为角标来源，通知列表作为本地提醒内容来源。
5. 通过共享游标筛选真正新增且未读的通知；游标不存在时只建立基线。
6. 汇总所有成功论坛的账号角标，再投递每个论坛最多最近 3 条本地通知。

## 并发与失败

- 后台任务只允许一个同步执行实例；重复触发复用正在执行的任务。
- 同一论坛的前台协调器与后台引擎通过共享 MainActor 游标服务执行“预留、投递、提交/释放”，避免跨 `await` 重复投递。
- 论坛按顺序执行，避免有限后台时间内同时启动大量请求和 Cloudflare 检测。
- Swift Task 取消必须在论坛之间检查，并传播为失败结果。
- 单论坛网络或认证失败被记录在结果中，后续论坛继续执行。
- 本地通知权限为 `.notDetermined` 且 App 不活跃时不发起系统授权弹窗。
- 后台 `DiscourseAPI` 禁用 WebSessionRefreshService/WKWebView 认证恢复；401、403、Cloudflare 和空响应只返回错误，不清理 Cookie、不展示 UI。

## 配置

- 标识符：`com.naine.dexoflux.notificationRefresh`。
- `BGTaskSchedulerPermittedIdentifiers` 只加入上述标识符。
- `UIBackgroundModes` 只加入 `fetch`；本任务不伪装成 `processing` 或 `remote-notification`。
- `earliestBeginDate` 为当前时间后 15 分钟，仅表达最早时间，不是周期保证。

## 风险与回滚

- 自签名或系统策略可能不执行后台任务；注册/提交失败必须静默记录，不影响前台使用。
- Cloudflare 阻断时后台不展示验证 UI，等待用户下次前台处理。
- 如后台同步造成问题，可移除 Scene 调度入口和 Info.plist 能力，前台通知协调器仍可独立工作。
