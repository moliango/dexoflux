# Whisper 悄悄话标识

## Goal

对 staff-only whisper 帖展示清晰标识，避免与普通回复混淆。

## FluxDO Reference

- `lib/widgets/post/whisper_indicator.dart`
- post 字段 `whisper` / staff 可见逻辑

## Requirements

- 解析 post 的 whisper 标记
- 在 Post cell 展示“悄悄话”标识（样式克制）
- 无权限看不到的内容不瞎编；仅对已返回的 whisper 帖标记
- 与树形/扁平视图兼容

## Acceptance Criteria

- [ ] whisper 帖有可见标识
- [ ] 普通帖无标识
- [ ] 不影响布局稳定性

## Out of Scope

- 完整 whisper 发送权限工作流（若 API/权限复杂，可二期）
