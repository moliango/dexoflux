# 实施计划

按顺序做。每步可单独编译；不要先铺 UI 再补协议。

有意偏离必须在代码里用 `ponytail:` 标出（见 `design.md`）：无 ECH、无 Gateway、不复刻 Chrome JA3、iOS 15–16 WebView 无 CONNECT、不暴露 `mitm_connect=false`。

## 0. 依赖与配置模型

- [ ] `Tuist/Package.swift` 增加 `swift-nio`、`swift-nio-ssl`、`swift-nio-http2`、`swift-nio-transport-services`；`Project.swift` Doer target 加对应 product（`.external`，与 Alamofire 相同，不要再走一份 `.package` URL）。
- [ ] 新增 `DohProxyConfig`：从 UserDefaults + Keychain 拍快照；签名变化才重建。
- [ ] `AppSettings+DoH`：h2 MITM（默认 false）、prefer IPv6、server IP、上游协议/主机/端口/用户名/cipher、自定义 bootstrap IPs。上游密码 Keychain tag `com.naine.doer.doh.upstream-password`。
- [ ] `make generate`

**验证**：工程能解析新 SPM 包；旧 `dohEnabled` 行为键仍在。

## 1. DoH 解析对齐 FluxDo（不做 ECH）

- [ ] 去掉 `DohResolver.isAllowedHost`。任意 Host 可解析。
- [ ] JSON / wire 查询都打 bootstrap IP，SNI/Host 仍是 DoH 域名。禁止失败后回落 `URLSession.shared` 走系统 DNS。
- [ ] TTL 60…1800、inflight 去重、缓存上限 1000、粘性 IP 10 分钟、失败 IP 惩罚。
- [ ] 暴露 cache stats / records / `clearCache` / `recordHostSuccess`。
- [ ] `ponytail:` 不查 HTTPS/SVCB。
- [ ] 自定义 URL 无 bootstrap 且 Host 不是 IP → 启动失败，状态行可见。

**验证**：单元测试 bootstrap 请求 URL/Host；allowlist 测试改为“任意 Host 可解析、CF Host 仍可解析”。

## 2. 门面改成单路径

- [ ] `apply(to:)`：DoH 开就挂 CONNECT，不再要求 `linux.do`。
- [ ] iOS 17+：`EncryptedDnsService.disable()`；WKWebView `proxyConfigurations` CONNECT。
- [ ] iOS 15–16：仅 WebView 保留 PrivacyContext Encrypted DNS；URLSession/图片仍走 CONNECT。`ponytail:` 无 MITM。
- [ ] `AvatarImageLoader` / `ExternalImageFetcher` 走同一 CONNECT，禁止再 `clearProxy`。
- [ ] `statusDescription` 显示端口；失败原因保留。

**验证**：关闭 DoH 后字典和 `proxyConfigurations` 被清空。

## 3. 默认 CONNECT MITM

- [ ] `shouldMITM`：CF challenge 除外的任意 Host 为 true。
- [ ] 解析失败 / 上游失败回 502，不系统 DNS 直通。
- [ ] 出口 TLS 连 DoH IP，SNI = 真实 Host。`ponytail:` 无 ECH。
- [ ] 默认 ALPN 锁 `http/1.1`，明文拷贝。
- [ ] 删掉 `SSLCreateContext` / semaphore 忙等。MITM 客户端 TLS 用 NIOSSL server（NIOTS 包现有 CONNECT 流，或代理整体迁 NIOTS）。
- [ ] `MitmCertificateAuthority`：h2 关只签 http/1.1；开则 `h2` + `http/1.1`。

**风险文件**：`LocalConnectProxy.swift`、`MitmTLSBridge.swift`（替换）、`MitmCertificateAuthority.swift`。

**验证**：`LocalConnectProxyTests` 更新 example.com 应为 MITM；CF 仍否。二进制/源码不再出现 `SSLCreateContext`。

## 4. 信任挂钩

- [ ] `FluxDoMitmTrustManager`：DoH 开时默认 evaluator 覆盖任意 Host。
- [ ] `MitmTrust.handle` 接到：`WebLoginViewController`、`WebSessionRefreshService`、`InAppBrowserViewController`（含弹窗 WebView）、CF 验证页、其它自定义 `WKWebView`。
- [ ] 再加一层 `WKWebView` 原生信任挂钩，避免漏接。关闭 DoH 时拆除。

**验证**：挑战页不 MITM；普通 HTTPS 叶证书能被 WebView 接受。

## 5. 上游 HTTP / SOCKS5 / Shadowsocks

- [ ] `UpstreamProxyClient`：HTTP CONNECT + Basic；SOCKS5 greeting/userpass/domain CONNECT。
- [ ] Shadowsocks：`aes-128-gcm`、`aes-256-gcm`、`chacha20-ietf-poly1305`、`2022-blake3-aes-256-gcm`。
- [ ] 上游主机名用 DoH/bootstrap 解析，不用系统 DNS。
- [ ] 无效配置 → 状态失败，不静默直连。
- [ ] 协议测试：handshake 字节、SS 2022 密钥长度 32、Keychain 读写。

**风险文件**：新 `UpstreamProxyClient.swift`；设置里的密码路径。

## 6. h2 MITM

- [ ] 关：不得协商 h2，行为与第 3 步相同。
- [ ] 开：NIOHTTP2 真多路复用；源站按 ALPN 走 h2 或 h1。
- [ ] 开关变化重建代理，无孤儿端口。

**验证**：单测 ALPN 列表随开关变化；能的话用本地 h2 源站打一条 CONNECT。

## 7. 设置页

- [ ] 端口、缓存条数、清空、失败原因。
- [ ] h2 MITM、IPv6 优先、server IP、自定义 bootstrap。
- [ ] 上游卡片 + 测试按钮。
- [ ] iOS 15–16 浏览器限制说明。
- [ ] 中英文案进 `Localizable.xcstrings`。不要 ECH。

## 8. 回归测试

- [ ] 更新 `LocalConnectProxyTests`、`EncryptedDnsServiceTests`（iOS 15–16 兜底语义）。
- [ ] 新增：config 签名、resolver 缓存/去重、upstream handshake、SS 密钥校验、ALPN、CF 不 MITM、关 DoH 清代理。
- [ ] `make generate`
- [ ] 编译（不启动模拟器，除非用户要求）：

```bash
xcodebuild build -workspace Doer.xcworkspace -scheme DoerTests \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

能跑单测再跑 `DoerTests`。设备验收：linux.do API、登录 WebView、应用内浏览器、Turnstile、关 DoH 恢复。

## 回滚点

| 点 | 动作 |
|---|---|
| 第 0 步后依赖编不过 | 撤 SPM，停在现有原型 |
| 第 3 步 MITM 不稳 | `dohEnabled=false` 立即回系统网络；不要回 SecureTransport |
| 第 5–6 步 SS/h2 未完 | 主路径仍可开；对应开关默认关 |

## `task.py start` 前核对

- [x] `prd.md` 验收可测，第一批含默认 MITM + 上游 + h2
- [x] `design.md` 有边界、数据流、偏离、回滚
- [x] 本清单有序且有验证命令
- [ ] 用户看过规划并同意开始实现
