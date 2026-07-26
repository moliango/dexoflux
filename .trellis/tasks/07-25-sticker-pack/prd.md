# 表情包市场与插入

## Goal

对齐 FluxDO 表情包：双 Tab、市场订阅、最近使用、Markdown 插入、可配置市场 base URL。

## Requirements

- 回复/发帖：`表情` / `表情包` 双 Tab
- 空状态 + 从市场添加
- 市场浏览、订阅/取消、本地持久化
- 最近使用
- 插入 `![name|WxH,30%](url)`
- 默认 `https://s.pwsh.us.kg`，可配置并恢复默认，改 URL 清缓存

## Acceptance Criteria

- [x] 未订阅空状态与市场添加
- [x] 订阅后可选中插入
- [x] 发送后正文图片展示正常
- [x] base URL 可改可恢复

## Out of Scope

- 自制上传表情包
- 自建市场后端
