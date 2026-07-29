# 07-29 全局列表刷新与 UX 一致性优化

**PRD 编号**：07-29
**状态**：草稿
**优先级**：高
**创建时间**：2026-07-29

## 1. 背景

当前 dexoflux 的多个列表页面（Home、Me 话题列表、Categories、ForumDetail 等）都使用了 pull-to-refresh + loadMore 机制，但实现方式分散：
- 部分页面已加 `contentInsetAdjustmentBehavior = .never`
- 刷新后置顶逻辑不统一（部分自动滚动到顶部，部分依赖用户手势）
- 错误/空态处理方式各异
- ObservableViewController 依赖通知中心驱动更新，存在一定延迟

用户反馈中出现“拉取第二页时列表抖动”问题，主要发生在列表滚动到底部后触发刷新时。

## 2. 目标

- 提升所有列表页面的刷新体验一致性（减少抖动、自动置顶）
- 统一内容安全区与 inset 管理
- 改善 Observable 状态管理，提升刷新/加载的响应速度
- 提供可复用的 ListState / 错误处理组件
- 增加列表内容缓存层，提高性能

## 3. 具体方案

### 3.1 全局刷新策略（ListRefreshPolicy）
- 提取 `DexoListRefreshPolicy` 到 `Core/` 目录
- 支持：
  - pull-to-refresh 触发刷新
  - 滚动到底部自动加载更多
  - 刷新后强制滚动到顶部（animated: false）
  - 禁用额外加载更多标志
- 所有列表页集成此策略

### 3.2 Observable 升级
- 将 `DexoObservableObject` 升级为 Actor + Published（或 Combine）
- `ObservableViewController` 移除通知中心，改用 `@MainActor` + `Task` 绑定
- 减少 notifyChanged 调用次数

### 3.3 内容安全区全局管理
- 在 `ObservableViewController` 基类中统一处理 `contentInsetAdjustmentBehavior`
- 提供可选的 `contentInset` 管理方法（类似 TopicDetail 的 bottomInset 方案）
- 强制所有列表页设置 `.never`

### 3.4 统一 ListStateView
- 创建 `Components/ListStateView.swift`（或 SwiftUI 版）
- 支持 loading、error、empty、retry 三态
- 可复用到所有列表页
- 内置动画和主题适配

### 3.5 缓存层优化
- 添加 `TopicListCache`（使用 NSCache + UserDefaults 持久化）
- 缓存 topics、users、categories
- 刷新时优先从缓存加载，网络成功后更新缓存

## 4. 实现范围

**影响文件**：
- `dexo/Core/Observable/`（升级）
- `dexo/Core/`（新增策略、缓存）
- 所有列表控制器（Home、Me、Categories 等）
- 新增 `ListStateView`

**不影响**：
- Discourse API 层
- 业务逻辑（仅 UI 层）

## 5. 验收标准

- 所有列表页拉取刷新后自动滚动到顶部
- 滚动到底部时不再触发不必要的加载更多
- 列表页不再出现抖动现象
- 内容安全区设置统一
- ListStateView 可复用且性能可接受
- 相关单元测试覆盖（至少 80%）

## 6. 风险与注意事项

- Observable 升级可能影响现有通知依赖
- 缓存层需处理并发刷新逻辑
- iOS 版本兼容（18+ 动态岛影响）
- 需在 Release 包中验证列表流畅度

**建议**：分两阶段：
1. 策略 + inset 统一（1 周）
2. Observable + 缓存 + ListState（2 周）

## 7. 相关链接

- 当前问题：Topic 列表刷新抖动
- 参考：HomePullToRefreshPolicy

**作者**：Codex
**审阅人**：待定
