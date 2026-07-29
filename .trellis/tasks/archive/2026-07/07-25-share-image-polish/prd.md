# 分享图预览与多主题

## Goal

把话题「生成分享图片」升级为 FluxDO 风格预览页：多主题、主帖/指定楼层富文本卡片、保存相册与分享。

## Requirements

- 预览页替代直接 UIActivity
- 主题：经典/纯白/深色/纯黑/蓝调/绿野，记忆上次选择
- 默认主帖富文本；支持指定楼层入口
- 卡片：品牌、标题(emoji)、作者、正文、链接
- 保存到相册 + 系统分享

## Acceptance Criteria

- [x] 预览/主题/保存/分享可用
- [x] 默认主帖；指定楼层入口正确
- [x] 视觉明显优于当前纯文本画布

## Dependencies

- 优先复用 child A 的标题 emoji 渲染

## Out of Scope

- AI 分享图
