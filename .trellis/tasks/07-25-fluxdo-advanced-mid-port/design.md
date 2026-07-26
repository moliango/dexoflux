# Design — parent orchestration

## Strategy
- Parent owns sequencing, cross-acceptance, and conflict watch on Topic Detail / Home card / Composer.
- Each child owns API + UI + tests.
- Shared utilities (link parser, settings keys, post badges) go to existing Core/Settings or small shared helpers — no new framework.

## Conflict Surfaces
- `PostNativeCell` / topic detail：revision、whisper、signature、nested 会碰同一 cell → 按 delivery order 合并
- `AppSettings`：新增开关集中，避免键名冲突
- Composer：AI review 与已有 sticker/emoji 面板分区

## Rollback
- 每个 child 可独立回滚；nested 与 AI review 风险最高，最后做
