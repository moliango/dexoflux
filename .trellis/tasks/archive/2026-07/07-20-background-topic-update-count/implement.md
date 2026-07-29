# 后台 Topic 更新计数 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让现有 BGAppRefreshTask 更新 Home 页新的或已更新 Topic 数量。

**Architecture:** 使用轻量 UserDefaults Store 保存前台基线和待更新 ID；后台只拉最新第一页并执行纯对比；Home 继续复用现有 incoming topic 加载路径。

**Tech Stack:** Swift、UIKit、UserDefaults、Alamofire、XCTest、BGTaskScheduler。

---

### Task 1: Topic 基线和对比 Store

**Files:**
- Create: `dexo/Core/BackgroundTopicUpdateStore.swift`
- Create: `dexofluxTests/BackgroundTopicUpdateStoreTests.swift`

- [x] 编写无基线、新增、更新、去重、30 条上限和论坛隔离测试。
- [x] 运行 Store 定向测试并确认测试先失败。
- [x] 实现 fingerprint、持久化状态和纯对比逻辑。
- [x] 运行 Store 定向测试并确认通过。

### Task 2: 后台请求接线

**Files:**
- Modify: `dexo/Features/ForumDetail/Notifications/BackgroundNotificationSyncEngine.swift`
- Modify: `dexo/Features/ForumDetail/Notifications/BackgroundNotificationDeliveryPipeline.swift`
- Modify: `dexofluxTests/ForumNotificationStateTests.swift`

- [x] 在通知快照中加入可选最新 Topic 数据。
- [x] 通知请求成功后只追加一次 `fetchLatestTopics(page: 0)`。
- [x] Topic 失败保留通知快照，并按错误类型更新任务结果。
- [x] Pipeline 在取消检查后更新 Topic Store。
- [x] 增加结果语义测试。

### Task 3: Home 状态恢复和清零

**Files:**
- Modify: `dexo/Features/ForumDetail/Home/HomeViewModel.swift`
- Modify: `dexo/Features/ForumDetail/Home/HomeViewController.swift`
- Modify: `dexo/Core/Auth/AuthManager.swift`

- [x] Home 初始化和回前台时恢复待更新 ID。
- [x] 最新列表无基线时建立基线，普通加载保留待更新 ID。
- [x] incoming Topics 成功合并后记录基线并清零。
- [x] 登出或会话失效时清理对应论坛状态。

### Task 4: 验证

- [x] 运行 `mise exec -- tuist generate`。
- [x] 运行 Topic Store 与通知定向测试。
- [x] 运行 `xcodebuild build-for-testing`。
- [x] 运行 `plutil -lint dexo/Info.plist`。
- [x] 运行 `git diff --check`。

### 验证结果

- `BackgroundTopicUpdateStoreTests` 8 条测试通过。
- `ForumNotificationStateTests` 13 条测试通过。
- 完整 `xcodebuild build-for-testing` 通过。
- `plutil -lint dexo/Info.plist` 与 `git diff --check` 通过。
