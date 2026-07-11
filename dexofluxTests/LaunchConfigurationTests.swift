import XCTest
import UIKit
@testable import dexoflux

@MainActor
final class LaunchConfigurationTests: XCTestCase {
    func testSystemLaunchScreenUsesTheRuntimeLaunchBackground() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plistURL = projectRoot.appendingPathComponent("dexo/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let root = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let launchScreen = try XCTUnwrap(root["UILaunchScreen"] as? [String: Any])

        XCTAssertEqual(
            launchScreen["UIColorName"] as? String,
            DexoLaunchAppearance.backgroundColorName
        )
        XCTAssertNil(launchScreen["UIToolbar"])
    }

    func testLaunchBackgroundColorAssetExists() {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetURL = projectRoot.appendingPathComponent(
            "dexo/Assets.xcassets/LaunchBackground.colorset/Contents.json"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: assetURL.path))
        XCTAssertNotNil(UIColor(named: DexoLaunchAppearance.backgroundColorName))
    }
}
