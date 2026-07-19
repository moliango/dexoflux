import XCTest
@testable import dexoflux

@MainActor
final class DexoPluginRuntimeTests: XCTestCase {
    func testBuiltInPluginsExposeStableIdentifiersAndAreEnabledByDefault() async throws {
        let defaults = makeDefaults()
        let store = PluginStateStore(defaults: defaults)
        let registry = try PluginRegistry(plugins: BuiltInPlugins.all, stateStore: store)
        let scope = PluginScope(baseURL: "HTTPS://LINUX.DO/", username: "Sam")

        XCTAssertEqual(registry.allPlugins.map(\.id), [
            BuiltInPluginID.ldc,
            BuiltInPluginID.cdk,
            BuiltInPluginID.topicExport,
            BuiltInPluginID.newAPICheckIn,
            BuiltInPluginID.ldcStore,
        ])
        XCTAssertTrue(registry.allPlugins.allSatisfy(\.defaultEnabled))
        XCTAssertEqual(registry.enabledPlugins(for: scope).map(\.id), registry.allPlugins.map(\.id))
        XCTAssertTrue(registry.allPlugins.allSatisfy { !$0.capabilities.isEmpty })
        XCTAssertTrue(registry.allPlugins.allSatisfy { !$0.contributions.isEmpty })
    }

    func testRegistryRejectsDuplicatePluginIdentifiers() async throws {
        let defaults = makeDefaults()
        let store = PluginStateStore(defaults: defaults)
        let duplicate = PluginManifest(
            id: "duplicate.plugin",
            displayName: "Duplicate",
            version: "1.0.0",
            minimumHostVersion: "1.2",
            publisher: "DexoFlux",
            supportedHosts: [],
            capabilities: [.forumRead],
            contributions: [],
            defaultEnabled: true,
            order: 0
        )

        XCTAssertThrowsError(try PluginRegistry(plugins: [duplicate, duplicate], stateStore: store)) { error in
            XCTAssertEqual(error as? PluginRegistryError, .duplicatePluginID("duplicate.plugin"))
        }
    }

    func testRegistryUsesDeterministicPluginAndContributionOrdering() async throws {
        let defaults = makeDefaults()
        let store = PluginStateStore(defaults: defaults)
        let alpha = makeManifest(
            id: "plugin.alpha",
            order: 10,
            contributions: [
                PluginContribution(id: "z-last", kind: .meAction, titleKey: "Z", systemImageName: "z.circle", order: 20),
                PluginContribution(id: "a-first", kind: .meAction, titleKey: "A", systemImageName: "a.circle", order: 10),
            ]
        )
        let beta = makeManifest(
            id: "plugin.beta",
            order: 10,
            contributions: [
                PluginContribution(id: "b", kind: .meAction, titleKey: "B", systemImageName: "b.circle", order: 10),
            ]
        )
        let early = makeManifest(id: "plugin.early", order: 1)
        let registry = try PluginRegistry(plugins: [beta, alpha, early], stateStore: store)
        let scope = PluginScope(baseURL: "https://linux.do", username: "sam")

        XCTAssertEqual(registry.allPlugins.map(\.id), ["plugin.early", "plugin.alpha", "plugin.beta"])
        XCTAssertEqual(
            registry.contributions(of: .meAction, for: scope).map { "\($0.plugin.id)/\($0.contribution.id)" },
            ["plugin.alpha/a-first", "plugin.beta/b", "plugin.alpha/z-last"]
        )
    }

    func testEnabledStateIsNormalizedAndIsolatedByForumAndAccount() async throws {
        let defaults = makeDefaults()
        let store = PluginStateStore(defaults: defaults)
        let registry = try PluginRegistry(plugins: BuiltInPlugins.all, stateStore: store)
        let sam = PluginScope(baseURL: "HTTPS://LINUX.DO/", username: "Sam")
        let sameSam = PluginScope(baseURL: "https://linux.do", username: "sam")
        let alex = PluginScope(baseURL: "https://linux.do", username: "alex")
        let anotherForum = PluginScope(baseURL: "https://meta.discourse.org", username: "sam")

        registry.setPlugin(BuiltInPluginID.ldc, enabled: false, for: sam)

        XCTAssertFalse(registry.isPluginEnabled(BuiltInPluginID.ldc, for: sameSam))
        XCTAssertTrue(registry.isPluginEnabled(BuiltInPluginID.ldc, for: alex))
        XCTAssertTrue(store.isPluginEnabled(BuiltInPluginID.ldc, defaultValue: true, for: anotherForum))

        let reloadedStore = PluginStateStore(defaults: defaults)
        let reloadedRegistry = try PluginRegistry(plugins: BuiltInPlugins.all, stateStore: reloadedStore)
        XCTAssertFalse(reloadedRegistry.isPluginEnabled(BuiltInPluginID.ldc, for: sameSam))
    }

    func testSafeModeImmediatelySuppressesAllContributionsWithoutLosingPreferences() async throws {
        let defaults = makeDefaults()
        let store = PluginStateStore(defaults: defaults)
        let registry = try PluginRegistry(plugins: BuiltInPlugins.all, stateStore: store)
        let scope = PluginScope(baseURL: "https://linux.do", username: "sam")

        XCTAssertFalse(registry.contributions(of: .topicDetailAction, for: scope).isEmpty)

        registry.setSafeModeEnabled(true)

        XCTAssertTrue(registry.enabledPlugins(for: scope).isEmpty)
        XCTAssertTrue(registry.contributions(of: .topicDetailAction, for: scope).isEmpty)
        XCTAssertTrue(store.isPluginEnabled(BuiltInPluginID.topicExport, defaultValue: true, for: scope))

        registry.setSafeModeEnabled(false)

        XCTAssertFalse(registry.contributions(of: .topicDetailAction, for: scope).isEmpty)
    }

    func testStateChangesPostStatusNotificationOnlyWhenValueChanges() async throws {
        let defaults = makeDefaults()
        let center = NotificationCenter()
        let store = PluginStateStore(defaults: defaults, notificationCenter: center)
        let scope = PluginScope(baseURL: "https://linux.do", username: "sam")
        var notifications: [Notification] = []
        let token = center.addObserver(
            forName: PluginStateStore.stateDidChangeNotification,
            object: store,
            queue: nil
        ) { notification in
            notifications.append(notification)
        }
        defer { center.removeObserver(token) }

        store.setPlugin(BuiltInPluginID.ldc, enabled: false, defaultValue: true, for: scope)
        store.setPlugin(BuiltInPluginID.ldc, enabled: false, defaultValue: true, for: scope)
        store.setSafeModeEnabled(true)
        store.setSafeModeEnabled(true)

        XCTAssertEqual(notifications.count, 2)
        XCTAssertEqual(notifications[0].userInfo?[PluginStateStore.pluginIDUserInfoKey] as? String, BuiltInPluginID.ldc)
        XCTAssertEqual(notifications[0].userInfo?[PluginStateStore.scopeUserInfoKey] as? String, scope.storageKey)
        XCTAssertEqual(notifications[1].userInfo?[PluginStateStore.safeModeUserInfoKey] as? Bool, true)
    }

    func testUnsupportedHostOnlyExposesHostIndependentPlugins() async throws {
        let defaults = makeDefaults()
        let registry = try PluginRegistry(
            plugins: BuiltInPlugins.all,
            stateStore: PluginStateStore(defaults: defaults)
        )
        let scope = PluginScope(baseURL: "https://meta.discourse.org", username: "sam")

        XCTAssertEqual(registry.enabledPlugins(for: scope).map(\.id), [
            BuiltInPluginID.topicExport,
            BuiltInPluginID.newAPICheckIn,
        ])
        XCTAssertTrue(registry.contributions(of: .metaverseService, for: scope).isEmpty)
        XCTAssertEqual(
            registry.contributions(of: .topicDetailAction, for: scope).map(\.plugin.id),
            [BuiltInPluginID.topicExport]
        )
    }

    private func makeManifest(
        id: String,
        order: Int,
        contributions: [PluginContribution] = []
    ) -> PluginManifest {
        PluginManifest(
            id: id,
            displayName: id,
            version: "1.0.0",
            minimumHostVersion: "1.2",
            publisher: "Tests",
            supportedHosts: ["linux.do"],
            capabilities: [.forumRead],
            contributions: contributions,
            defaultEnabled: true,
            order: order
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "DexoPluginRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
