# 用户签名显示开关

## Goal

阅读设置中增加“显示用户签名”，控制帖子下方 user signature 是否渲染。

## FluxDO Reference

- appearance/reading：`reading_showSignatures`

## Requirements

- 设置开关，默认与 FluxDO/社区习惯一致（实现时确认 Dexo 当前是否已解析 signature；若未解析需补模型字段）
- 详情帖子列表根据开关显示/隐藏签名
- 切换后已加载页面刷新或即时生效

## Acceptance Criteria

- [ ] 开关存在且持久化
- [ ] 开：有签名用户展示签名
- [ ] 关：不展示签名且不留大空白

## Out of Scope

- 编辑自己的签名（可用站内浏览器）
