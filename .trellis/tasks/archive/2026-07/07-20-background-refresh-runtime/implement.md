# 实施计划：系统后台任务生命周期

- [x] 新增后台刷新服务和纯调度策略。
- [x] 在 AppDelegate 注册任务。
- [x] 在 SceneDelegate 后台回调提交请求。
- [x] 更新 Info.plist 后台能力。
- [x] 增加调度日期、账号判定和完成语义测试。
- [x] 生成工程并完成测试构建。

## 验证结果

- `mise exec -- tuist generate` 通过。
- `xcodebuild build-for-testing` 通过。
- `ForumNotificationStateTests` 12 条测试通过。
