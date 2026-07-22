# 技术设计：后台通知投递与集成

- `ForumNotificationDeliveryStore` 统一游标键、首次基线和新增通知筛选。
- `ForumLocalNotificationPresenter` 持久化 scope 未读数，并提供原子更新/清理接口。
- presenter 的后台路径只读取授权状态；只有 App 活跃时才允许请求首次授权。
- delivery pipeline 在同步快照成功后更新 scope 与游标，再投递最多最近 3 条通知。
- 失败论坛不推进游标、不覆盖最后已知角标。
- 前台 `ForumNotificationCoordinator` 改用相同 delivery store，避免前后台重复提醒。
- BGTask handler await 完整 pipeline 后再完成任务；expiration 通过取消向下传播。
