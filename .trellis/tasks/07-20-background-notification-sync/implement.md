# 实施计划：后台通知同步与提醒

- [x] 新增无 UI 后台同步引擎。
- [x] 为 DiscourseAPI 增加不启动 WKWebView 的后台请求上下文。
- [x] 保证后台网络层不触发 WKWebView、登录或 Cloudflare UI。
- [x] 增加多论坛、部分失败和取消测试。

## 验证结果

- 后台上下文禁用交互式 Web 恢复的策略测试通过。
- 认证、Cloudflare、瞬时失败和取消结果语义已覆盖。
