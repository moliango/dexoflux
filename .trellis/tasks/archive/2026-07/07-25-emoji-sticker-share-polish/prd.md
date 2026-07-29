# 表情包、分享图美化与标题 Emoji 显示修复

## Goal

对齐 FluxDO 在回复体验与话题分享上的关键能力：
1. 回复/发帖编辑器支持表情包（sticker pack），可从市场添加并插入内容
2. 话题「生成分享图片」从粗糙截图式升级为 FluxDO 风格卡片预览（多主题 + 保存/分享）
3. 修复 Topic 标题中 emoji/shortcode 显示成英文文本的问题，保证列表与详情标题正确渲染表情

## Confirmed Facts（仓库可验证）

### Dexo 现状
- 已有 Discourse 自定义 emoji：
  - API：`/emojis.json`（`DiscourseRouter.emojis` / `DiscourseAPI`）
  - 缓存与查找：`EmojiStore`
  - 选择器：`EmojiPickerView`（分组、最近使用、搜索）
  - 接入：`ReplyComposerViewController`、`NewTopicComposerViewController`
- **没有** sticker pack / 表情包市场 / 订阅管理 / 插入 sticker 链路
- 标题 shortcode 渲染：
  - 列表：`TopicCell.configureTitleWithEmoji(topic.fancyTitle)`
  - 详情：`TopicDetailViewController.configureTitleLabel`
  - 匹配模式：`:[\w\-+]+:`
  - 若 `EmojiStore.lookupMap` 为空或 shortcode 无 URL，直接显示原始文本（看起来像英文 shortcode）
- 分享图：
  - 入口：详情页菜单「生成分享图片」→ `shareTopicImage()`
  - 实现：固定 1080x1350 画布，只画标题纯文本 + 正文 strip HTML 截断 + URL，无预览页、无主题、无作者信息、无品牌卡片

### FluxDO 参考（`/Users/naine/Documents/AndroidWorkspace/fluxdo`）
- 表情/表情包双 Tab：`emoji_sticker_panel.dart` + `sticker_picker.dart` + `sticker_market_sheet.dart`
- 市场服务：`StickerMarketService`
  - 默认 base：`https://s.pwsh.us.kg`
  - 索引/分组/详情 JSON，本地 24h 缓存
  - 订阅分组、最近使用
  - 选中后插入 Markdown 图片：`![name|WxH,30%](url)`
- 分享图：`share_image_preview.dart` + `share_image_widget.dart`
  - 预览页 + 多主题（经典米黄 / 纯白 / 深色 / 纯黑 / 蓝调 / 绿野等）
  - 卡片结构：品牌 Logo + 标题（含 emoji）+ 作者头像/名/时间 + 正文 + 链接
  - 保存到相册 / 系统分享
  - 记住上次主题索引

### 相关但不应硬塞的现有任务
- `07-11-fluxdo-extensions-topic-experience` 覆盖 LDC/CDK、浏览器、已读样式、详情操作菜单等，不包含表情包与分享图重构

## Requirements

### A. 表情包（Sticker Pack）
- **决策（已确认）**：首发完整对齐 FluxDO 核心能力，并包含可配置市场 base URL
- 回复与发帖编辑器在现有 emoji 能力旁提供「表情 / 表情包」双 Tab（或等价切换）
- 空状态提示「还没有表情包」，并提供「从市场添加」
- 支持从表情包市场浏览分组、添加/取消订阅、本地持久化订阅列表
- 已订阅分组可浏览贴纸网格；支持最近使用
- 选中贴纸后插入到编辑器内容（与 FluxDO 一致的 Markdown 图片语义：`![name|WxH,30%](url)`）
- 默认市场 base：`https://s.pwsh.us.kg`；首发提供可配置市场 base URL（含恢复默认），修改后清除相关缓存
- 图片加载失败、网络失败、空市场、未订阅等状态有明确反馈
- 本地化（中/英至少与项目现有 i18n 一致）

### B. 分享图美化
- **决策（已确认）**：主帖富文本卡片 + 可选指定楼层；不做纯文本摘要糊弄
- 「生成分享图片」进入预览页，而不是直接弹出系统分享
- 默认分享主帖（1 楼）；若从指定回复/楼层入口触发，可分享该楼层
- 预览卡片至少包含：品牌区、标题、作者信息、正文内容区（富文本/图文尽量保真）、可识别链接/来源
- 正文复用/贴近现有帖子渲染能力，允许对超长内容限高或合理截断，但不能退回 strip HTML 纯文本白板
- 提供多主题色板（对齐 FluxDO 可见主题：经典 / 纯白 / 深色 / 纯黑 / 蓝调 / 绿野）
- 支持「保存到相册」「分享」
- 记住用户上次选择的主题
- 标题中的 emoji 在分享图中也要正确渲染（不能退回 shortcode 英文）

### C. Topic 标题 Emoji 显示修复
- 列表卡片与详情标题在存在 Discourse shortcode / 自定义 emoji 时显示图像或正确 emoji，而不是裸英文 shortcode
- 在 emoji 缓存尚未就绪时，应在就绪后自动刷新标题渲染，而不是永久卡在文本
- shortcode 无对应资源时的降级策略明确且不破坏布局
- 覆盖：`TopicCell`、详情页主标题与导航栏标题（若展示同一 title）

## Acceptance Criteria

- [ ] 回复/发帖编辑器可切换到表情包面板，未订阅时展示空状态与「从市场添加」
- [ ] 可从市场添加至少一个表情包分组，返回后可浏览并插入贴纸到编辑器
- [ ] 支持修改表情包市场 base URL，并可恢复默认；修改后旧缓存不继续误用
- [ ] 插入内容发送后，在帖子正文中以图片/贴纸语义正确展示（与 Discourse Markdown 图片兼容）
- [ ] 最近使用贴纸可记录并再次选择
- [ ] 话题详情「生成分享图片」打开预览页，可切换主题并即时更新预览
- [ ] 默认分享主帖富文本内容；从指定楼层入口进入时可分享该楼
- [ ] 预览页可保存到相册，也可唤起系统分享
- [ ] 分享图包含标题、作者、正文内容区、品牌信息，视觉明显优于当前纯文本画布
- [ ] 含 shortcode/自定义 emoji 的 Topic 标题在列表与详情显示为表情图，而不是英文 shortcode 文本
- [ ] emoji 缓存异步就绪后，已展示的标题会刷新为正确表情
- [ ] 现有标准 emoji 选择、发送、搜索行为不回归
- [ ] UIKit-only，iOS 15 兼容，文案本地化，目标测试通过

## Out of Scope

- 自建表情包市场后端或改 FluxDO 市场协议
- AI 分享图 / AI 聊天分享卡
- 非 UIKit 框架迁移
- 把本需求并入 `07-11-fluxdo-extensions-topic-experience` 大杂烩任务
- 表情包上传/自制（仅消费市场）

## Decisions

- 表情包首发范围：完整对齐 FluxDO 核心（双 Tab、市场订阅、最近使用、Markdown 图片插入）+ 可配置市场 base URL。
- 分享图正文：主帖富文本卡片为默认；支持从指定楼层入口分享该楼；不做纯文本摘要方案。
- 任务结构：parent + 3 children，独立规划/实现/验收。
  - Child A：标题 emoji 显示修复（优先）
  - Child B：分享图预览与多主题
  - Child C：表情包市场/订阅/插入
- 用户已要求拆分后直接进入实现；规划文档补齐后从 Child A 启动。

## Open Questions

- 无阻塞问题。剩余细节在各 child 的 design/implement 中落地。

## Notes

- 复杂任务：完成 `prd.md` 后还需 `design.md` + `implement.md`，经用户确认再 `task.py start`
- 参考实现优先对照 FluxDO 源码，而不是凭空发明交互


## Task Map

| Child | Scope | Notes |
|---|---|---|
| `topic-title-emoji-fix` | 列表/详情标题 shortcode 与自定义 emoji 正确渲染 | 优先；分享图标题也可复用 |
| `share-image-polish` | 分享预览页、主题、保存/分享、主帖/指定楼层富文本卡片 | 依赖标题 emoji 渲染能力更佳 |
| `sticker-pack` | 表情/表情包双 Tab、市场、订阅、最近使用、Markdown 插入、可配置 base URL | 最大块，独立交付 |
