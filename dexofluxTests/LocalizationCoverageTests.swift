import XCTest

@MainActor
final class LocalizationCoverageTests: XCTestCase {
    func testProfileActionStringsHaveAllChineseLocalizations() async throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = projectRoot.appendingPathComponent("dexo/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        let keys = [
            "action.confirm",
            "user.profile.ignore",
            "user.profile.ignore.custom",
            "user.profile.ignore.day",
            "user.profile.ignore.month",
            "user.profile.ignore.week",
            "user.profile.interactions",
            "user.profile.mute",
            "user.profile.replied_to",
            "user.profile.restore_notifications",
            "user.profile.share",
            "user.profile.top_categories",
            "user.profile.top_links",
            "user.profile.top_replies",
            "user.profile.unfollow",
        ]

        for key in keys {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "Missing key: \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "Missing localizations: \(key)")
            for locale in ["zh-Hans", "zh-Hant", "zh-HK"] {
                let localization = try XCTUnwrap(localizations[locale] as? [String: Any], "Missing \(locale): \(key)")
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: Any], "Missing string unit: \(key) \(locale)")
                let value = try XCTUnwrap(unit["value"] as? String, "Missing value: \(key) \(locale)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty value: \(key) \(locale)")
            }
        }
    }
}
