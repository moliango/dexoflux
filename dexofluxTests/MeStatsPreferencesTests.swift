import XCTest
@testable import dexoflux

@MainActor
final class MeStatsPreferencesTests: XCTestCase {
    func testLegacySelectionMigratesInOrderWithGridLayout() {
        let suiteName = "MeStatsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["likesReceived", "topicCount", "daysVisited"], forKey: "me.stats.selected")

        let preferences = MeStatsPreferences(defaults: defaults)

        XCTAssertEqual(preferences.configuration.orderedMetrics, [.likesReceived, .topicCount, .daysVisited])
        XCTAssertEqual(preferences.configuration.layout, .grid)
    }

    func testConfigurationRoundTrips() {
        let suiteName = "MeStatsPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MeStatsPreferences(defaults: defaults)
        let configuration = MeStatsConfiguration(
            orderedMetrics: [.badges, .timeRead],
            layout: .horizontal
        )

        preferences.configuration = configuration

        let reloaded = MeStatsPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.configuration, configuration)
    }
}
