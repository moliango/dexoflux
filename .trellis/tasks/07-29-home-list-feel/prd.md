# Home 列表手感与刷新分页

## Goal

让 Home 话题列表的下拉刷新、接近底部加载、回顶、tab bar 显隐在各种网速与数据量下可预期、不抖、不连发请求。

## Confirmed Facts

- Home 使用私有 `UIRefreshControl` + `pullToRefresh` + `viewModel.loadMoreTopics()`。
- 存在 top refresh geometry lock、loadMore 期间 tab bar freeze 等复杂逻辑。
- `DexoListRefreshPolicy` 未接管 Home。
- Home 有 `BackgroundTopicListCache` 首屏缓存路径。

## Requirements（细拆）

### A1 下拉刷新

- 刷新过程中重复下拉不启动第二个 refresh 任务。
- 刷新结束必须 `endRefreshing`（成功/失败/空数据/取消都要）。
- 刷新成功后内容置顶策略明确：有数据则无动画或短动画回顶；空列表不 crash。
- 刷新期间 tab bar / header 不出现明显跳动（记录当前 lock 规则并固化）。

### A2 分页 load-more

- 距底部阈值内只触发一次 load-more。
- `isLoadingMore == true` 或 `canLoadMore == false` 时不发请求。
- 分页失败展示可重试入口（footer 或 toast 二选一，与现有 UI 一致优先）。
- 分页成功不重置滚动位置到顶部。

### A3 滚动与 tab bar

- 用户上滑/下滑时 tab bar 显隐规则文档化并保持一致。
- load-more 进行中禁止 tab bar 因 contentSize 变化误触发显隐。
- 快速抛滑不出现“卡死在隐藏/显示态”。

### A4 首屏与缓存

- 冷启动优先展示有效缓存（若有），再后台刷新。
- 缓存过期/损坏不阻塞网络刷新，不白屏死等。
- 刷新失败且无缓存时，错误态可重试。

### A5 可观测与测试

- 日志前缀：`home.refresh` / `home.loadmore` / `home.scroll`。
- 单测或可重复的 view model 级测试：refresh 去重、load-more 去重、无更多数据。

## Acceptance Criteria

- [ ] 弱网下连续下拉，网络层 refresh 不会并行叠加。
- [ ] load-more 在同一页生命周期内同一游标不重复请求。
- [ ] 刷新结束 refresh control 必收起。
- [ ] 分页中滚动 tab bar 不乱跳。
- [ ] 有缓存冷启动可见列表；无缓存显示 loading/错误而非空白卡死。
- [ ] 定向测试覆盖去重；`xcodebuild build` 通过。

## Out Of Scope

- 改 Home 信息架构、抽屉分类交互大改。
- 强制立刻替换为 `DexoListRefreshPolicy`（由 D 任务承接，本任务可预留钩子）。
