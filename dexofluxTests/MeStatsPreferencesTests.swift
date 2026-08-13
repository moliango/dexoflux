import XCTest
@testable import Doer

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

    func testAccountFunctionsDefaultToAllVisible() {
        let suiteName = "MeAccountFunctionPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = MeAccountFunctionPreferences(defaults: defaults)

        XCTAssertEqual(preferences.visibleFunctions, MeAccountFunction.allCases)
        XCTAssertTrue(preferences.hiddenFunctions.isEmpty)
    }

    func testAccountFunctionsVisibilityAndOrderRoundTrip() {
        let suiteName = "MeAccountFunctionPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MeAccountFunctionPreferences(defaults: defaults)

        preferences.setVisibleFunctions([.settings, .messages, .browser])

        let reloaded = MeAccountFunctionPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.visibleFunctions, [.settings, .messages, .browser])
        XCTAssertFalse(reloaded.hiddenFunctions.contains(.settings))
        XCTAssertTrue(reloaded.hiddenFunctions.contains(.aiModelService))
    }

    func testAccountFunctionsResetRestoresDefault() {
        let suiteName = "MeAccountFunctionPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = MeAccountFunctionPreferences(defaults: defaults)
        preferences.setVisibleFunctions([.settings])

        preferences.reset()

        XCTAssertEqual(preferences.visibleFunctions, MeAccountFunction.allCases)
        XCTAssertTrue(preferences.hiddenFunctions.isEmpty)
    }
}
