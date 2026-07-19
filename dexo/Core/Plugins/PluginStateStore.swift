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
}
