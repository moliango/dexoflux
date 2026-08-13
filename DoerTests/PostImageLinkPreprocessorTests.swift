import XCTest
@testable import Doer

final class PostImageLinkPreprocessorTests: XCTestCase {
    func testRewritesBareImageAnchorToImg() {
        let html = #"<p><a href="https://pan.644222.xyz/raw/abc.jpg">https://pan.644222.xyz/raw/abc.jpg</a></p>"#
        let out = PostImageLinkPreprocessor.rewrite(html)
        XCTAssertTrue(out.contains(#"<img src="https://pan.644222.xyz/raw/abc.jpg""#))
        XCTAssertFalse(out.contains("<a "))
    }

    func testRewritesBadgeAnchorToImg() {
        let html = #"<p><a href="https://prompt.iwooji.com/badge?u=a&t=b">https://prompt.iwooji.com/badge?u=a&t=b</a></p>"#
        let out = PostImageLinkPreprocessor.rewrite(html)
        XCTAssertTrue(out.contains("prompt.iwooji.com/badge"))
        XCTAssertTrue(out.contains("<img "))
    }

    func testKeepsMentionLinks() {
        let html = #"<p><a class="mention" href="/u/alice">@alice</a></p>"#
        let out = PostImageLinkPreprocessor.rewrite(html)
        XCTAssertEqual(out, html)
    }
}
