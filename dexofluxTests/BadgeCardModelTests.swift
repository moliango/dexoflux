import XCTest
@testable import dexoflux

final class BadgeCardModelTests: XCTestCase {
    func testParsesPromptIwoojiBadgeURL() throws {
        let url = try XCTUnwrap(URL(string: "https://prompt.iwooji.com/badge?u=alieismy&t=%3CLINUX%20DO%3E%20%E9%BE%99%E9%AA%91%E5%A3%AB&w=%E7%88%B1%E4%BD%A0%E6%89%80%E7%88%B1&lw=&k=none&l=6966ea&lfs=15&rfs=15&tc=%236966ea&dc=%2334495e&tfc=%23ffffff&dfc=%23ffffff&ec=717c6028"))
        let model = try XCTUnwrap(BadgeCardModel.parse(url: url))
        XCTAssertEqual(model.title, "<LINUX DO> 龙骑士")
        XCTAssertEqual(model.subtitle, "爱你所爱")
        XCTAssertTrue(model.showsPlayButton)
    }

    func testRejectsNonBadgeHosts() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/badge?t=hello"))
        XCTAssertNil(BadgeCardModel.parse(url: url))
    }
}
