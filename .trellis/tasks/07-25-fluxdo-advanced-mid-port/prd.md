# FluxDO 高级与中级能力全量移植

## Goal

将 FluxDO 中已确认、且 Dexo 尚未做透的 **高级 + 中级** 能力分批移植到 Dexo（UIKit / iOS 15+），补齐详情完成度、内容管理与输入体验，避免继续散落在口头需求里。

## Scope Map（Parent 只编排，实现落在 children）

### 高级（High）
| # | Child | 价值 | 复杂度 |
|---|---|---|---|
| 1 | `07-25-clipboard-topic-link` | 剪贴板话题链接识别打开 | 低 |
| 2 | `07-25-pending-posts` | 我的待审内容列表 | 低-中 |
| 3 | `07-25-post-revision-history` | 帖子修订历史对比 | 中 |
| 4 | `07-25-topic-card-style` | 话题卡片字段/布局自定义 | 中 |
| 5 | `07-25-nested-reply-view` | 树形回复视图 | 高 |

### 中级（Mid）
| # | Child | 价值 | 复杂度 |
|---|---|---|---|
| 6 | `07-25-ai-post-review` | AI 发帖/回复预审 + 快捷提示 | 中 |
| 7 | `07-25-user-signature-toggle` | 用户签名显示开关 | 低 |
| 8 | `07-25-whisper-indicator` | Whisper 悄悄话标识 | 低-中 |
| 9 | `07-25-presence-typing` | Presence 正在输入 | 中 |
| 10 | `07-25-mermaid-viewer` | Mermaid 全屏查看 | 低-中 |
| 11 | `07-25-notion-sync` | Notion 话题同步 | 中 |

## Delivery Order（强制）

1. clipboard-topic-link  
2. pending-posts  
3. user-signature-toggle  
4. whisper-indicator  
5. mermaid-viewer  
6. post-revision-history  
7. topic-card-style  
8. presence-typing  
9. ai-post-review（复用现有 AI model/chat 底座）  
10. nested-reply-view（最后，最大块）

依赖说明写在各 child `prd.md` / `implement.md`，树结构不隐含依赖。

## Cross-child Acceptance

- [ ] 11 个 child 各自可独立验收，不互相破坏现有详情/列表/编辑器主路径
- [ ] 全部 UIKit-only、iOS 15、本地化、无 Flutter 架构搬运
- [ ] 行为与 Discourse/FluxDO 端点契约对齐；故意简化处用 `ponytail:` 注释
- [ ] 相关单测 + `build-for-testing` 通过
- [ ] 不把 Notion / 桌面快捷键大全 / 无后端玩具功能塞进本父任务

## Out of Scope (Parent)

- （Notion 已单独立项 `07-25-notion-sync`）
- 桌面快捷键完整体系
- 再扩 metaverse 花活
- 与本批无关的 AI 聊天大重构（仅预审接入）
- 把未完成的 `07-25-emoji-sticker-share-polish` 子能力重复立项

## Notes

- 参考仓库：`/Users/naine/Documents/AndroidWorkspace/fluxdo`
- 用户要求：高级 + 中级全部集成；以 child 为单位规划与实现
