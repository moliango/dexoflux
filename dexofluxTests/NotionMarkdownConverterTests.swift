import XCTest
@testable import dexoflux

final class NotionMarkdownConverterTests: XCTestCase {
    func testHeadingsListsCodeAndImage() {
        let md = """
        # Title
        hello world
        - a
        - b
        ```swift
        print(1)
        ```
        ![x](https://example.com/a.png)
        """
        let blocks = NotionMarkdownConverter.blocks(from: md)
        let types = blocks.compactMap { $0["type"] as? String }
        XCTAssertTrue(types.contains("heading_1"))
        XCTAssertTrue(types.contains("paragraph"))
        XCTAssertTrue(types.contains("bulleted_list_item"))
        XCTAssertTrue(types.contains("code"))
        XCTAssertTrue(types.contains("image"))
    }

    func testChunking() {
        let blocks = (0..<250).map { _ in
            ["object": "block", "type": "paragraph", "paragraph": ["rich_text": []]] as [String: Any]
        }
        let chunks = NotionMarkdownConverter.chunked(blocks)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].count, 100)
        XCTAssertEqual(chunks[2].count, 50)
    }
}
