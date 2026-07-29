# 话题详情流畅 — 实施

## Steps

1. 加首屏/reload 诊断日志（可 `#if DEBUG`）。
2. 盘点 `reloadData` 调用点，分类：可差量 / 必须全量。
3. 实现或加固 postId 高度缓存；图片完成回调走 `reloadRows`。
4. 书签/反应/编辑成功路径改为局部更新（若已有则补回归测试）。
5. 检查 cell `prepareForReuse` 取消图片与异步解析。
6. 手动：短帖、长帖、多图帖、嵌套开/关、编辑保存。
7. 去掉或降级临时日志。

## Validation

- 手动帧率体感 + reload 计数下降（改前改后对比记在 research）。
- build 通过。

## Done in code
- postRowHeightCache for estimatedHeight
- clear cache on emoji-map full reload path
