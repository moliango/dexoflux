import UIKit
import XCTest
@testable import Doer

final class MiniProgramIconStoreTests: XCTestCase {
    func testSavesLocalIconDataWithProgramRelativePathAndLoadsImage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MiniProgramIconStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MiniProgramIconStore(baseDirectory: directory)
        let image = try XCTUnwrap(makeImage().pngData())

        let relativePath = try store.saveIconData(image, programID: "custom.test")

        XCTAssertEqual(relativePath, "MiniProgramIcons/custom.test.png")
        XCTAssertNotNil(store.image(relativePath: relativePath))
    }

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
