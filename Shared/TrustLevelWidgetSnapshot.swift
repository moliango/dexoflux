import Foundation

enum TrustLevelWidgetIDs {
    static let appGroup = "group.com.naine.doer"
    static let snapshotKey = "trustLevel.widget.snapshot"
    static let widgetKind = "DoerTrustLevelWidget"
    static let deepLink = "doer://trust"
}

struct TrustLevelWidgetItem: Codable, Equatable {
    var label: String
    var current: Int
    var target: Int
    var isMet: Bool
    var isReverse: Bool

    var remaining: Int {
        if isReverse { return max(current - target, 0) }
        return max(target - current, 0)
    }
}

struct TrustLevelWidgetSnapshot: Codable, Equatable {
    var title: String
    var badgeText: String
    var subtitle: String
    var items: [TrustLevelWidgetItem]
    var updatedAt: Date
    var trustLevel: Int?

    var headlineItem: TrustLevelWidgetItem? {
        items.first { $0.label.contains("帖") || $0.label.lowercased().contains("post") || $0.label.contains("读") }
            ?? items.first { !$0.isMet }
            ?? items.first
    }
}

enum TrustLevelWidgetSnapshotStore {
    static func load(defaults: UserDefaults? = UserDefaults(suiteName: TrustLevelWidgetIDs.appGroup)) -> TrustLevelWidgetSnapshot? {
        guard let data = defaults?.data(forKey: TrustLevelWidgetIDs.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(TrustLevelWidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: TrustLevelWidgetSnapshot, defaults: UserDefaults? = UserDefaults(suiteName: TrustLevelWidgetIDs.appGroup)) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: TrustLevelWidgetIDs.snapshotKey)
    }
}
