# 实施计划：编辑自己发表的评论

## A. 数据与 API 契约

- [x] Post 解码 `raw/can_edit/yours`
- [x] 增加单帖 GET 与正文 PUT 路由
- [x] 增加 fetch/update API 与兼容响应模型
- [x] 增加模型、路由和参数测试

## B. 编辑器模式

- [x] ReplyComposer 增加 reply/edit 模式
- [x] 编辑态预填 raw，切换标题和保存按钮
- [x] 编辑态提交 updatePost，失败保留内容
- [x] 增加模式策略测试

## C. 菜单和刷新

- [x] PostCellDelegate 增加编辑回调
- [x] Native Cell 仅在 canEdit 时显示编辑菜单
- [x] TopicDetail 拉取 raw、展示编辑器并精准刷新单帖
- [x] Replies 页面接入编辑并刷新列表
- [x] 处理 fallback Cell 协议一致性

## D. 国际化与验证

- [x] 增加编辑评论相关国际化
- [x] 测试 Cell 复用后权限菜单不残留
- [x] `xcodebuild build-for-testing`
- [ ] 定向运行新增测试
- [x] `git diff --check`

## 回滚点

- API、Composer 模式、Cell 入口保持独立边界；若服务端响应不兼容，可先隐藏入口而不影响回复功能。
