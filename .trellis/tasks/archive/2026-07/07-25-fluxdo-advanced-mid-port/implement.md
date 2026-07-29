# Implement — parent

按 PRD Delivery Order 逐个 `task.py start <child>` → before-dev → 实现 → check → 再下一个。

Gate:
- 每完成 2-3 个轻量 child，跑一次 `build-for-testing`
- nested / AI review 单独加长验证

当前不 start parent 本体。
