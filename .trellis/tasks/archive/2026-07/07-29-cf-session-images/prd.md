# Cloudflare 会话与图片稳定性

## Goal

降低 CF 挑战、会话漂移、主站图/外链图加载失败对主路径的破坏；挑战期间行为可预期，恢复后能自动续上。

## Confirmed Facts

- 存在 `CloudflareImageGate`、`CloudflareVerificationPolicy`、`WebSessionRefreshService`、`WebCookieStore`。
- 主域图片可能带 cookie；外链 cookieless + Referer。
- 图片挑战会 pause 主域下载并 post 通知。

## Requirements（细拆）

### C1 挑战可预期

- 检测到 CF 挑战时：用户有明确恢复入口（已有则验收稳定性）。
- 挑战期间图片失败不形成死循环通知刷屏（coalesce 已有则验证冷却有效）。
- 验证 grace 期内忽略重复 image challenge。

### C2 会话

- API 401/挑战后的 session refresh 成功路径可恢复列表/详情。
- refresh 失败不破坏本地已登录标记到“假登录”态而不提示。
- 多账号/多论坛（若仍支持切换）cookie 不串（按现有账户模型验收）。

### C3 图片

- 主域 uploads 与外链床在正常会话下成功率可接受（抽测）。
- gate pause 期间不狂重试；恢复后可见图可自动或手动恢复。
- Avatar 与正文图策略一致，不一边通一边死。

### C4 诊断

- 统一日志：`cf.challenge` / `cf.grace` / `session.refresh` / `img.gate`。
- 关键策略函数可单测（cooldown、grace、host 分流）。

## Acceptance Criteria

- [ ] 模拟/构造挑战通知不会 1 秒内连发。
- [ ] grace 内 image challenge 不重复打断。
- [ ] 会话恢复后 Home/详情请求可继续。
- [ ] 主域/外链图片分流单测或固定 fixture 覆盖。
- [ ] build 通过。

## Out Of Scope

- 自建反代、改 DNS/DoH。
- 重写整套 Networking。
