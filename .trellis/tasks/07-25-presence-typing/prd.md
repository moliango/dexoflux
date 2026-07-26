# Presence 正在输入

## Goal

在回复输入时按站点/用户设置向 Discourse 报告 presence，并在可行时展示他人正在输入（若 API 与预加载设置支持）。

## FluxDO Reference

- `lib/services/presence_service.dart`
- 受 `presence_enabled` 与用户 `hide_presence` 控制
- 心跳 ~30s，输入防抖

## Requirements

- 从 preloaded/site settings 读取是否启用
- 用户隐藏 presence 时不发送
- 回复编辑器 focus/输入时 enter channel，消失/关闭 leave
- 失败静默，不影响输入
- 若服务端可拉取同频道 presence，详情底栏或编辑器附近展示“有人正在输入”（做不到则首发只上报，PRD 验收降级写清）

## Acceptance Criteria

- [ ] 启用条件下输入会发 presence（可用日志/代理验证）
- [ ] 关闭条件不发
- [ ] 不导致编辑器卡顿或重复风暴请求

## Out of Scope

- 自定义 presence 动画社交玩法
