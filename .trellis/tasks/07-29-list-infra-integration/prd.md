# 列表基建收口与真接入

## Goal

把半成品列表基建收成一条可用链路：刷新策略、状态视图、缓存，并真正接到主列表；消灭双轨。

## Confirmed Facts

- `DexoListRefreshPolicy` 闭包 API 已存在，主要 Me 使用。
- `ListStateView` 组件存在，主列表未必统一使用。
- `TopicListCache` 与 `BackgroundTopicListCache` 两套。

## Requirements（细拆）

### D1 刷新策略

- Policy 负责任务去重、cancel、load-more 门闩；页面只提供 `onRefresh/onLoadMore`。
- Home 在 A 稳定后接入：**允许 Home 保留 header inset 所有权**，Policy 不管 Home 动态 header 几何。
- 至少接入：Home、Me 话题列表、Notifications（能分页的）、Search 结果列表（若结构允许）。

### D2 状态视图

- 首屏 loading / empty / error+retry 能复用 `ListStateView` 的页面清单明确。
- 不遮挡 refresh control 与 pagination footer。
- Reduce Motion / 动态字体可用。

### D3 缓存归一

- 选定唯一话题列表缓存门面（合并或 fortify 其一，deprecates 另一）。
- key：论坛 baseURL + 列表查询维度。
- 过期/损坏安全失效；写失败不阻塞 UI。

### D4 清理

- 删除或标记 deprecated 的死代码路径。
- 测试：Policy 去重、Cache 过期、State retry 回调。

## Acceptance Criteria

- [ ] Home 与 Me 刷新/分页都经统一门闩（Home 可适配器模式）。
- [ ] 目标页错误/空态可 retry 且不挡刷新。
- [ ] 仅保留一套对外缓存 API。
- [ ] `rg` 无生产代码双轨调用（或仅 wrapper）。
- [ ] 测试 + build 通过。

## Out Of Scope

- 非列表页（Settings 表单等）。
- 详情页时间线。
