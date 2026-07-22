# FluxDo iOS 后台刷新研究

## 参考实现

- 仓库：`/Users/naine/Documents/AndroidWorkspace/fluxdo`
- `ios/Runner/AppDelegate.swift` 在启动返回前注册 `com.fluxdo.notificationPoll`。
- `ios/Runner/Info.plist` 声明 `BGTaskSchedulerPermittedIdentifiers`，并启用 `fetch`、`processing`、`remote-notification`。
- `lib/services/background/background_notification_service.dart` 使用 Workmanager 注册最早 15 分钟的周期任务。
- `lib/services/background/ios_background_fetch.dart` 在独立 Isolate 中读取单个 `userId` 和 MessageBus 游标，执行一次短轮询并投递本地通知。

## 可复用原则

1. 注册必须发生在 App 启动返回前。
2. 后台任务只做一次有明确超时的短网络同步。
3. 进入后台时提交任务，系统唤醒后继续安排下一次。
4. 首次游标只建立基线，不能轰炸历史通知。

## 不直接照搬的部分

- FluxDo 后台状态只保存一个用户，DexoFlux 需要覆盖数据库中的全部已登录论坛。
- DexoFlux 已有 `/session/current.json` 和 `/notifications.json` 未读语义及通知点击路由，继续复用这套契约，暂不新增 MessageBus 子域配置。
- DexoFlux 只使用 `BGAppRefreshTask`，因此仅声明 `fetch`。没有 APNs 时不声明 `remote-notification`，没有长维护任务时不声明 `processing`。
- 后台任务不能触发通知权限弹窗或 Cloudflare WebView。

## iOS 平台限制

- `earliestBeginDate` 只表示最早开始时间，不保证 15 分钟触发。
- 用户强退 App、关闭“后台 App 刷新”、低电量或系统预算不足时，任务可能长期不运行。
- 后台刷新属于尽力拉取；实时且可保证的挂起/杀进程通知仍需要 APNs 服务端。
