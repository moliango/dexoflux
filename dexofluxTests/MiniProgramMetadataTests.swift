import XCTest
@testable import Doer

final class MiniProgramMetadataTests: XCTestCase {
    func testParsesOpenGraphTitleAndAppleTouchIcon() throws {
        let html = """
        <html>
          <head>
            <meta property="og:site_name" content="Example App">
            <link rel="apple-touch-icon" href="/apple.png">
            <title>Fallback Title</title>
          </head>
        </html>
        """

        let metadata = MiniProgramMetadataParser.parse(
            html: html,
            pageURL: try XCTUnwrap(URL(string: "https://example.com/app"))
        )

        XCTAssertEqual(metadata.name, "Example App")
        XCTAssertEqual(metadata.iconURL?.absoluteString, "https://example.com/apple.png")
    }

    func testFallsBackToTitleAndFavicon() throws {
        let html = """
        <html>
          <head>
            <link rel="shortcut icon" href="favicon.ico">
            <title>Docs</title>
          </head>
        </html>
        """

        let metadata = MiniProgramMetadataParser.parse(
            html: html,
            pageURL: try XCTUnwrap(URL(string: "https://docs.example.com/path/index.html"))
        )

        XCTAssertEqual(metadata.name, "Docs")
        // Bare relative favicon should resolve against the page first.
        XCTAssertEqual(metadata.iconURL?.absoluteString, "https://docs.example.com/path/favicon.ico")
    }

    func testFallsBackToRootFaviconWhenHTMLHasNoIcon() throws {
        let metadata = MiniProgramMetadataParser.parse(
            html: "<html><body>Hello</body></html>",
            pageURL: try XCTUnwrap(URL(string: "https://empty.example.com/deep/path"))
        )

        XCTAssertEqual(metadata.name, "empty.example.com")
        XCTAssertEqual(metadata.iconURL?.absoluteString, "https://empty.example.com/favicon.ico")
    }

    func testIgnoresSVGIconAndFallsBackToRootFavicon() throws {
        let html = """
        <html>
          <head>
            <link rel="icon" href="/favicon.svg">
            <title>Vector App</title>
          </head>
        </html>
        """

        let metadata = MiniProgramMetadataParser.parse(
            html: html,
            pageURL: try XCTUnwrap(URL(string: "https://vector.example.com"))
        )

        XCTAssertEqual(metadata.name, "Vector App")
        XCTAssertEqual(metadata.iconURL?.absoluteString, "https://vector.example.com/favicon.ico")
    }

    func testPublicFaviconServiceURLUsesHost() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://linux.do/t/topic/1"))
        let serviceURL = MiniProgramMetadataParser.publicFaviconServiceURL(for: pageURL)
        XCTAssertEqual(
            serviceURL?.absoluteString,
            "https://www.google.com/s2/favicons?domain=linux.do&sz=128"
        )
    }

    func testRootFaviconURLStripsPathAndQuery() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/a/b?x=1#y"))
        let favicon = MiniProgramMetadataParser.rootFaviconURL(for: pageURL)
        XCTAssertEqual(favicon?.absoluteString, "https://example.com/favicon.ico")
    }
}
