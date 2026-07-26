# 帖子修订历史

## Goal

在帖子详情中查看编辑历史与版本对比，对齐 Discourse revisions API 与 FluxDO revision UI。

## FluxDO Reference

- `lib/services/discourse/_revisions.dart`
  - `GET /posts/:id/revisions/latest.json`
  - `GET /posts/:id/revisions/:revision.json`
  - 可选：hide/show/revert/delete（权限门控）
- `lib/widgets/post/post_revision/*`

## Requirements

- 当 post 有 version/修订时展示入口（如“编辑过”）
- 打开修订 sheet/页面：版本切换、时间、编辑者、正文 diff 或前后对比
- 至少支持只读浏览 latest 与指定 revision
- 权限不足时隐藏危险操作；首发可只做只读浏览，写操作列入明确扩展
- 加载/错误/无修订态

## Acceptance Criteria

- [ ] 有修订的帖子可打开历史
- [ ] 可查看至少两个版本内容差异或前后文
- [ ] API 失败有错误提示
- [ ] 不影响正常读帖/回复

## Out of Scope（首发可延后，需在 design 标明）

- 永久删除全部修订
- 复杂 HTML diff 可视化到像素级（可用文本/分段对比）
