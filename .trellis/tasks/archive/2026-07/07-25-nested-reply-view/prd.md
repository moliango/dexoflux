# 树形回复视图

## Goal

在 Topic Detail 提供可选的树形/嵌套回复视图，支持展开、深度限制与子树 sheet，对齐 FluxDO nested 体验的核心能力。

## FluxDO Reference

- `lib/widgets/nested/*`
- `lib/models/nested_topic.dart`
- nested provider / maxDepth / continue thread sheet

## Requirements

- 阅读设置或详情菜单：扁平 / 树形 切换，持久化
- 树形：按 reply_to 关系缩进展示；深节点可“继续此主题”打开子树
- 与现有分页、跳楼、只看楼主、回复/编辑/反应共存（允许首发对部分动作降级，但必须写明）
- 性能：长帖不可卡死；可虚拟化或限制首屏深度
- 切换视图不丢失当前阅读位置（尽力）

## Acceptance Criteria

- [ ] 可在扁平/树形间切换
- [ ] 树形正确反映回复关系
- [ ] 超深回复可进入子树浏览
- [ ] 回复/点进用户等基础操作仍可用
- [ ] 大 topic 不显著卡顿（定性：可滚动、可进入）

## Dependencies

- 建议在 post-revision / whisper 标识之后，避免详情 cell 同时大改冲突
- 不依赖 AI/Notion

## Out of Scope

- 完美复刻 Flutter 动画
- 无限深度一次全量渲染
