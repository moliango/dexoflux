# 主路径打磨（总包）

## Goal

把 DexoFlux 从“功能堆得很多”拉回到“每天主路径好用”：Home 列表、话题详情、登录会话/图片、列表基建真接入、超大文件可维护性。不新增边缘功能，只打磨高频路径。

## Why Now

- Home / TopicDetail / Settings / PostNativeCell 体量失控，改一处易炸三处。
- 列表刷新基建（Policy / ListStateView / Cache）已有半成品，但 Home 等主列表仍走私有逻辑。
- Cloudflare / 会话 / 图片链路复杂，是 Linux.do 可用性底线。
- 功能移植已阶段性完成，继续堆功能的边际收益低于主路径稳定性。

## Confirmed Facts（仓库）

- `HomeViewController` ~3300+ 行，自管 refreshControl、loadMore、tab bar geometry lock。
- `TopicDetailViewController` ~3000+ 行，`PostNativeCell` ~2800+ 行，首屏与长帖是性能热点。
- `DexoListRefreshPolicy` 目前主要接入 Me 话题列表；Home 未统一。
- `TopicListCache` 与 `BackgroundTopicListCache` 并存。
- 图片路径有 `CloudflareImageGate` / `ExternalImageFetcher` / cookie 分流。
- `SettingsViewController` ~5500+ 行。

## Scope Map（子任务）

| 子任务 | 目录 | 用户价值 |
|--------|------|----------|
| A Home 列表手感 | `07-29-home-list-feel` | 每天最高频 |
| B 详情流畅 | `07-29-topic-detail-perf` | 进帖体验与留存 |
| C CF/会话/图片 | `07-29-cf-session-images` | 能不能稳定用 |
| D 列表基建收口 | `07-29-list-infra-integration` | 消除双轨与半接入 |
| E 神文件拆分 | `07-29-god-file-split` | 后续改动成本 |

## Global Constraints

- 不改 Discourse API 合约语义（除非 C 中会话恢复必需的最小修复）。
- 不迁移 SwiftUI 大页。
- 不回退无关未提交功能；分享图图文混排等旁路改动可另 commit。
- 每子任务可独立验收、独立回滚。
- iOS 15+，UIKit，本地化字符串走现有 catalog。

## Cross-task Acceptance

- [ ] 五个子任务各自有可演示的验收路径。
- [ ] 主路径（启动 → Home 刷新/分页 → 进帖 → 看图/回复返回 → 通知角标）无新增明显回归。
- [ ] 全量 `xcodebuild build`（iphonesimulator generic）通过。
- [ ] 子任务按推荐顺序交付，或文档明确说明并行边界。

## Out Of Scope

- 新插件、新 AI 能力、DoH、Notion、表情包市场增强。
- 完整 FluxDO 视觉 1:1 重做。
- 一次性把 Settings 拆到“完美模块化”。

## Recommended Order

1. **A Home**（立刻可感）
2. **C CF/会话/图片**（与 A 可短并行调研，实现避免同时大改 Home 网络层）
3. **B 详情**（依赖 C 的图片稳定性结论）
4. **D 列表基建**（吃 A 的结论，把 Policy 真正接到主列表）
5. **E 神文件拆分**（在行为稳定后做，避免边拆边改行为）

若必须并行：A∥C 调研；B 实现与 D 设计可并行；E 最后。
