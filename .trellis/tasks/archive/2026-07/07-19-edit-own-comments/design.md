# 技术设计：编辑自己发表的评论

## 数据与权限

- `DiscourseTopicDetail.Post` 增加 `raw`、`canEdit`、`yours`，缺失时安全回退为 `nil/false`。
- 菜单显示条件只使用 `canEdit`。`yours` 不作为授权条件。
- 点击编辑后再次请求 `/posts/{id}.json`，使用最新 `raw` 与 `can_edit`。

## API

- Router 增加 `post(id:)`：GET `/posts/{id}.json`。
- Router 增加 `updatePost(id:)`：PUT `/posts/{id}.json`。
- `DiscourseAPI.fetchPost(id:)` 返回可编辑帖子模型。
- `DiscourseAPI.updatePost(id:raw:)` 使用 `post[raw]` 嵌套参数；成功后重新获取帖子。

## 编辑器

- `ReplyComposerViewController` 增加明确的 `Mode`：回复或编辑。
- 回复模式保持现有行为。
- 编辑模式预填 raw，标题和按钮切换为编辑语义，提交调用 `updatePost`。
- 失败不 dismiss；成功通过独立回调返回已编辑 postId。

## UI 与回写

- `PostCellDelegate` 增加编辑事件。
- `PostNativeCell` 根据当前 Post 动态构建菜单，复用时重新生成。
- TopicDetail 保存成功后调用 `viewModel.reloadPost(postId:)`，再刷新对应 Cell。
- Replies 保存成功后调用现有 `loadReplies()`。

## 兼容与风险

- 单帖接口响应兼容直接 Post 或 `{post: Post}`。
- 服务端 403/422/429 统一走现有错误处理并保留编辑内容。
- WebView fallback 实现新增 delegate 链路，避免协议升级导致缺失。
