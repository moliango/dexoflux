# 神文件拆分 — 设计

## 原则

**行为冻结下的机械拆分。**

- 先 extract method，再 move file。
- 命名按用户任务：`HomePullRefreshController`、`TopicDetailMenuPresenter`，不按技术层乱起。
- 保持 `final class` 主类型稳定，避免到处改引用。

## 推荐第一刀（Home）

```
HomeViewController
  ├─ HomeViewController+Refresh.swift
  ├─ HomeViewController+ScrollTabBar.swift
  └─ HomeViewController+DataSource.swift（若自然）
```

## 推荐第二刀（TopicDetail）

```
TopicDetailViewController
  ├─ +Sharing.swift
  ├─ +PostActions.swift
  └─ +NavigationDeepLink.swift
```

## 风险

- merge conflict 大：拆分期间冻结他人同文件功能 PR。
- extension 过多：控制在职责清晰的 3–5 个/主类型。
