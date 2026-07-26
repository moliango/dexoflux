# 话题卡片样式自定义

## Goal

提供话题列表卡片的显示字段与布局配置，并实时预览，对齐 FluxDO topic card style 设置。

## FluxDO Reference

- `lib/pages/topic_card_style_settings_page.dart`
- `lib/models/topic_card_style.dart`
- `lib/widgets/topic/painted_topic_card.dart` / `topic_card_layout.dart`

## Requirements

- 设置页：字段开关（如分类、标签、摘录、浏览/回复数、最后发帖时间、头像叠放等——以 FluxDO 实际字段为基线，按 Dexo 现有卡片能力裁剪）
- 布局选项：在 Dexo 现有 list / xiaohongshu 等模式上增加可配置项，而不是推翻主题系统
- 实时预览（假数据或样例 topic）
- 配置持久化，列表立即生效
- 与已读样式、分类抽屉不冲突

## Acceptance Criteria

- [ ] 用户可开关至少 4 类卡片元信息
- [ ] 修改后首页/列表卡片立即反映
- [ ] 预览与真实列表一致（允许主题色差异）
- [ ] 默认配置接近当前 Dexo 观感，不突然变丑

## Out of Scope

- 完全自绘引擎重写
- 每论坛独立皮肤市场
