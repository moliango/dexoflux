# AI 发帖预审与快捷提示

## Goal

在发帖/回复编辑器接入 AI 预审与快捷提示，复用 Dexo 已有 AI model/chat 底座，对齐 FluxDO ai_post_review 的核心闭环。

## FluxDO Reference

- `lib/widgets/ai/ai_post_review_button.dart`
- `ai_quick_prompts_*`
- `ai_post_review_service.dart`

## Requirements

- 回复/发帖工具区：预审按钮
- 将标题（若有）+ 正文 + 分类/标签上下文发给当前可用 AI 模型
- 展示建议：风险点/改进建议/可一键应用的改写（至少返回可读建议；一键应用若风险高可二期）
- 快捷提示条：常用 prompt 可配置或内置
- 无模型/未配置时引导去 AI 设置，不假装可用
- 不阻塞发送；预审失败可重试

## Acceptance Criteria

- [ ] 配置模型后可对当前草稿预审并展示结果
- [ ] 未配置模型有明确引导
- [ ] 不破坏现有发送/上传/表情包
- [ ] 与 `07-21-ai-*` 底座复用，不另起炉灶

## Dependencies

- 依赖现有 AI model service / chat 能力可用
- 不阻塞其他非 AI child

## Out of Scope

- 自动发帖前强制 AI 审查
- 云端专用审核服务
