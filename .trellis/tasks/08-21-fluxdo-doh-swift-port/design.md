# 技术设计

把 FluxDo `doh_proxy` 的进程内 CONNECT 栈用纯 Swift 接到 Doer 现有入口上。不链 Rust，不引入 Dart/FFI，不提供可注入 ECH。

## 架构

```
DiscourseAPI / SDWebImage / URLSession
WKWebView (iOS 17+ proxyConfigurations)
        │
        ▼
127.0.0.1 CONNECT / SOCKS5   LightweightDohProxyService
        │
        ├─ DoH A/AAAA（bootstrap IP，不走系统 DNS）
        ├─ challenges.cloudflare.com → 纯隧道（端到端 TLS）
        ├─ 默认 MITM：本地 CA 叶证书终止客户端 TLS
        │     ALPN 锁 http/1.1 → 明文拷到上游 TLS
        ├─ h2 MITM 开：客户端协商 h2 → HTTP/2 多路复用转发
        └─ 可选上游：HTTP CONNECT / SOCKS5 / Shadowsocks
              然后再对源站做 TLS（SNI = 真实 Host）
```

门面仍叫 `LightweightDohProxyService`，避免改遍调用点。内部从“Encrypted DNS + 精简 CONNECT”改成一条代理路径。

## 模块边界

全部放在 `Doer/Networking/DoH/`。UIKit 调用方只碰门面、`MitmTrust`、`AppSettings+DoH`。

| 文件 | 职责 | 处置 |
|---|---|---|
| `LightweightDohProxyService.swift` | 启停、签名、挂 URLSession / WKWebView / 图片 | 改：DoH 开则所有 session 挂 CONNECT，不再按 `linux.do` 过滤 |
| `LocalConnectProxy.swift` | 回环监听、CONNECT/SOCKS 解析、分流 MITM/隧道 | 改：任意 Host DoH 解析；CF 强制隧道 |
| `DohResolver.swift` | A/AAAA、TTL 缓存、inflight 去重、粘性 IP、RTT | 改：去掉 `isAllowedHost`；DoH 查询必须打 bootstrap IP |
| `MitmCertificateAuthority.swift` | per-device CA + 叶证书；ALPN 随 h2 开关 | 留，补 h2 ALPN |
| `MitmTrust.swift` | Alamofire evaluator + WKWebView challenge | 改：所有 Host；再加一层 WKWebView 原生信任，防漏接 |
| `MitmTLSBridge.swift` | 客户端 TLS 终止 | **删 SecureTransport**，换成 NIOSSL acceptor |
| `EncryptedDnsService.swift` | PrivacyContext Encrypted DNS | **仅 iOS 15–16 WebView DNS 兜底**；iOS 17+ 关闭，避免和 CONNECT 混用 |
| `DohProxyConfig.swift` | 运行时配置快照 | 新 |
| `UpstreamProxyClient.swift` | HTTP CONNECT / SOCKS5 / Shadowsocks 建隧 | 新 |
| `H2MitmForwarder.swift` | h2 开关打开后的多路复用转发 | 新 |
| `Socks5Handshake.swift` / `DohConnectRequest.swift` | 本地 SOCKS/CONNECT 解析 | 留 |

设置：`AppSettings+DoH.swift` + `NetworkSettingsViewController.swift`。上游密码走 Keychain，tag `com.naine.doer.doh.upstream-password`。

## 运行时合同

`DohProxyConfig` 在 `configureFromSettings()` 时从 UserDefaults + Keychain 拍快照，签名变化则重建监听。

```
dohEnabled
dohServerURL + bootstrapIPs
h2Mitm                 默认 false
preferIPv6             默认 false
serverIP               可选，跳过解析
upstream: protocol/host/port/username/cipher + Keychain password
```

默认值对齐 FluxDo 现网：`mitm_connect=true`（Doer 不暴露关闭开关）、`h2_mitm=false`。没有 Gateway 开关。

重建规则：开关 DoH、换服务器、改 h2、改 IPv6、改 server IP、改上游，都要停旧 `NWListener` / NIO 服务再起，旧连接取消，`configurationVersion += 1`，让 `DiscourseAPI.session` 换新 `URLSession`。

## 数据流

### 1. 默认 MITM（第一批主路径）

1. 客户端发 `CONNECT host:443`。
2. 若 Host 是 `challenges.cloudflare.com` → 走第 2 条纯隧道。
3. DoH 解析 A/AAAA（有 `serverIP` 则跳过）。失败回 502，不回落系统 DNS。
4. 出口 TCP 连解析出的 IP（或先连上游代理再 TLS）。`NWProtocolTLS` / NIOSSL 客户端 SNI = 真实 Host。**ponytail: 无 ECH，ClientHello 外层 SNI 明文。**
5. 上游 TLS 成功后回 `HTTP/1.1 200 Connection Established`。
6. 用叶证书对客户端做 TLS server，ALPN 只提供 `http/1.1`。
7. 握手后明文双向拷贝。

### 2. 纯隧道

只用于 CF 验证域名。DoH 解析后裸 TCP 转发，客户端端到端 TLS。禁止签发叶证书。

### 3. h2 MITM（默认关）

开关打开：叶证书 ALPN = `h2` + `http/1.1`。客户端选 `h2` 时走 `H2MitmForwarder`（NIOHTTP2 服务端 + 到源站的 h2/h1 客户端，按 ALPN）。客户端选 `http/1.1` 则仍明文拷。关闭时不得协商到 h2。

### 4. 上游代理

有效配置时，到源站的 TCP 换成：

- HTTP：`CONNECT host:port`，可选 Basic
- SOCKS5：greeting + 可选 user/pass + domain CONNECT（socks5h）
- Shadowsocks：AEAD 2017（aes-128/256-gcm、chacha20-ietf-poly1305）和 SIP022 `2022-blake3-aes-256-gcm`

上游自身若是域名，用 bootstrap/DoH 解析，禁止系统 DNS。密码只读 Keychain。

### 5. 接入点

| 调用方 | 行为 |
|---|---|
| `DiscourseAPI.makeSession` | DoH 开则挂 CONNECT 字典；`ServerTrustManager` 用全 Host MITM evaluator |
| `AvatarImageLoader` / `ExternalImageFetcher` | 同样挂 CONNECT，**不要**再清代理改走 Encrypted DNS |
| iOS 17+ `WKWebsiteDataStore.default()` | `ProxyConfiguration(httpCONNECTProxy:)` |
| iOS 15–16 WKWebView | 系统不支持 `proxyConfigurations`；只开 PrivacyContext Encrypted DNS 做解析兜底，设置页写明无 MITM |
| 登录 / 应用内浏览器 / session 刷新 / CF 验证页 | 信任本地 CA |

回环例外：`ExceptionsList` 含 `127.0.0.1` / `localhost` / `::1`，避免代理自连。

## TLS 选型

Network.framework **不能**在已完成的 CONNECT TCP 上升级成 TLS server，所以不能用 `NWListener` TLS 替代 FluxDo 的 `TlsAcceptor`。

客户端 MITM 与 h2 使用 Swift 包（不是第二套产品）：

- `swift-nio-transport-services`：iOS 上跑 NIO，底层仍是 Network.framework
- `swift-nio-ssl`：CONNECT 之后的 TLS server / 上游 TLS client
- `swift-nio-http2`：h2 MITM

依赖加在 `Tuist/Package.swift`（与 Alamofire 一样走 `.external`），`Project.swift` 给 Doer target 加 product。`make generate` 之后才能编。

项目级 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。NIO EventLoop 上的类型必须 `nonisolated`，禁止从 EventLoop hop 到 MainActor 再同步等。现有 DoH 类型已经是 `nonisolated final class`，新代码沿用。

## 证书与信任

- CA 仍是设备内 RSA 2048，Keychain tag 不变。禁止打包同一把 CA。
- 叶证书 SAN = 当前 Host，密钥复用（与 FluxDo 相同）。
- Alamofire：`allHostsMustBeEvaluated: false` 不够。DoH 开时用一个默认 `MitmTrustEvaluator` 覆盖任意 Host，失败再回系统信任。
- WKWebView：每个 `WKNavigationDelegate` 显式 `MitmTrust.handle`，并在 `WKWebView` 层做一次原生信任挂钩，避免漏掉应用内浏览器、弹窗 WebView、CF 验证页。
- 关闭 DoH 后停止挂钩，恢复系统信任。

## DoH 解析

- 查询连接 DoH 服务器的 **bootstrap IP**，TLS SNI / HTTP Host 仍是 DoH 域名。禁止先用系统 DNS 解析 `dns.alidns.com` 这类主机名。
- 自定义 URL：Host 已是 IP 则用作 bootstrap；否则用可选 `dohCustomBootstrapIPs`。都没有则启动失败并在状态行显示原因，不静默回落系统 DNS。
- TTL 夹在 60…1800s（对齐 FluxDo）。inflight 去重。缓存上限 1000。粘性 IP 10 分钟。失败 IP 短惩罚。
- **ponytail: 不查 HTTPS/SVCB，不做 ECH 负缓存。**

## 设置 UI

`NetworkSettingsViewController` 原生卡片，不搬 Flutter。

保留：DoH 开关、服务器列表、自定义 URL、状态、CF 验证入口、调试日志。

新增：

- 状态行带端口
- 缓存条数 + 清空
- h2 MITM 开关（默认关，副标题说明关=HTTP/1.1、开=真 h2）
- IPv6 优先
- 可选固定 server IP
- 上游：协议 / 主机 / 端口 / 用户名 / 密码 / SS cipher；测试按钮
- iOS 15–16 提示：浏览器不走 CONNECT MITM

文案走 `String(localized:)`，中文写进 `Localizable.xcstrings`。不要出现 ECH。

## 兼容与迁移

| 现状 | 目标 |
|---|---|
| 只 MITM / 只解析 `linux.do` | 任意 Host；CF 除外不 MITM |
| API 只对 `linux.do` 挂代理 | DoH 开则所有 `apply(to:)` 都挂 |
| 图片清代理、走 Encrypted DNS | 图片走同一 CONNECT |
| SecureTransport 忙等 + semaphore | NIOSSL 异步 |
| `EncryptedDnsService` 全局 | 仅 iOS 15–16 WebView |
| `shouldMITM("example.com") == false` | 变为 true |

UserDefaults 旧键（`dohEnabled` / `dohProvider` / `dohCustomURL`）保留。新键默认值等于 FluxDo 现网默认，现有用户打开 DoH 即进入默认 MITM。

## 有意偏离（implement 时写 `ponytail:`）

1. **无 ECH。** 出口 ClientHello 外层 SNI 明文。不查 HTTPS 记录，UI 不写 ECH。
2. **无 Gateway。** URLSession CONNECT MITM 替代 Dio 明文反代。
3. **不复刻 Chrome JA3 套件序。**
4. **iOS 15–16 WebView 无 CONNECT。** 系统限制；API/图片仍走 CONNECT。
5. **不暴露 `mitm_connect=false`。** 默认 MITM 是产品路径，CF 除外。

## 回滚

总开关仍是 `dohEnabled`。关掉必须：停监听、清 `connectionProxyDictionary` / `proxyConfigurations`、停 Encrypted DNS、停 CA 挂钩、`DiscourseAPI` 因签名变化换 session。NIO 依赖可留在工程里，运行时不启动。

## 风险

- NIO + 项目 MainActor 隔离：所有代理 I/O 保持 `nonisolated`。
- Shadowsocks 2022 比 AEAD 2017 重（Blake3、会话、时间戳）；四个 cipher 都要能测通。
- 全 Host MITM 会签 CDN 叶证书，WKWebView 漏接信任会直接握手失败 → 原生层统一挂钩是硬需求。
- 图片曾经不能混 SOCKS 和 Encrypted DNS；统一 CONNECT 后禁止再给 SDWebImage 开 PrivacyContext。
