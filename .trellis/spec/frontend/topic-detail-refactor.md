# TopicDetail 重构方案

**背景**
- `TopicDetailViewController.swift` 1668 行，是 ForumDetail 最大黑洞
- 已拆出多个 +XXX.swift，但核心职责（生命周期、UI 配置、action、状态管理）仍在主文件
- 继续堆功能会导致可测性、可读性持续恶化

**推荐拆分结构**

1. **TopicDetailCoordinator**（新增，550-650 行）
   - 负责整个页面的生命周期管理
   - 子 VC 管理（RepliesViewController、BoostInputViewController、MermaidViewer 等）
   - 通知路由、Cloudflare 验证观察
   - 所有 action（reply、share、bookmark、export、notion 等）

2. **扩充 TopicDetailViewModel**（已有，继续补）
   - 把所有配置逻辑、状态、订阅移进来
   - `updateUI()`、`applyThemeStyle()`、`applyTypography()`、`configureTitleLabel()`、`sharedIssueState()` 等

3. **TopicDetailViewController**（剩下约 700-750 行）
   - 只保留视图搭建 + 数据源 + layoutSubviews + 少数生命周期钩子

**PostNativeCell 继续拆（1188 行）**

- 继续拆出：
  - PostNativeCell + PostContentRenderer（渲染层）
  - PostNativeCell + PostActions（交互层）
  - PostNativeCell + PostMedia（媒体处理层）

**PluginCenterViewController（1262 行）**

- 拆成：
  - PluginCenterViewModel（数据 + 拖拽排序）
  - PluginCenterCoordinator（sheet 管理、导航）
  - 剩下根容器 + 列表

**ForumContainerViewController（1020 行）**

- 拆成 **ForumCoordinator**（根容器生命周期、登录态、Cloudflare、通知路由）

**实施建议**
- 优先级顺序：TopicDetail → PostNativeCell → PluginCenter → ForumContainer
- 改完后必须跑 `make generate`
- 改完后重点 review：数据源回调、状态同步、Coordinator 注入
- 预计 TopicDetail 拆完后，主文件能降到 700 行以内

**新增文件**
- .trellis/spec/frontend/topic-detail-refactor.md
