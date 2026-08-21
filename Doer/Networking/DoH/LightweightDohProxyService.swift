import Foundation
import Network
import SDWebImage
import WebKit

nonisolated final class LightweightDohProxyService: @unchecked Sendable {
    static let shared = LightweightDohProxyService()

    private static let startQueueKey = DispatchSpecificKey<UInt8>()
    private let lock = NSLock()
    private let resolver = DohResolver()
    private let startQueue: DispatchQueue
    private var proxy: LocalConnectProxy?
    private(set) var lastError: Error?
    private(set) var configurationVersion: Int = 0
    private var lastSignature = ""


    private init() {
        let queue = DispatchQueue(label: "doer.doh.proxy-start")
        queue.setSpecific(key: Self.startQueueKey, value: 1)
        self.startQueue = queue
    }

    var currentSignature: String {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "dohEnabled")
        let provider = defaults.object(forKey: "dohProvider") as? Int ?? AppSettings.DoHProvider.alidns.rawValue
        let url = DohProviderConfiguration.currentFromDefaults().url
        return [
            enabled ? "on" : "off",
            "\(provider)",
            url,
        ].joined(separator: "|")
    }

    var sessionConfigurationSignature: String {
        "\(currentSignature)|\(configurationVersion)"
    }

    var statusDescription: String {
        guard UserDefaults.standard.bool(forKey: "dohEnabled") else {
            return "未启用"
        }

        lock.lock()
        let activePort = proxy?.proxyPort
        let activeError = lastError
        lock.unlock()

        if let activePort {
            if #available(iOS 17.0, *) {
                return "运行中 127.0.0.1:\(activePort) · 主站+浏览器"
            }
            return "运行中 127.0.0.1:\(activePort) · 主站（浏览器需 iOS 17）"
        }
        if let activeError {
            return "启动失败：\(activeError.localizedDescription)"
        }
        return "未启动 · \(SwiftDnsResolverBackend.engineName)"
    }

    func configureFromSettings() {
        lock.lock()
        let signature = currentSignature
        let enabled = UserDefaults.standard.bool(forKey: "dohEnabled")
        if signature == lastSignature, proxy?.isRunning == enabled {
            lock.unlock()
            return
        }
        lastSignature = signature
        configurationVersion += 1
        let shouldEnable = enabled
        lock.unlock()

        if shouldEnable {
            // Never wait on the main actor: NWListener callbacks would hop back
            // and deadlock a semaphore.wait in start().
            startQueue.async { [weak self] in
                _ = self?.ensureRunning()
                self?.publishAppClients()
            }
        } else {
            stop()
            publishAppClients()
        }
    }

    func ensureRunning() -> UInt16? {
        if DispatchQueue.getSpecific(key: Self.startQueueKey) != nil {
            return startProxyNow()
        }
        lock.lock()
        let port = proxy?.proxyPort
        lock.unlock()
        if port != nil {
            return port
        }
        // Never `startQueue.sync` from the main thread: listener callbacks and
        // SDWebImage session mutation can hop back to MainActor and watchdog-kill launch.
        startQueue.async { [weak self] in
            _ = self?.startProxyNow()
        }
        return port
    }

    private func startProxyNow() -> UInt16? {
        guard UserDefaults.standard.bool(forKey: "dohEnabled") else {
            stop()
            return nil
        }

        lock.lock()
        if let proxy {
            let port = proxy.proxyPort
            lock.unlock()
            return port
        }
        let newProxy = LocalConnectProxy(resolver: resolver)
        newProxy.onTLSHandshakeReset = { host in
            DohDebugLog.record("DoH TLS handshake reset for \(host); staying on DoH IPs")
        }
        newProxy.onListening = { [weak self] port in
            guard let self else { return }
            self.lock.lock()
            self.lastError = nil
            self.configurationVersion += 1
            self.lock.unlock()
            DohDebugLog.record("DoH proxy started on 127.0.0.1:\(port)")
            self.publishAppClients()
        }
        newProxy.onFailed = { [weak self, weak newProxy] error in
            guard let self else { return }
            self.lock.lock()
            if let newProxy, self.proxy === newProxy {
                self.proxy = nil
                self.lastError = error
                self.configurationVersion += 1
            }
            self.lock.unlock()
            DohDebugLog.record("DoH proxy start failed: \(error.localizedDescription)")
            self.publishAppClients()
        }
        proxy = newProxy
        lock.unlock()
        do {
            try newProxy.start()
            return newProxy.proxyPort
        } catch {
            lock.lock()
            if proxy === newProxy {
                proxy = nil
                lastError = error
                configurationVersion += 1
            }
            lock.unlock()
            DohDebugLog.record("DoH proxy start failed: \(error.localizedDescription)")
            publishAppClients()
            return nil
        }
    }

    func stop() {
        lock.lock()
        let oldProxy = proxy
        proxy = nil
        lastError = nil
        configurationVersion += 1
        lock.unlock()

        oldProxy?.stop()
        publishAppClients()
    }

    func clearCache() {
        resolver.clearCache()
    }

    func connectionProxyDictionary(for baseURL: String) -> [AnyHashable: Any]? {
        let config = URLSessionConfiguration.ephemeral
        apply(to: config, hostURL: baseURL)
        return config.connectionProxyDictionary
    }

    /// Attach the loopback CONNECT proxy. Pass `hostURL` to limit it to linux.do
    /// API sessions; omit it for shared clients (images / WKWebView) that rely
    /// on CONNECT passthrough for other hosts.
    func apply(to sessionConfiguration: URLSessionConfiguration, hostURL: String? = nil) {
        let shouldAttach: Bool
        if let hostURL {
            shouldAttach = shouldProxy(baseURL: hostURL)
        } else {
            shouldAttach = UserDefaults.standard.bool(forKey: "dohEnabled")
        }
        guard shouldAttach, let port = ensureRunning() else {
            clearProxy(on: sessionConfiguration)
            return
        }
        attach(port: port, to: sessionConfiguration)
        DohDebugLog.record(
            "Using local SOCKS5 proxy\(hostURL.map { " for \($0)" } ?? "") on 127.0.0.1:\(port)"
        )
    }

    private func publishAppClients() {
        let work = { [weak self] in
            self?.applyWebViewProxy()
            self?.applyImageDownloaderProxy()
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func applyWebViewProxy() {
        guard #available(iOS 17.0, *) else { return }
        let enabled = UserDefaults.standard.bool(forKey: "dohEnabled")
        lock.lock()
        let port = (enabled && proxy?.isRunning == true) ? proxy?.proxyPort : nil
        lock.unlock()
        let apply = {
            if let port, let proxy = Self.socksProxyConfiguration(port: port) {
                WKWebsiteDataStore.default().proxyConfigurations = [proxy]
                DohDebugLog.record("WKWebView default store using SOCKS5 proxy 127.0.0.1:\(port)")
            } else {
                WKWebsiteDataStore.default().proxyConfigurations = []
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    private func applyImageDownloaderProxy() {
        let config = SDWebImageDownloader.shared.config.sessionConfiguration
            ?? URLSessionConfiguration.default
        attachCurrentProxy(to: config)
        SDWebImageDownloader.shared.config.sessionConfiguration = config
    }

    private func attachCurrentProxy(to sessionConfiguration: URLSessionConfiguration) {
        lock.lock()
        let port = (UserDefaults.standard.bool(forKey: "dohEnabled") && proxy?.isRunning == true)
            ? proxy?.proxyPort
            : nil
        lock.unlock()
        guard let port else {
            clearProxy(on: sessionConfiguration)
            return
        }
        attach(port: port, to: sessionConfiguration)
    }

    private func attach(port: UInt16, to sessionConfiguration: URLSessionConfiguration) {
        sessionConfiguration.connectionProxyDictionary = Self.proxyDictionary(port: port)
        if #available(iOS 17.0, *) {
            if let proxy = Self.socksProxyConfiguration(port: port) {
                sessionConfiguration.proxyConfigurations = [proxy]
            }
        }
    }

    private func clearProxy(on sessionConfiguration: URLSessionConfiguration) {
        sessionConfiguration.connectionProxyDictionary = nil
        if #available(iOS 17.0, *) {
            sessionConfiguration.proxyConfigurations = []
        }
    }

    /// System Configuration SOCKS keys only. Mixing `kCFStreamPropertySOCKS*`
    /// into `connectionProxyDictionary` can abort CFNetwork at session create.
    static func proxyDictionary(port: UInt16) -> [AnyHashable: Any] {
        [
            "SOCKSEnable": NSNumber(value: 1),
            "SOCKSProxy": "127.0.0.1",
            "SOCKSPort": NSNumber(value: Int(port)),
            "ExceptionsList": ["127.0.0.1", "localhost", "::1"],
        ]
    }

    @available(iOS 17.0, *)
    private static func socksProxyConfiguration(port: UInt16) -> ProxyConfiguration? {
        guard let ipv4 = IPv4Address("127.0.0.1"),
              let nwPort = NWEndpoint.Port(rawValue: port)
        else {
            return nil
        }
        let endpoint = NWEndpoint.hostPort(host: .ipv4(ipv4), port: nwPort)
        return ProxyConfiguration(socksv5Proxy: endpoint)
    }

    private func shouldProxy(baseURL: String) -> Bool {
        guard UserDefaults.standard.bool(forKey: "dohEnabled"),
              let host = Self.host(from: baseURL)
        else {
            return false
        }
        return DohResolver.isAllowedHost(host)
    }

    private static func host(from baseURL: String) -> String? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: trimmed)?.host {
            return host
        }
        return URL(string: "https://\(trimmed)")?.host
    }
}
