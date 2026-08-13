import Foundation

final class PluginStateStore {
    static let stateDidChangeNotification = Notification.Name("DexoPluginStateDidChange")
    static let pluginIDUserInfoKey = "pluginID"
    static let scopeUserInfoKey = "scope"
    static let enabledUserInfoKey = "enabled"
    static let safeModeUserInfoKey = "safeMode"

    private static let safeModeDefaultsKey = "dexo.plugins.safe-mode.v1"
    private static let enabledDefaultsPrefix = "dexo.plugins.enabled.v1"

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
    }

    var isSafeModeEnabled: Bool {
        defaults.bool(forKey: Self.safeModeDefaultsKey)
    }

    func setSafeModeEnabled(_ enabled: Bool) {
        guard isSafeModeEnabled != enabled else { return }
        defaults.set(enabled, forKey: Self.safeModeDefaultsKey)
        notificationCenter.post(
            name: Self.stateDidChangeNotification,
            object: self,
            userInfo: [Self.safeModeUserInfoKey: enabled]
        )
    }

    func isPluginEnabled(
        _ pluginID: String,
        defaultValue: Bool,
        for scope: PluginScope
    ) -> Bool {
        let key = enabledDefaultsKey(pluginID: pluginID, scope: scope)
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    func setPlugin(
        _ pluginID: String,
        enabled: Bool,
        defaultValue: Bool,
        for scope: PluginScope
    ) {
        guard isPluginEnabled(pluginID, defaultValue: defaultValue, for: scope) != enabled else { return }
        defaults.set(enabled, forKey: enabledDefaultsKey(pluginID: pluginID, scope: scope))
        notificationCenter.post(
            name: Self.stateDidChangeNotification,
            object: self,
            userInfo: [
                Self.pluginIDUserInfoKey: pluginID,
                Self.scopeUserInfoKey: scope.storageKey,
                Self.enabledUserInfoKey: enabled,
            ]
        )
    }

    func resetPlugin(_ pluginID: String, defaultValue: Bool, for scope: PluginScope) {
        let key = enabledDefaultsKey(pluginID: pluginID, scope: scope)
        guard defaults.object(forKey: key) != nil else { return }
        defaults.removeObject(forKey: key)
        notificationCenter.post(
            name: Self.stateDidChangeNotification,
            object: self,
            userInfo: [
                Self.pluginIDUserInfoKey: pluginID,
                Self.scopeUserInfoKey: scope.storageKey,
                Self.enabledUserInfoKey: defaultValue,
            ]
        )
    }

    private func enabledDefaultsKey(pluginID: String, scope: PluginScope) -> String {
        "\(Self.enabledDefaultsPrefix).\(scope.storageKey).\(pluginID)"
    }

    func makeExportPayload() -> PluginStateExportPayload {
        var enabled: [String: Bool] = [:]
        let prefix = Self.enabledDefaultsPrefix + "."
        for (key, value) in defaults.dictionaryRepresentation() {
            guard key.hasPrefix(prefix), let flag = value as? Bool else { continue }
            enabled[String(key.dropFirst(prefix.count))] = flag
        }
        return PluginStateExportPayload(safeModeEnabled: isSafeModeEnabled, enabledByKey: enabled)
    }

    func importExportPayload(_ payload: PluginStateExportPayload) {
        setSafeModeEnabled(payload.safeModeEnabled)
        let prefix = Self.enabledDefaultsPrefix + "."
        for (key, _) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
        for (suffix, enabled) in payload.enabledByKey {
            defaults.set(enabled, forKey: prefix + suffix)
        }
        notificationCenter.post(name: Self.stateDidChangeNotification, object: self)
    }
}

struct PluginStateExportPayload: Codable, Equatable {
    var safeModeEnabled: Bool
    /// Keys are `"\(scope.storageKey).\(pluginID)"`.
    var enabledByKey: [String: Bool]
}
