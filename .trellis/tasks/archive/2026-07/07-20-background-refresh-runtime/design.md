# 技术设计：系统后台任务生命周期

- 新建单例 `BackgroundNotificationRefreshService`，封装 `BGTaskScheduler`。
- 使用 `BGAppRefreshTaskRequest`，`earliestBeginDate = now + 15min`。
- 通过纯策略类型暴露标识符、调度日期和是否需要调度，便于 XCTest 验证。
- Handler 内部持有当前 Swift `Task`，expiration 取消它，统一 await 后调用一次 `setTaskCompleted`。
- AppDelegate 只做注册；SceneDelegate 只做调度，不直接执行同步逻辑。
