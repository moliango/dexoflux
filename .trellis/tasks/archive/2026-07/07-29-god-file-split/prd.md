# 神文件拆分与可维护性

## Goal

在行为已稳定的前提下，把超大文件按职责切开，降低后续改动风险。不夹带功能变更。

## Confirmed Facts

- Settings ~5500、Home ~3300、TopicDetail VC ~3000、PostNativeCell ~2800。

## Requirements（细拆）

### E1 拆分目标（量化）

- 单个主 VC 实现文件目标 < 1500 行（分期达到，本任务至少完成 **Home 或 TopicDetail 其一** 降到可维护切片）。
- 本任务交付至少两刀有意义的垂直拆分（例如 Home 滚动/刷新、Detail 菜单/分享、Cell 配置分段）。

### E2 拆分方式

- 优先 `extension` 分文件或独立 helper/coordinator 类型。
- 禁止改变对外行为与 IB/导航结构。
- 每刀拆分可单独 compile 与手动点验。

### E3 范围选择（推荐顺序）

1. `HomeViewController`：Refresh/Scroll/TabBar 相关 → `HomeScrollCoordinator` 或 extension 文件。
2. `TopicDetailViewController`：分享/菜单/通知跳转 → 独立类型。
3. `PostNativeCell`：configure 分段（header/body/footer）。
4. `SettingsViewController`：按 settings section 拆 extension（可放后续 PR）。

### E4 守卫

- 拆分 PR 描述必须写“无行为意图变更”。
- 若必须改行为，挪到 A/B/C/D 任务，不在 E 混进。

## Acceptance Criteria

- [ ] 至少两个大文件出现可导航的职责边界（新文件 + 清晰命名）。
- [ ] 主路径手动回归通过。
- [ ] build 通过；diff 以 move/extract 为主。
- [ ] 行数或认知负担可量化对比（拆前/拆后行数表）。

## Out Of Scope

- 架构升级到全新模块化工程、SPM 大拆。
- 重写 Settings 信息架构。
