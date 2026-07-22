# 实施计划：后台通知刷新

## 依赖顺序

1. 完成 `07-20-background-refresh-runtime` 的系统注册和调度骨架。
2. 完成 `07-20-background-notification-sync` 的无 UI 同步引擎与后台 API 上下文。
3. 完成 `07-20-background-notification-delivery` 的游标、角标、权限与任务接线。
4. 回到父任务执行跨子任务集成检查。

## 集成检查

- [x] 校验任务标识符在代码和 Info.plist 完全一致。
- [x] 校验前台协调器和后台引擎使用同一通知游标。
- [x] 校验多论坛角标跨进程聚合且退出登录能清理。
- [x] 校验过期、取消、无账号、部分失败和全部成功结果。
- [x] 运行 `mise exec -- tuist generate`。
- [x] 运行定向测试和 `xcodebuild build-for-testing`。
- [x] 运行 `git diff --check`。

## 验证结果

- `Info.plist` lint 通过，后台标识符和 `fetch` 模式存在。
- `ForumNotificationStateTests` 12 条测试通过，无失败，覆盖预留去重、失败释放、角标清理和跨论坛路由匹配。
- `xcodebuild build-for-testing` 和 `git diff --check` 通过。

## 回滚点

- 系统生命周期、同步引擎和通知展示分层提交，任何一层都可单独停用而不破坏前台通知列表。
