# 列表基建收口 — 实施

## Steps

1. 盘点所有列表 VC 的 refresh/loadMore/空错态实现表。
2. 定 Home 适配器接口（inset/scroll 所有权）。
3. Me 已用 Policy：对齐 API，补测试。
4. Home 接入适配器；Notifications/Search 能接则接。
5. 缓存门面 + 迁移调用点。
6. ListStateView 接到 2+ 个主列表首屏态。
7. 删死代码；全量 build；主路径手动。

## Done in code
- TopicListCacheFacade unifies Home + background disk cache entry
