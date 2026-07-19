import Foundation

enum PluginRegistryError: Error, Equatable {
    case duplicatePluginID(String)
    case duplicateContributionID(pluginID: String, contributionID: String)
}

final class PluginRegistry {
    let allPlugins: [PluginManifest]

    private let stateStore: PluginStateStore

    init(plugins: [PluginManifest], stateStore: PluginStateStore) throws {
        var pluginIDs = Set<String>()
        for plugin in plugins {
            guard pluginIDs.insert(plugin.id).inserted else {
                throw PluginRegistryError.duplicatePluginID(plugin.id)
            }

            var contributionIDs = Set<String>()
            for contribution in plugin.contributions {
                guard contributionIDs.insert(contribution.id).inserted else {
                    throw PluginRegistryError.duplicateContributionID(
                        pluginID: plugin.id,
                        contributionID: contribution.id
                    )
                }
            }
        }

        self.allPlugins = plugins.sorted(by: Self.sortPlugins)
        self.stateStore = stateStore
    }

    private init(stateStore: PluginStateStore) {
        allPlugins = []
        self.stateStore = stateStore
    }

    static func empty(stateStore: PluginStateStore) -> PluginRegistry {
        PluginRegistry(stateStore: stateStore)
    }

    func manifest(id: String) -> PluginManifest? {
        allPlugins.first { $0.id == id }
    }

    func enabledPlugins(for scope: PluginScope) -> [PluginManifest] {
        guard !stateStore.isSafeModeEnabled else { return [] }
        return allPlugins.filter { plugin in
            plugin.supports(scope)
                && stateStore.isPluginEnabled(plugin.id, defaultValue: plugin.defaultEnabled, for: scope)
        }
    }

    func isPluginEnabled(_ pluginID: String, for scope: PluginScope) -> Bool {
        guard !stateStore.isSafeModeEnabled,
              let plugin = manifest(id: pluginID),
              plugin.supports(scope)
        else { return false }
        return stateStore.isPluginEnabled(plugin.id, defaultValue: plugin.defaultEnabled, for: scope)
    }

    func setPlugin(_ pluginID: String, enabled: Bool, for scope: PluginScope) {
        guard let plugin = manifest(id: pluginID) else { return }
        stateStore.setPlugin(pluginID, enabled: enabled, defaultValue: plugin.defaultEnabled, for: scope)
    }

    var isSafeModeEnabled: Bool {
        stateStore.isSafeModeEnabled
    }

    func setSafeModeEnabled(_ enabled: Bool) {
        stateStore.setSafeModeEnabled(enabled)
    }

    func contributions(
        of kind: PluginContributionKind,
        for scope: PluginScope
    ) -> [PluginContributionRegistration] {
        enabledPlugins(for: scope)
            .flatMap { plugin in
                plugin.contributions
                    .filter { $0.kind == kind }
                    .map { PluginContributionRegistration(plugin: plugin, contribution: $0) }
            }
            .sorted(by: Self.sortContributions)
    }

    func contribution(
        pluginID: String,
        contributionID: String,
        for scope: PluginScope
    ) -> PluginContributionRegistration? {
        guard isPluginEnabled(pluginID, for: scope),
              let plugin = manifest(id: pluginID),
              let contribution = plugin.contributions.first(where: { $0.id == contributionID })
        else { return nil }
        return PluginContributionRegistration(plugin: plugin, contribution: contribution)
    }

    nonisolated private static func sortPlugins(_ lhs: PluginManifest, _ rhs: PluginManifest) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.id < rhs.id
    }

    nonisolated private static func sortContributions(
        _ lhs: PluginContributionRegistration,
        _ rhs: PluginContributionRegistration
    ) -> Bool {
        if lhs.contribution.order != rhs.contribution.order {
            return lhs.contribution.order < rhs.contribution.order
        }
        if lhs.plugin.id != rhs.plugin.id {
            return lhs.plugin.id < rhs.plugin.id
        }
        return lhs.contribution.id < rhs.contribution.id
    }
}
