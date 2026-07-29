# 话题详情流畅 — 设计

## 测量优先

在改代码前加短时诊断（DEBUG 或临时日志）：

- `topic.open` → API 返回
- `topic.parse` → blocks 就绪
- `topic.first_cells` → 首屏 cell 配置完成
- `topic.reload` 计数

用数据决定先砍哪块，避免盲拆。

## 更新策略

```
数据变化
  ├─ 单帖字段（赞/书签/whisper 标记）→ reloadRows
  ├─ 插入新回复 → insertRows 或 section 差量
  └─ 结构失效（排序模式切换/大范围 raw 替换）→ reloadData（白名单）
```

## 图片与高度

- 图片加载完成：只 `invalidate` 对应 indexPath。
- 预估高度缓存：postId → height；复用时先吃缓存。
- 与 C 任务对齐：CF 门闩打开时详情不风暴重试。

## 边界

不在本任务大规模移动 `PostNativeCell` 文件（E 做）；本任务只允许为性能做最小提取（例如 HeightCache 小类型）。
