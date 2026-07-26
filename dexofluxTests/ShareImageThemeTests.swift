import XCTest
@testable import dexoflux

final class ShareImageThemeTests: XCTestCase {
    func testThemeIndexRoundTrip() {
        let original = ShareImagePreferences.theme
        defer { ShareImagePreferences.theme = original }

        for theme in ShareImageTheme.allCases {
            ShareImagePreferences.theme = theme
            XCTAssertEqual(ShareImagePreferences.theme, theme)
        }
    }

    func testFromIndexFallback() {
        XCTAssertEqual(ShareImageTheme.fromIndex(0), .classic)
        XCTAssertEqual(ShareImageTheme.fromIndex(99), .classic)
    }
}
