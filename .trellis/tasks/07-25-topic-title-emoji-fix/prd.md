# 标题 Emoji 显示修复

## Goal

Topic 列表与详情标题中的 Discourse shortcode / 自定义 emoji 显示为表情图，而不是英文 shortcode 文本。

## Confirmed Facts

- `TopicCell` / `TopicDetailViewController` 仅在 `EmojiStore.lookupMap` 非空且 shortcode 命中 URL 时替换
- emoji 异步加载完成前渲染的标题会永久停留在 `:english_name:` 文本，直到 cell/页面重配
- FluxDO 对标准 emoji 使用确定性 URL：`/images/emoji/twitter/{name}.png`，不依赖完整 map 就绪

## Requirements

- 抽出共享标题 emoji 渲染工具，列表与详情共用
- shortcode 解析不依赖 lookupMap 非空；自定义优先，标准 emoji 可回退确定性路径
- emoji 缓存/映射就绪后，已展示标题自动刷新
- 无 shortcode 时行为与现网一致；未知 shortcode 合理降级
- 不回归现有 emoji picker / 正文渲染

## Acceptance Criteria

- [x] 含 `:shortcode:` 的 fancyTitle 在首页列表显示为 emoji 图
- [x] 详情页主标题与导航标题同样正确
- [x] emoji map 晚到时标题会刷新，不永久英文 shortcode
- [x] 无 shortcode 标题纯文本路径不变
- [x] 相关单测覆盖 shortcode 解析与 URL 解析

## Out of Scope

- 表情包市场
- 分享图整页重构（仅可复用标题渲染工具）
