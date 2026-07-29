# 剪贴板话题链接识别

## Goal

App 回到前台时识别剪贴板中的论坛话题链接，提示用户一键打开对应 Topic Detail。

## FluxDO Reference

- `lib/services/clipboard_topic_link_service.dart`
- 去重：进程内 seen + 持久化 last prompted hash
- 仅在设置开启时检查

## Requirements

- 设置项：允许/禁止剪贴板话题链接提示（默认开或跟随现有隐私偏好，需在实现时选定并写清）
- 识别当前论坛 `baseURL` 域名下的 `/t/...` 链接（至少支持绝对 http(s) 与 `//`）
- App 进入 active 时检查；同一链接不反复弹
- 弹窗：打开 / 忽略；打开后进入已登录会话的 Topic Detail
- 无权限/读剪贴板失败时静默失败，不崩

## Acceptance Criteria

- [ ] 复制本论坛话题链接后回前台出现提示
- [ ] 点打开进入正确 topic
- [ ] 同一链接短时间不重复弹
- [ ] 开关关闭后不再检查
- [ ] 单测覆盖链接解析与 hash 去重

## Out of Scope

- 识别任意第三方站点
- 自动打开不经确认
