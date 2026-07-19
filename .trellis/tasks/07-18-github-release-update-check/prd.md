# GitHub Release 自动检查更新

## Goal

让 DexoFlux 从公开 GitHub Releases 自动检测新版本，并以符合 iOS 平台限制的方式提醒用户查看版本说明和获取更新包。

## User Value

- 用户无需手动访问 GitHub 即可知道有新版本。
- 自动检查失败不会影响启动、登录或论坛浏览。
- 用户可以在设置中手动检查，并控制是否自动检查。

## Confirmed Facts

- 更新源为 `https://github.com/moliango/dexoflux/releases`，API 为 `https://api.github.com/repos/moliango/dexoflux/releases/latest`。
- 当前稳定 Release 为 `v1.2-build.7`，包含 `dexoflux-unsigned.ipa` 和 GitHub 自动生成的 Release Notes。
- `Project.swift` 的 `MARKETING_VERSION` 当前为 `1.2`，`CURRENT_PROJECT_VERSION` 默认是 `1`；GitHub Actions 归档时用 `github.run_number` 覆盖 build number。
- Release tag 契约是 `v{marketingVersion}-build.{buildNumber}`。
- iOS 应用不能自行安装未签名 IPA；更新动作必须交给网页、下载/分享或用户已有的侧载工具。
- FluxDo 使用 GitHub `/releases/latest`、一小时缓存、ETag/304、默认开启的启动检查、手动检查、静默自动失败和更新详情弹窗。
- FluxDo 只比较三段纯数字语义版本，不兼容 DexoFlux 的 `v1.2-build.7` 标签，不能直接照搬。

## Requirements

- 使用 GitHub Releases API 获取最新的非草稿、非预发布稳定版本。
- 解析 `v{marketingVersion}-build.{buildNumber}`，同时比较 `CFBundleShortVersionString` 和 `CFBundleVersion`。
- 远端营销版本更高时判定有更新；营销版本相同但远端 build 更高时也判定有更新。
- 自动检查默认开启，启动后延迟执行且不阻塞首屏。
- 自动检查失败静默处理；手动检查失败显示可恢复错误。
- 支持 ETag/304 和本地缓存，降低 GitHub API 限流风险。
- 设置页提供“检查更新”和“自动检查更新”入口，并显示当前版本与 build。
- 发现更新时展示当前版本、最新版本、Release Notes、资源大小和操作按钮。
- 支持“稍后提醒”；忽略策略等待产品决定。
- 所有用户可见文案覆盖现有四语言。
- 网络层、解析层和 UI 层可独立测试。

## Acceptance Criteria

- [ ] `1.2 (6)` 能正确识别 `v1.2-build.7` 为更新。
- [ ] `1.2 (7)` 不会把 `v1.2-build.7` 判定为更新。
- [ ] `1.2 (99)` 能正确识别 `v1.3-build.1` 为更新。
- [ ] 草稿或预发布版本不会触发稳定渠道更新提示。
- [ ] 启动自动检查不阻塞首屏，失败时不弹错误。
- [ ] 手动检查能显示“已是最新版本”、更新详情或明确错误。
- [ ] GitHub 返回 304、403、429 或离线时按缓存策略处理。
- [ ] Release 缺少 IPA 资源时仍可打开 Release 详情页。
- [ ] 用户可在设置中关闭自动检查。
- [ ] 现有启动、登录和论坛导航不受影响。

## Out of Scope

- 应用内静默安装 IPA。
- 绕过 iOS 签名、企业证书或侧载工具限制。
- 自建更新服务器或强制更新后台。
- App Store / TestFlight 更新通道，除非后续单独接入。

## Open Questions

- 已决定：“立即更新”打开 GitHub Release 页面，由用户在网页中查看说明或下载 IPA。
- MVP 不提供“忽略此版本”或“永不提醒”按钮；用户可在设置中关闭自动检查，弹窗提供“稍后”。
- MVP 不实现强制更新或最低支持版本机制。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
