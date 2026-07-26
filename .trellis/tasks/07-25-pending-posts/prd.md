# 待审内容列表

## Goal

提供“我的待审内容”列表，对齐 Discourse `/posts/{username}/pending.json` 与 FluxDO `pending_posts_page`。

## FluxDO Reference

- `lib/pages/pending_posts_page.dart`
- `lib/services/discourse/_reviewables.dart` → `GET /posts/$username/pending.json` → `pending_posts`

## Requirements

- Me 或合适入口进入“待审内容”
- 列表展示：标题/摘要、目标话题、时间、状态
- 下拉刷新；空/加载/错误态
- 点击可跳话题（若已有 topic_id）或展示原文
- 登录态校验；未登录引导登录
- 发帖返回 enqueued 时，可深链/提示去待审列表（若现有 enqueued 流程可接）

## Acceptance Criteria

- [ ] 登录用户可拉取并展示 pending posts
- [ ] 空列表有明确空态
- [ ] 失败可重试
- [ ] 点击跳转或查看可用
- [ ] 本地化 + iOS 15

## Out of Scope

- 版主审核后台（reviewable 队列全量）
- 替用户删除服务端 pending（除非 FluxDO 有且 API 明确，首发可只读）
