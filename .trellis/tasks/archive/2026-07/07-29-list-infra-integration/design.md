# 列表基建收口 — 设计

## 接入模式

```
Page VC
  ├─ owns UITableView + business VM
  ├─ ListRefreshController (thin adapter over DexoListRefreshPolicy)
  └─ ListStatePresenter (binds VM state → ListStateView)
```

Home 特殊：`ListRefreshController` 的 scroll-to-top / inset 回调可 no-op，由 Home 自己处理。

## 缓存

推荐：

- 对外 `TopicListCacheFacade`（名可变）
- 内里先委托现有更成熟的 `BackgroundTopicListCache` 或增强 `TopicListCache`
- 另一套变为 private/deprecated，迁移完删除

## 依赖

- **前置**：A Home 行为契约完成。
- **并行**：C 不阻塞 D，但错误态文案可共用。
