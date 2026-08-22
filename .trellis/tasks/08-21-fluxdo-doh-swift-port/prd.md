# Port FluxDo DoH proxy to Swift for Doer

## Goal

把 FluxDo `doh_proxy` 的本地代理能力用 **纯 Swift** 搬进 Doer，与 FluxDo 的 Rust 库彻底分开，只维护一套实现。开启 DoH 后，应用内 API、图片、WKWebView 都走同一套进程内 CONNECT 代理（DoH 解析 + MITM/隧道），不再依赖系统 DNS，也不再使用现在的 Encrypted DNS / 精简 CONNECT 双路径。

用户价值：linux.do 在 DNS 污染下可稳定打开；iOS 构建不绑 Rust 工具链，也不用同步维护 `libdoh_proxy`。

## Confirmed Facts

- FluxDo 实现是 Rust 仓库 `Lingyan000/fluxdo_doh`（本地 submodule `core/doh_proxy` 为空）。约 4862 行，能力不是“只做 DoH”，而是本地 HTTP CONNECT 代理。
- 模块：DoH A/AAAA、HTTPS 记录取 ECH config、CONNECT MITM、CF 验证域名纯隧道、Gateway、h2 MITM、HTTP/SOCKS5/Shadowsocks 上游、per-device CA、DNS 缓存/粘性 IP/RTT。
- FluxDo Apple 端自己的 PRD（`fluxdo/docs/doh-proxy-swift-prd.md`）把 ECH + MITM 定为硬需求，并禁止用系统自动 ECH 冒充 rustls 可注入 config 的语义。
- Doer 已有精简 Swift 子集：`EncryptedDnsService`（PrivacyContext）、`LocalConnectProxy`（CONNECT/SOCKS + MITM）、`MitmCertificateAuthority`、`DohResolver`（仅 `linux.do`）、设置页开关。
- 现有 MITM **不是** FluxDo 对等实现，只是原型，第一批必须做成可用的 CONNECT MITM，不能跳过：
  - 只对 `linux.do` MITM；其它 CONNECT 走系统 DNS 直通。
  - 客户端 TLS 用已弃用的 SecureTransport（`SSLCreateContext`），握手忙等 40 次 + semaphore 阻塞读写。
  - 出口 TLS 已用 `NWProtocolTLS` 连 DoH IP（这层可留）。
  - Alamofire 只给 `linux.do` 挂了 `MitmTrustEvaluator`。
  - WKWebView 信任只接了登录页和 session 刷新；应用内浏览器、Cloudflare 验证页没有 `MitmTrust.handle`。
- FluxDo 默认 `mitm_connect=true`、`h2_mitm=false`：普通 HTTPS CONNECT 做 MITM，叶证书 ALPN 锁 `http/1.1`，明文拷贝到上游 TLS。`h2 MITM` 是另一条 hyper 多路复用路径，默认关。
- Doer 接入点已经存在，全搬后应继续走这些入口，而不是再加一套 Dart/FFI：
  - `DiscourseAPI.makeSession` → `LightweightDohProxyService.apply`
  - `WKWebsiteDataStore.default().proxyConfigurations`（iOS 17+）
  - `WebLoginViewController` / 应用内浏览器共用 default store
  - `AvatarImageLoader` / `ExternalImageFetcher`
  - `NetworkSettingsViewController` / `AppSettings+DoH`
- Doer 没有 Dio/rhttp。FluxDo 的 Gateway 是给 Dio 减一层 TLS 用的；Doer 的等价路径是 URLSession 也走 CONNECT MITM。
- Doer 没有上游代理设置 UI。FluxDo 有 HTTP / SOCKS5 / Shadowsocks。
- Doer 最低 iOS 15。WKWebView `proxyConfigurations` 需要 iOS 17。
- 纯 Swift / Network.framework **不能**把 DNS HTTPS 记录里的 ECH config bytes 注入 ClientHello。
- 已拍板：**全部 Swift，不链 rustls-ffi，不链 `libdoh_proxy.a`。** 理由是不维护两套实现。这是对 FluxDo 现网的有意偏离：出口 TLS 用 Network.framework，SNI 仍按系统 ClientHello 发送。
- `.trellis/spec/frontend/fluxdo-porting.md`：行为从 FluxDo 按契约搬，UI 用 Doer 原生卡片，不搬 Flutter 架构。本任务的 ECH 偏离必须在 implement.md 用 `ponytail:` 标明。

## Requirements

1. 用 Swift 在 Doer 进程内实现 FluxDo 同构的本地 HTTP CONNECT 代理，替换当前 `EncryptedDnsService` + 精简 `LocalConnectProxy` 双路径。
2. 开启 DoH 后：
   - Discourse API（Alamofire / URLSession）走本地代理。
   - WKWebView（登录、应用内浏览器、Cloudflare 验证）走本地代理。
   - 图片加载走同一套解析/出口策略，且不能和代理配置冲突导致 CFNetwork 失败。
3. DoH 解析：用户选择的 DoH URL、bootstrap IP（不先走系统 DNS）、A/AAAA、TTL 缓存、inflight 去重、失败可观测。
4. **CONNECT MITM 是第一批硬需求**（FluxDo 默认路径，不是可选项）：
   - 启用 DoH 后，普通 HTTPS CONNECT 必须 MITM：用 per-device CA 为当前 Host 签发叶证书，对客户端完成 TLS，再向源站发起独立 TLS。
   - 出口连 DoH 解析到的 IP，SNI 使用真实 Host，不得再走系统 DNS。
   - 解析与 MITM 不限 `linux.do`：WKWebView 碰到的任意 HTTPS Host 都走 DoH + MITM，只有 `challenges.cloudflare.com` 禁止 MITM、必须纯隧道。
   - 默认叶证书 ALPN 锁 `http/1.1`（与 FluxDo `h2_mitm=false` 一致）。
   - 替换 SecureTransport 原型，客户端 TLS 用可维护的 Swift TLS 栈，禁止 `SSLCreateContext`。
   - 所有会走该代理的 WKWebView 都必须在原生层信任本地 CA，禁止漏接 challenge。
5. 出口 TLS 连到 DoH 解析出的 IP，不得把真实 Host 再交给系统 DNS。
6. 设置页保留现有 DoH 开关/服务器列表，并补齐 FluxDo 对等的可观测性（代理端口、缓存条目、失败原因）以及第一批开关：h2 MITM、IPv6 优先、可选固定 server IP、上游代理。
7. 不引入 Flutter/Dart/FFI 总控，不引入任何 Rust 静态库或 rustls-ffi。实现留在 `Doer/Networking/DoH/`，由现有 `LightweightDohProxyService` 门面调度。
8. **不做可注入 ECH。** 不查询 HTTPS/SVCB 的 ECH config，设置页不展示“ECH 可用”。出口 TLS 连 DoH IP 时使用常规 TLS（SNI 明文）。
9. **h2 MITM 开关**（默认关）：关闭时锁 HTTP/1.1 并明文拷贝；打开后必须与客户端真协商 HTTP/2 并多路复用转发，不能假开或静默锁死 HTTP/1.1。
10. **上游代理**：HTTP CONNECT、SOCKS5、Shadowsocks（`aes-128-gcm` / `aes-256-gcm` / `chacha20-ietf-poly1305` / `2022-blake3-aes-256-gcm`）均可建连。密码进 Keychain，不进 UserDefaults。

## Acceptance Criteria

- [ ] 开启 DoH 后，`linux.do` API 请求不走系统 DNS；设置页能显示本地代理已启动及端口。
- [ ] 关闭 DoH 后，API / WebView / 图片恢复系统网络，无残留代理字典或 `proxyConfigurations`。
- [ ] 默认 CONNECT 为 MITM：任意普通 HTTPS Host（不限 `linux.do`）客户端看到 per-device CA 签发的叶证书；Alamofire 与所有走代理的 WKWebView 信任评估通过。
- [ ] MITM 出口 TCP 连的是 DoH IP，TLS SNI 是真实 Host；抓包不得再出现对该 Host 的系统 DNS。
- [ ] 访问 `challenges.cloudflare.com` 不 MITM，Turnstile 可完成。
- [ ] 不再使用 `SSLCreateContext` / SecureTransport 做 MITM 客户端握手。
- [ ] h2 MITM 关闭时，经代理的 HTTPS 锁 HTTP/1.1；打开后 WebView/API 经代理实际协商到 HTTP/2。切换后代理重建，无孤儿端口。
- [ ] HTTP、SOCKS5、Shadowsocks 上游均可建连并完成至少一个 HTTPS 请求；Shadowsocks 密码只存在 Keychain。
- [ ] 设置页可看缓存条目、清空缓存、看到失败原因；切换 DoH 服务器 / h2 / 上游后代理按新配置重建。
- [ ] 设置页不出现“ECH 可用”；代码不查询 HTTPS/SVCB ECH config。
- [ ] iOS 17+ WKWebView 走 CONNECT MITM；iOS 15–16 WebView 仅 Encrypted DNS 兜底（无 MITM），设置页有说明。

## Out of Scope

- 把 Swift 实现编译进 Android / Windows / Linux，或改 FluxDo 主仓库。
- 引入 Dart `DohProxyService` / rhttp / Dio Gateway 原样架构。
- **Gateway 反向代理**（FluxDo 给 Dio 减一层 TLS；Doer 等价路径是 URLSession CONNECT MITM）。
- 改变 DoH 服务器产品列表的默认品牌（Cloudflare / Google / Quad9 / AliDNS / DNSPod / 自定义）。
- 把 per-device CA 私钥打进仓库或随包分发同一把密钥。
- 可注入 ECH（rustls `EchConfig` / rhttp `echConfigList` / 系统自动 ECH 冒充）。
- 继续维护或打包 FluxDo 的 `core/doh_proxy` / `libdoh_proxy.a`。
- 逐字节复刻 `tls_crypto.rs` 的 Chrome 密码套件排序。

## Notes

- 复杂改造，需要 `design.md` 和 `implement.md`。
- 第一批全要：默认 MITM（ALPN 锁 HTTP/1.1 + 明文拷）+ HTTP/SOCKS5/Shadowsocks 上游 + h2 MITM 开关。
- 相关入口：
  - FluxDo Rust：`/tmp/fluxdo_doh/src/{proxy,dns,ech,cert,upstream,tls_crypto}.rs`
  - FluxDo Dart：`lib/services/network/doh_proxy/`、`lib/services/network/doh/`、`lib/services/network/proxy/`
  - Doer：`Doer/Networking/DoH/`、`DiscourseAPI.swift`、`WebLoginViewController.swift`、`NetworkSettingsViewController.swift`
