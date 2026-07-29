# Mermaid 全屏查看器

## Goal

对帖子中的 Mermaid 代码块提供更大、可缩放/分享友好的全屏查看体验。

## FluxDO Reference

- `lib/pages/mermaid_viewer_page.dart`
- Dexo 已有 `CodeBlockRenderer` mermaid 识别

## Requirements

- 代码块 mermaid：点击放大/全屏
- 全屏页渲染图表；失败显示源码与错误
- 支持关闭返回
- 尽量复用现有渲染路径，不新引入沉重 Web 栈（若必须 WKWebView，需隔离）

## Acceptance Criteria

- [ ] mermaid 块可进入全屏查看
- [ ] 成功渲染或可读降级
- [ ] 普通代码块行为不变

## Out of Scope

- 在编辑器内 live mermaid 预览（可二期）
