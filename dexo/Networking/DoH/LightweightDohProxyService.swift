import Foundation

final class LightweightDohProxyService {
    static let shared = LightweightDohProxyService()

    private let lock = NSLock()
    private let resolver = DohResolver()
    private var proxy: LocalConnectProxy?
    private(set) var lastError: Error?
    private(set) var configurationVersion: Int = 0
    private var lastSignature = ""

    private init() {}

    var currentSignature: String {
        let settings = AppSettings.shared
        return [
            settings.dohEnabled ? "on" : "off",
            "\(settings.dohProvider.rawValue)",
            settings.dohServerURL,
        ].joined(separator: "|")
    }

    var sessionConfigurationSignature: String {
        "\(currentSignature)|\(configurationVersion)"
    }

    var statusDescription: String {
        guard AppSettings.shared.dohEnabled else {
            return "未启用"
        }

        lock.lock()
        let activePort = proxy?.proxyPort
        let activeError = lastError
        lock.unlock()

        if let activePort {
            return "运行中 127.0.0.1:\(activePort) · \(SwiftDnsResolverBackend.engineName)"
        }
        if let activeError {
            return "启动失败：\(activeError.localizedDescription)"
        }
        return "未启动 · \(SwiftDnsResolverBackend.engineName)"
    }

    func configureFromSettings() {
        lock.lock()
        let signature = currentSignature
        if signature == lastSignature, proxy?.isRunning == AppSettings.shared.dohEnabled {
            lock.unlock()
            return
        }
        lastSignature = signature
        configurationVersion += 1
        let shouldEnable = AppSettings.shared.dohEnabled
        lock.unlock()

        if shouldEnable {
            _ = ensureRunning()
        } else {
            stop()
        }
    }

    func ensureRunning() -> UInt16? {
        guard AppSettings.shared.dohEnabled else {
            stop()
            return nil
        }

        lock.lock()
        if let proxy, proxy.isRunning {
            let port = proxy.proxyPort
            lock.unlock()
            return port
        }
        let newProxy = LocalConnectProxy(resolver: resolver)
        do {
            try newProxy.start()
            proxy = newProxy
            lastError = nil
            configurationVersion += 1
            let port = newProxy.proxyPort
            lock.unlock()
            return port
        } catch {
            lastError = error
            proxy = nil
            configurationVersion += 1
            lock.unlock()
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
    }

    func clearCache() {
        resolver.clearCache()
    }

    func connectionProxyDictionary(for baseURL: String) -> [AnyHashable: Any]? {
        guard shouldProxy(baseURL: baseURL) else { return nil }
        guard let port = ensureRunning() else { return nil }
        // URLSession uses these proxy keys to open HTTPS requests through HTTP CONNECT.
        // The HTTPS CFNetwork constants are unavailable on iOS, so keep the raw keys.
        let proxy: [AnyHashable: Any] = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: Int(port),
            "HTTPSEnable": true,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": Int(port),
        ]
        DohDebugLog.record("Using local CONNECT proxy for \(baseURL) on 127.0.0.1:\(port)")
        return proxy
    }

    private func shouldProxy(baseURL: String) -> Bool {
        guard AppSettings.shared.dohEnabled,
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
