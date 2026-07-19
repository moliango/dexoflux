import Foundation

enum PluginCapability: String, Codable, CaseIterable, Hashable {
    case forumRead = "forum.read"
    case topicRead = "topic.read"
    case topicExport = "topic.export"
    case browserNavigation = "browser.navigation"
    case pluginStorage = "storage.plugin"
    case secureStorage = "storage.secure"
    case restrictedNetwork = "network.restricted"
}

enum PluginContributionKind: String, Codable, CaseIterable, Hashable {
    case meAction = "me.action"
    case topicDetailAction = "topic-detail.action"
    case settingsAction = "settings.action"
    case homeShortcut = "home.shortcut"
    case forumTab = "forum.tab"
    case metaverseService = "metaverse.service"
}

struct PluginContribution: Codable, Hashable, Identifiable {
    let id: String
    let kind: PluginContributionKind
    let titleKey: String
    let titleFallback: String?
    let systemImageName: String
    let order: Int

    init(
        id: String,
        kind: PluginContributionKind,
        titleKey: String,
        titleFallback: String? = nil,
        systemImageName: String,
        order: Int
    ) {
        self.id = id
        self.kind = kind
        self.titleKey = titleKey
        self.titleFallback = titleFallback
        self.systemImageName = systemImageName
        self.order = order
    }
}

struct PluginManifest: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let version: String
    let minimumHostVersion: String
    let publisher: String
    let supportedHosts: [String]
    let capabilities: Set<PluginCapability>
    let contributions: [PluginContribution]
    let defaultEnabled: Bool
    let order: Int

    func supports(_ scope: PluginScope) -> Bool {
        guard !supportedHosts.isEmpty else { return true }
        guard let scopeHost = scope.host else { return false }
        return supportedHosts.contains { supportedHost in
            let normalizedHost = supportedHost
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return scopeHost == normalizedHost || scopeHost.hasSuffix(".\(normalizedHost)")
        }
    }
}

struct PluginScope: Codable, Hashable {
    let baseURL: String
    let username: String
    let storageKey: String

    init(baseURL: String, username: String?) {
        let storageKey = AccountScopeKey.make(baseURL: baseURL, username: username)
        let components = storageKey.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        self.baseURL = components.first.map(String.init) ?? baseURL
        self.username = components.count > 1 ? String(components[1]) : "guest"
        self.storageKey = storageKey
    }

    var host: String? {
        URLComponents(string: baseURL)?.host?.lowercased()
    }
}

struct PluginContributionRegistration: Hashable, Identifiable {
    let plugin: PluginManifest
    let contribution: PluginContribution

    var id: String {
        "\(plugin.id):\(contribution.id)"
    }
}

enum BuiltInPluginID {
    static let ldc = "builtin.ldc"
    static let cdk = "builtin.cdk"
    static let topicExport = "builtin.topic-export"
    static let newAPICheckIn = "builtin.newapi-check-in"
    static let ldcStore = "builtin.ldc-store"
}
