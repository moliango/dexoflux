import Foundation

enum BuiltInPlugins {
    static let all: [PluginManifest] = [ldc, cdk, topicExport]

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
}
