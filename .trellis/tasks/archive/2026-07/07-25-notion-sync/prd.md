# Notion 话题同步

## Goal

把话题同步到用户自己的 Notion Database，对齐 FluxDO Notion 集成的可用闭环：配置 Token/Database、测试连接、同步主帖或已加载帖、重复检测。

## FluxDO Reference

- `lib/services/notion/notion_config.dart`
- `lib/services/notion/notion_client.dart`
- `lib/services/notion/notion_sync_service.dart`
- `lib/services/notion/markdown_to_notion_blocks.dart`
- `lib/pages/notion_settings_page.dart`
- 入口：导出/分享 sheet 的 Notion 目标

## Requirements

1. **配置**
   - Integration Token 存 Keychain
   - Database ID、同步范围、收藏自动同步 等非敏感项本地持久化
   - 按论坛账号隔离（baseURL + username）
   - 设置页：填写 Token/DB ID、测试连接、清除配置
2. **同步**
   - 从话题详情触发「同步到 Notion」
   - 范围：仅主帖 / 已加载全部帖
   - Markdown → Notion blocks（段落/标题/列表/代码/引用/图片 URL）
   - create page（前 100 blocks）+ append 剩余分批
   - 按 Topic ID 查重；已存在可选跳过或覆盖（archive 旧页再建）
3. **状态**
   - 未配置时引导去设置
   - 进度/成功（可打开页面 URL）/失败提示

## Acceptance Criteria

- [x] 可配置 Token + Database ID 并测试连接
- [x] 话题可同步到 Notion 并返回 page 链接
- [x] 重复同步可跳过或覆盖
- [x] Token 不进明文导出备份的普通配置文件（Keychain）
- [x] UIKit、iOS 15、本地化

## Out of Scope

- 单帖级 page 批量同步每一层（可二期）
- 完整 cooked HTML 结构（poll/onebox）无损
- Notion OAuth 应用流（仍用 integration token）
