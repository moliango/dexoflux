# Home 列表手感 — 设计

## 策略

**先行为契约，后统一组件。**

本任务不强行让 Home 迁到通用 Policy（那是 D）。先把 Home 现有私有状态机收成清晰状态：

```
idle ──pull──► refreshing ──ok/fail──► idle
idle ──near bottom──► loadingMore ──ok/fail/nomore──► idle
refreshing 时忽略 pull 与 loadMore
loadingMore 时忽略 loadMore；pull 可取消或排队（推荐：忽略 loadMore，允许 pull 取消 more）
```

## 关键所有权

| 区域 | 主人 |
|------|------|
| 动态 Header / 顶 inset | Home 现有 geometry lock |
| refresh control 生命周期 | Home `pullToRefresh` 唯一出口 |
| load-more 触发 | scroll 代理 + viewModel 标志 |
| tab bar 显隐 | 仅用户拖动 + 明确的 loading freeze |

## 设计取舍

- **不**在本任务引入第二套 refresh UI。
- 缓存继续走现有 `BackgroundTopicListCache`，D 再决定是否与 `TopicListCache` 合并。
- 对 `HomeViewModel` 增加可测试的门闩（actor/标志），UI 只负责触发。

## 回滚

仅触及 Home VC/VM 与相关测试；不改全局 Observable 基类。
