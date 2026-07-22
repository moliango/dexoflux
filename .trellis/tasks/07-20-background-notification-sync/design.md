# 技术设计：后台通知同步与提醒

- 新建 `BackgroundNotificationSyncEngine`，依赖论坛读取和 API 创建边界，不依赖 ViewController 或系统通知中心。
- 为 `DiscourseAPI` 增加前台/后台执行上下文；后台上下文关闭 WebSessionRefreshService 恢复与成功响应后的 WebKit 刷新。
- 每个论坛获取 current user 与通知列表，形成 `baseURL/username/unread/notifications` 纯快照。
- 引擎只返回成功快照和失败论坛；游标提交、角标和系统通知由 delivery 子任务负责。
- 同一 `baseURL` 的前台和后台同步通过共享 actor 串行，避免同时读取旧游标后重复投递。
