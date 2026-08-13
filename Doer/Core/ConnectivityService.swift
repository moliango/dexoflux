import Foundation
import Network
import UIKit

/// App-wide network connectivity, aligned with FluxDo `ConnectivityService`:
/// - Listen for device path changes (Wi‑Fi / cellular up/down)
/// - Debounce transient disconnects (500ms) to avoid false offline flashes
/// - While offline, exponential backoff re-check (1s → 2s → … → 30s)
/// - Optional `/srv/status` ping (off by default, same as FluxDo)
/// - Notify subscribers on connect/disconnect so UI can recover
@MainActor
final class ConnectivityService {
    static let shared = ConnectivityService()

    static let didChangeNotification = Notification.Name("DoerConnectivityDidChange")
    nonisolated static let isConnectedUserInfoKey = "isConnected"

    /// When true, also require `GET {baseURL}/srv/status` → 200 + body `ok`.
    /// FluxDo keeps this false by default (local path only).
    static var enableServerPing = false

    /// Optional base URL used only when `enableServerPing` is true.
    var pingBaseURL: String?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "doer.connectivity.monitor")
    private var isMonitoring = false

    private var disconnectDebounceWorkItem: DispatchWorkItem?
    private var retryWorkItem: DispatchWorkItem?
    private var retryInFlight = false
    private var retryBackoffSeconds = 1
    private let maxRetryBackoffSeconds = 30

    private(set) var isConnected = true
    private var lastPathStatus: NWPath.Status?

    private init() {}

    // MARK: - Public

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: monitorQueue)

        // Initial snapshot (path may already be available).
        handlePathUpdate(monitor.currentPath)
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitor.cancel()
        cancelDisconnectDebounce()
        stopRetry()
    }

    /// Manual check — call on foreground resume (FluxDo `ConnectivityService.check()`).
    func check() {
        Task { @MainActor in
            if Self.enableServerPing {
                let reachable = await pingServerIfConfigured()
                setConnected(reachable)
            } else {
                let path = monitor.currentPath
                setConnected(path.status == .satisfied)
            }
        }
    }

    // MARK: - Path handling

    private func handlePathUpdate(_ path: NWPath) {
        let status = path.status
        lastPathStatus = status
        let hasNetwork = status == .satisfied

        if !hasNetwork {
            // Path monitor can emit a brief unsatisfied blip on launch/resume.
            // Debounce 500ms like FluxDo connectivity_plus handling.
            scheduleDisconnectDebounce()
            return
        }

        cancelDisconnectDebounce()

        if Self.enableServerPing {
            Task { @MainActor in
                let reachable = await pingServerIfConfigured()
                setConnected(reachable)
            }
        } else {
            setConnected(true)
        }
    }

    private func scheduleDisconnectDebounce() {
        cancelDisconnectDebounce()
        let work = DispatchWorkItem { [weak self] in
            self?.setConnected(false)
        }
        disconnectDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func cancelDisconnectDebounce() {
        disconnectDebounceWorkItem?.cancel()
        disconnectDebounceWorkItem = nil
    }

    private func setConnected(_ connected: Bool) {
        if connected {
            cancelDisconnectDebounce()
        }
        guard isConnected != connected else {
            if connected { stopRetry() }
            return
        }
        isConnected = connected
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: [Self.isConnectedUserInfoKey: connected]
        )

        if connected {
            stopRetry()
        } else {
            startRetry()
        }
    }

    // MARK: - Offline retry (exponential backoff)

    private func startRetry() {
        stopRetry()
        retryBackoffSeconds = 1
        scheduleNextRetry()
    }

    private func scheduleNextRetry() {
        let delay = TimeInterval(retryBackoffSeconds)
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                await self?.runRetryTick()
            }
        }
        retryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func runRetryTick() async {
        guard !isConnected else { return }
        guard !retryInFlight else { return }
        retryInFlight = true
        defer { retryInFlight = false }

        let path = monitor.currentPath
        let hasNetwork = path.status == .satisfied
        if hasNetwork {
            if Self.enableServerPing {
                if await pingServerIfConfigured() {
                    setConnected(true)
                }
            } else {
                setConnected(true)
            }
        }

        if !isConnected {
            retryBackoffSeconds = min(retryBackoffSeconds * 2, maxRetryBackoffSeconds)
            scheduleNextRetry()
        }
    }

    private func stopRetry() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryInFlight = false
        retryBackoffSeconds = 1
    }

    // MARK: - Optional server ping

    /// Discourse-style: `GET /srv/status` returns 200 and body `ok`.
    private func pingServerIfConfigured() async -> Bool {
        guard let raw = pingBaseURL?.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
              !raw.isEmpty,
              let url = URL(string: raw + "/srv/status")
        else {
            // No base URL — fall back to path-only success.
            return monitor.currentPath.status == .satisfied
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return body == "ok"
        } catch {
            return false
        }
    }
}
