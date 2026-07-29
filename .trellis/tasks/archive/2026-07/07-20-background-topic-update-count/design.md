# 技术设计：后台 Topic 更新计数

## 状态模型

`BackgroundTopicUpdateStore` 按规范化 `baseURL` 保存：

- 前台基线：最多 30 个 `TopicFingerprint`。
- 待更新 ID：最多 30 个，顺序与服务器最新列表一致。

Fingerprint 只包含 `id`、`postsCount`、`replyCount`、`lastPostedAt` 和 `pinned`。

## 对比规则

1. 没有基线时保存当前最新第一页并返回空列表。
2. 以基线中第一个非置顶 Topic 为参考点。
3. 参考点之前、不在基线中的 Topic 视为新增。
4. 基线中已存在但帖子数、回复数或最后回复时间变化的 Topic 视为更新。
5. 合并去重后按服务器顺序保留最多 30 个 ID。
6. 后台刷新和普通 Home 加载都不移动已有基线；用户点击提示并成功合并后才重建基线。

## 数据流

1. `HomeViewModel.loadTopics()` 成功加载 `.latest` 且无分类时，仅在没有基线的情况下建立基线，并恢复已有待更新 ID。
2. `BackgroundNotificationSyncEngine` 完成通知请求后请求 `fetchLatestTopics(page: 0)`。
3. `BackgroundNotificationDeliveryPipeline` 将成功返回的 Topics 交给 Store 对比。
4. Home 初始化、`viewWillAppear` 和 `didBecomeActive` 从 Store 恢复待更新 ID。
5. `loadIncomingTopics()` 成功合并后记录新基线并清空待更新 ID。

## 失败语义

- Topic 请求失败不丢弃已经成功的通知快照。
- 瞬时 Topic 请求失败使 BGTask 返回失败，便于系统后续重试。
- Cloudflare 或认证错误不弹 UI，并保留旧 Topic 计数。
- 取消时不写入新的 Topic 对比结果。
