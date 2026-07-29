# 主路径打磨 — 总体设计

## 设计原则

1. **行为优先于抽象**：先修用户能感知的抖动/卡顿/挂图，再统一基建。
2. **一条主路径一个主人**：Home 刷新几何只允许一个所有权；详情高度估算只允许一个策略源。
3. **双轨必灭**：同类能力不允许长期两套（两套 cache、两套 refresh、两套 state view）。
4. **拆分不改语义**：E 阶段以文件边界移动 + 委托为主，禁止夹带功能变更。
5. **可观测**：关键失败路径要有可过滤日志前缀（`home.refresh` / `topic.firstpaint` / `cf.gate` / `img.fetch`）。

## 架构关系

```
启动/会话(C)
   │
   ▼
Home 列表(A) ──接入──► 列表基建(D: Policy/State/Cache)
   │
   ▼
Topic Detail(B) ──依赖──► 图片/CF(C)
   │
   ▼
稳定后拆神文件(E)
```

## 风险与缓解

| 风险 | 缓解 |
|------|------|
| Home geometry lock 与 Policy 冲突 | A 先固化 Home 行为契约；D 接入时 Home 可保留唯一 inset 所有权 |
| 详情大 refactor 引入功能回归 | B 以测量驱动：首屏时间、滚动掉帧、reload 次数；禁止无关 UI 改版 |
| CF 改动导致登录环 | C 先加诊断与单测/fixture，再改门闩策略 |
| 拆文件 diff 过大 | E 按垂直切片 PR：Home 切片、Detail 切片、Settings 切片 |

## 质量门槛（总）

- 每子任务：定向测试 + 手动主路径 checklist。
- 禁止“只 mock 被调用”的空测试。
- `git diff --check` 通过。
