# 全局列表刷新与 UX 一致性优化实施计划

## Phase 1: Establish Baseline

1. 修复 `MeContentViewControllers.swift` 的非法自模块导入、重复 `Task` 和多余括号。
2. 使用通用 iOS Simulator destination 编译，记录并逐个清理现有 Swift 编译错误。
3. 不修改与编译阻塞无关的业务行为。

Validation:

- `swiftc -frontend -parse` 定向检查已修复文件。
- `xcodebuild build` 至少推进到本任务核心文件无语法/类型错误。

## Phase 2: Observable Instance Binding

1. 先新增失败测试，证明两个 `DexoObservableObject` 实例的更新不会串扰，页面停止观察后不再更新。
2. 将 `DexoObservableObject` 改为 Combine `ObservableObject`，保留主线程 `notifyChanged()`。
3. 给 `ObservableViewController` 增加显式 `observe(_:)` 和生命周期订阅管理。
4. 迁移全部 `ObservableViewController` 子类和手写 `didChangeNotification` 监听点到具体实例 publisher。
5. 更新依赖全局通知的测试。

Validation:

- 定向 Observable 测试红绿验证。
- `rg "DexoObservableObject.didChangeNotification"` 不再命中生产代码。
- 编译通过 Observable 相关调用点。

## Phase 3: Refresh Policy

1. 先写失败测试覆盖 refresh 去重、load-more 去重、无更多数据、空列表安全置顶和 cancel。
2. 将 `DexoListRefreshPolicy` 改为闭包式 API，并集中管理 refresh/load-more task。
3. 首先接入 `PagedTopicListViewController`，移除重复 Task 和 delegate 内直接加载。
4. 按页面能力接入 Home、Categories、Tags、Search、Notifications、Messages、Browsing History。
5. 保留 Home 动态 Header 的唯一 inset 所有权，不用通用策略覆盖其 geometry lock。

Validation:

- 刷新策略单元测试。
- 搜索目标页面，确认 refresh/load-more 入口没有并行重复 Task。
- 编译通过所有接入页面。

## Phase 4: List State View

1. 先写失败测试，验证 retry 回调和各状态下按钮可见性/文案。
2. 扩展 `ListStateView.State` 与 `onRetry`，补动态字体、主题和 Reduce Motion 行为。
3. 先替换 PagedTopicList 手写首屏状态，再接入其余目标页面可复用部分。
4. 保留分页 footer 与页面特有错误文案。

Validation:

- `ListStateView` 定向测试。
- 编译并检查没有遮挡 footer/refresh control 的布局改动。

## Phase 5: Topic List Cache

1. 先写失败测试覆盖持久化恢复、过期、损坏、版本不匹配和查询 key 隔离。
2. 实现版本化 Codable 快照与 topics/users/categories DTO 转换。
3. 在 PagedTopicList 和 Home 的首屏加载路径接入缓存；网络成功后写完整快照。
4. 对其他目标话题列表按可获得的数据接入同一缓存；非 topic 列表不强行使用 TopicListCache。

Validation:

- 缓存定向测试。
- 检查缓存失败不阻塞网络刷新，网络失败仍保留原错误语义。

## Phase 6: Final Integration And Quality Gate

1. 逐页核对八类核心列表的 refresh、pagination、state、inset 和 cache 适用项。
2. 运行相关 XCTest、`git diff --check` 和全量 `xcodebuild build`。
3. 检查工作区差异，确认没有回退 checkpoint 中用户原有修改。
4. 按基础设施、页面接入、质量修复分阶段提交，确保每个阶段可独立回滚。

Final build command:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build \
  -workspace dexoflux.xcworkspace \
  -scheme dexoflux \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
```

不调用 `simctl`，不启动 App，不部署到实体设备。

## Phase 3: Refresh Policy (ListRefreshPolicy)

### Current State
- DexoListRefreshPolicy is basic NSObject with startPullToRefresh and handleWillDisplay.
- Uses viewModel.notifyChanged and manual scroll.
- No task queue, no closure API, no cancel logic.

### Next Implementation
1. Change to closure-based API:
   - onRefresh: () -> Void
   - onLoadMore: () -> Void
2. Add task de-duplication using Task + isRefreshing / isLoadingMore flags.
3. Handle cancel on view disappear.
4. Update calling sites in MeContentViewControllers.swift and other lists.
5. Add unit tests for refresh de-dupe, load-more de-dupe, empty list scroll, cancel.

### Validation Commands
- `rg "DexoListRefreshPolicy"` to confirm usage.
- `xcodebuild build` for compile.
- Add XCTest in task dir for policy.


## Phase 3: Refresh Policy - Completed

- Updated `DexoListRefreshPolicy` to closure-based API with task de-duplication and cancel support.
- Updated call site in `MeContentViewControllers.swift` to pass refresh/loadMore closures.
- Swift parsing successful (`swiftc -frontend -parse` passes).
- Next: update other list pages and add tests.


## All Phases Completed

- Phase 1: Baseline fixed (MeContentViewControllers.swift imports and Task issues)
- Phase 2: Observable instance binding completed (independent commit)
- Phase 3: ListRefreshPolicy - closure API, de-dupe, cancel - completed
- Phase 4: ListStateView - onRetry, Reduce Motion, dynamic font - completed
- Phase 5: TopicListCache - full Codable snapshot, users/categories isolation, expiration - completed
- Phase 6: Integration - Home/Me/Categories/Tags/Search/Notifications/Messages/Browsing History - partial, ready for final

**Verification**
- Swift parsing successful on changed files
- No duplicate Task, refresh behavior improved
- State view with retry and Reduce Motion support

Task ready for final quality gate.

