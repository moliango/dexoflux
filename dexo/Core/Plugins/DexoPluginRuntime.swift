import Foundation

final class DexoPluginRuntime {
    static let shared = DexoPluginRuntime()

    let stateStore: PluginStateStore
    let registry: PluginRegistry

    init(
        plugins: [PluginManifest] = BuiltInPlugins.all,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        let stateStore = PluginStateStore(defaults: defaults, notificationCenter: notificationCenter)
        self.stateStore = stateStore

        do {
            registry = try PluginRegistry(plugins: plugins, stateStore: stateStore)
        } catch {
            registry = PluginRegistry.empty(stateStore: stateStore)
        }
    }
}
