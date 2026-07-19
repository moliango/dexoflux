import Foundation

enum BuiltInPlugins {
    static let all: [PluginManifest] = [ldc, cdk, topicExport, newAPICheckIn, ldcStore]

    static let ldc = PluginManifest(
        id: BuiltInPluginID.ldc,
        displayName: "LDC",
        version: "1.0.0",
        minimumHostVersion: "1.2",
        publisher: "DexoFlux",
        supportedHosts: ["linux.do"],
        capabilities: [
            .forumRead,
            .topicRead,
            .browserNavigation,
            .pluginStorage,
            .secureStorage,
            .restrictedNetwork,
        ],
        contributions: [
            PluginContribution(
                id: "metaverse-service",
                kind: .metaverseService,
                titleKey: "extensions.services",
                titleFallback: "LDC",
                systemImageName: "l.circle.fill",
                order: 100
            ),
            PluginContribution(
                id: "me-action",
                kind: .meAction,
                titleKey: "extensions.services",
                titleFallback: "LDC",
                systemImageName: "l.circle.fill",
                order: 100
            ),
            PluginContribution(
                id: "settings",
                kind: .settingsAction,
                titleKey: "extensions.services",
                titleFallback: "LDC",
                systemImageName: "gearshape",
                order: 100
            ),
        ],
        defaultEnabled: true,
        order: 100
    )

    static let cdk = PluginManifest(
        id: BuiltInPluginID.cdk,
        displayName: "CDK",
        version: "1.0.0",
        minimumHostVersion: "1.2",
        publisher: "DexoFlux",
        supportedHosts: ["linux.do"],
        capabilities: [
            .forumRead,
            .topicRead,
            .browserNavigation,
            .pluginStorage,
            .secureStorage,
            .restrictedNetwork,
        ],
        contributions: [
            PluginContribution(
                id: "metaverse-service",
                kind: .metaverseService,
                titleKey: "extensions.services",
                titleFallback: "CDK",
                systemImageName: "c.circle.fill",
                order: 110
            ),
            PluginContribution(
                id: "me-action",
                kind: .meAction,
                titleKey: "extensions.services",
                titleFallback: "CDK",
                systemImageName: "c.circle.fill",
                order: 110
            ),
            PluginContribution(
                id: "settings",
                kind: .settingsAction,
                titleKey: "extensions.services",
                titleFallback: "CDK",
                systemImageName: "gearshape",
                order: 110
            ),
        ],
        defaultEnabled: true,
        order: 110
    )

    static let topicExport = PluginManifest(
        id: BuiltInPluginID.topicExport,
        displayName: "Topic Export",
        version: "1.0.0",
        minimumHostVersion: "1.2",
        publisher: "DexoFlux",
        supportedHosts: [],
        capabilities: [
            .forumRead,
            .topicRead,
            .topicExport,
            .pluginStorage,
        ],
        contributions: [
            PluginContribution(
                id: "topic-export",
                kind: .topicDetailAction,
                titleKey: "topic.export",
                titleFallback: "导出话题",
                systemImageName: "square.and.arrow.up",
                order: 200
            ),
            PluginContribution(
                id: "export-history",
                kind: .meAction,
                titleKey: "topic.export.history",
                titleFallback: "导出历史",
                systemImageName: "clock.arrow.circlepath",
                order: 200
            ),
            PluginContribution(
                id: "settings",
                kind: .settingsAction,
                titleKey: "topic.export.history",
                titleFallback: "导出历史",
                systemImageName: "gearshape",
                order: 200
            ),
        ],
        defaultEnabled: true,
        order: 200
    )

    static let newAPICheckIn = PluginManifest(
        id: BuiltInPluginID.newAPICheckIn,
        displayName: "NewAPI 签到",
        version: "0.1.0",
        minimumHostVersion: "1.2",
        publisher: "DexoFlux",
        supportedHosts: [],
        capabilities: [.restrictedNetwork, .pluginStorage, .secureStorage],
        contributions: [
            PluginContribution(
                id: "main-tab",
                kind: .forumTab,
                titleKey: "plugins.newapi.title",
                titleFallback: "NewAPI 签到",
                systemImageName: "checkmark.circle.fill",
                order: 300
            ),
            PluginContribution(
                id: "settings",
                kind: .settingsAction,
                titleKey: "plugins.newapi.title",
                titleFallback: "NewAPI 签到",
                systemImageName: "gearshape",
                order: 300
            ),
        ],
        defaultEnabled: true,
        order: 300
    )

    static let ldcStore = PluginManifest(
        id: BuiltInPluginID.ldcStore,
        displayName: "LD 士多",
        version: "0.1.0",
        minimumHostVersion: "1.2",
        publisher: "DexoFlux",
        supportedHosts: ["linux.do"],
        capabilities: [.browserNavigation, .restrictedNetwork, .pluginStorage],
        contributions: [
            PluginContribution(
                id: "main-tab",
                kind: .forumTab,
                titleKey: "plugins.ldc_store.title",
                titleFallback: "LD 士多",
                systemImageName: "LDStoreLogo",
                order: 310
            ),
            PluginContribution(
                id: "settings",
                kind: .settingsAction,
                titleKey: "plugins.ldc_store.title",
                titleFallback: "LD 士多",
                systemImageName: "gearshape",
                order: 310
            ),
        ],
        defaultEnabled: true,
        order: 310
    )
}
