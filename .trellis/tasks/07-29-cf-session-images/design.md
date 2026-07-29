# CF/会话/图片 — 设计

## 状态机（概念）

```
normal ──challenge──► blocked ──user verified / grace──► normal
                └──image pause──►
```

- `blocked`：API 与主域图暂停或走挑战 UI。
- `grace`：短时间忽略 image 侧重复 challenge，避免盾闪烁。

## 原则

- **单一挑战入口**：image 与 API 最终都归到同一 policy 决策。
- **恢复要幂等**：多次 verified 回调不重复刷全站 reload 风暴（可 debounce）。
- **先测后改**：cooldown/grace/host 判断纯函数化便于测。

## 与其他任务

- B 详情依赖本任务的“暂停期不风暴重试”。
- A Home 在 challenge 时错误态文案可复用统一字符串。
