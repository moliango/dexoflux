# CF/会话/图片 — 实施

## Steps

1. 阅读并笔记：`CloudflareImageGate`、`WebSessionRefreshService`、API challenge 检测。
2. 抽出/加固纯策略（cooldown、grace、isMainDomain）。
3. 修通知风暴与恢复 debounce（若复现）。
4. 对齐 Avatar 与 ExternalImageFetcher 的 gate 行为。
5. 单测策略；手动：登出登入、挑战页走通、多图帖。
6. 文档化失败时用户可见文案是否一致。

## Done in code
- CloudflareImageGate unit tests (pause main host only)
