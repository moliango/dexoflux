# 神文件拆分 — 实施

## Steps

1. 选第一刀（默认 Home Refresh/Scroll）。
2. 只移动代码 + 补 `// MARK:`，不改逻辑。
3. build；手动 Home 刷新分页。
4. 第二刀 TopicDetail 菜单/分享。
5. build；手动进帖/分享/编辑入口。
6. 写行数对比到 `research/loc.md`。
7. Settings 大拆列为 follow-up，不阻塞本任务关闭。

## Done in code
- HomePullToRefreshPolicy.swift extracted
- ForumInternalLinkParser.swift + Attachment downloader extracted from TopicDetail VC
