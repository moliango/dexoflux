# 全局列表刷新与 UX 一致性优化

## Goal

统一论坛列表页的刷新、分页加载、状态展示、内容 inset 和缓存行为，解决刷新后置顶不一致、接近底部时重复触发加载以及分页过程中列表抖动的问题，并恢复工程可编译状态。

## Confirmed Facts

- `15645c7`、`02f2da0`、`0830142`、`f2605d6` 已把刷新策略、Observable、ListStateView 和 TopicListCache 的半成品提交到 `main`，但没有完成端到端接入。
- `DexoObservableObject` 当前仍通过全局 `NotificationCenter` 驱动所有 `ObservableViewController`，且文件曾混入重复的 `@Published` 段和多余括号。
- `DexoListRefreshPolicy` 当前只做置顶和通知，不负责真正调用 `refresh` / `loadMore`；协议和实现还声明了同名类型。
- `ListStateView` 当前没有对外暴露重试闭包，按钮点击不会触发重试。
- `TopicListCache` 当前只有内存 `NSCache`，只缓存 topics，未持久化，也未覆盖 users/categories。
- 当前工作区包含用户已有的未提交修改；本任务不得回退或覆盖与本 PRD 无关的修改。
- 当前已知编译阻塞包括 `MeContentViewControllers.swift` 中重复的 `Task` / `}`，以及该文件顶部的自模块导入问题；这些不属于前四个提交中的两个核心文件，需按最终范围决定是否修复。

## Requirements

### Refresh And Pagination

- 提供一个可复用的列表刷新策略，统一处理 pull-to-refresh、接近底部时只触发一次 load-more、刷新完成后无动画滚到顶部和刷新控件收起。
- 刷新策略通过明确的 refresh/load-more 回调工作，不再依赖“发送通知就等业务代码自行猜测”的隐式行为。
- load-more 必须受 `isLoadingMore`、`canLoadMore` 和任务去重保护，不能在同一页连续触发重复请求。
- 统一处理空列表、刷新中、分页中、首屏错误和分页错误的 UI 状态，不覆盖已有业务错误文案。

### Observable Binding

- Observable 状态更新必须按实例绑定到对应控制器，移除全局广播造成的无关 UI 刷新。
- 保留现有 view model 的手动状态属性和 `notifyChanged()` 调用兼容性，避免重写业务 API 层。
- UI 更新在主线程执行；控制器离开页面后释放订阅，避免生命周期泄漏。

### Insets And List State

- 论坛列表控制器统一设置 `contentInsetAdjustmentBehavior = .never`，并由策略集中处理刷新期间的顶部 inset。
- `ListStateView` 支持 loading、error、empty、retry 四态，重试动作由调用方注入；支持主题颜色、动态字体和 Reduce Motion。
- 状态视图不得遮挡列表已有 footer、下拉刷新控件或键盘避让逻辑。

### Cache

- `TopicListCache` 以论坛和列表查询维度隔离缓存，至少覆盖 topics、users、categories。
- 内存缓存优先，`UserDefaults` 仅保存可控大小的持久化快照和时间戳；缓存过期、解码失败或版本不匹配时安全失效。
- 刷新优先展示有效缓存，网络成功后原子更新列表数据和缓存；缓存不得改变网络失败时的错误语义。

### Integration

- 接入 Home、Me 话题列表、Categories、Tags、Search、Notifications、Messages 和 Browsing History 等已有论坛列表；对没有分页或没有 Observable view model 的页面只接入适用能力。
- 不修改 Discourse API 的 endpoint 合约，不改变登录、权限和业务数据语义。
- 修复本任务导致或暴露的编译错误，最终以无 Swift 编译错误为验收条件。

## Acceptance Criteria

- [ ] 工程可通过 `xcodebuild build` 编译，输出无 Swift 编译错误。
- [ ] 所有目标论坛列表的下拉刷新完成后自动回到顶部，刷新控件可靠结束。
- [ ] 列表接近底部时同一页最多有一个 load-more 任务，已无更多数据时不再请求。
- [ ] 首屏 loading、空态、首屏错误、可重试错误和分页错误均有可见且可操作的状态。
- [ ] 控制器只接收自身 view model 的状态变化，离开页面后不会继续刷新 UI。
- [ ] 主题切换、动态字体和 Reduce Motion 下状态视图与列表刷新行为可用。
- [ ] 有效缓存可在重启后恢复，过期/损坏缓存不会阻塞网络刷新。
- [ ] 相关单元测试覆盖刷新策略去重、缓存过期/恢复、Observable 订阅生命周期和状态视图回调；不能用“只验证 mock 被调用”替代行为验证。
- [ ] 除本任务明确列出的文件外，不回退或重写工作区已有修改。

## Out Of Scope

- Discourse API endpoint、请求参数和响应模型的业务变更。
- TopicDetail 的消息时间线、编辑、回复、分享和渲染逻辑重构。
- 将整个 UIKit 页面迁移到 SwiftUI。
- 删除或重写用户已有的其他未提交功能。

## Scope Decision

- 本任务限定为 Home、Me 话题列表、Categories、Tags、Search、Notifications、Messages 和 Browsing History 八类核心论坛列表。Settings、Plugin、Invite、Drafts、Pending Posts 等独立列表如需统一，拆为后续任务。
