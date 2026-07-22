import XCTest

@testable import dexoflux

final class TrustRequirementsParsingTests: XCTestCase {
    func testConnectCardParsesRingsBarsQuotasAndVetos() throws {
        let html = """
        <html><body><div class="card">
          <h2 class="card-title">信任级别 3</h2>
          <span class="badge badge-success">已达标</span>
          <div class="card-subtitle">@tester</div>
          <div class="tl3-ring">
            <div class="tl3-ring-circle met" style="--val: 92; --max: 100;"></div>
            <div class="tl3-ring-label">访问天数</div>
          </div>
          <div class="tl3-bar-item">
            <span class="tl3-bar-label">已读帖子</span>
            <span class="tl3-bar-nums">5000 / 20000</span>
            <div class="tl3-bar-fill" style="--val: 5000; --max: 20000;"></div>
          </div>
          <div class="tl3-quota-card unmet">
            <span class="tl3-quota-label">被举报帖子</span>
            <span class="tl3-quota-nums">6 / 5</span>
            <div class="tl3-slot used"></div>
            <div class="tl3-slot used"></div>
            <div class="tl3-slot"></div>
          </div>
          <div class="tl3-veto-item">
            <div class="tl3-veto-front">
              <div class="tl3-veto-label">被禁言</div>
              <div class="tl3-veto-desc">过去 6 个月</div>
              <div class="tl3-veto-value">0</div>
            </div>
            <div class="tl3-veto-back">
              <div class="tl3-veto-label">被禁言（未满足）</div>
            </div>
          </div>
          <div class="text-hint">数据每小时更新</div>
          <div class="status-unmet">尚未满足全部要求</div>
        </div></body></html>
        """

        let report = try ConnectTrustParser.parse(html: html)

        XCTAssertFalse(report.isEmptyState)
        XCTAssertEqual(report.title, "信任级别 3")
        XCTAssertEqual(report.badgeText, "已达标")
        XCTAssertEqual(report.badgeKind, .success)
        XCTAssertEqual(report.subtitle, "@tester")

        XCTAssertEqual(report.rings.count, 1)
        XCTAssertEqual(report.rings[0].label, "访问天数")
        XCTAssertEqual(report.rings[0].current, 92)
        XCTAssertEqual(report.rings[0].max, 100)
        XCTAssertTrue(report.rings[0].isMet)

        XCTAssertEqual(report.bars.count, 1)
        XCTAssertEqual(report.bars[0].currentText, "5000 / 20000")
        XCTAssertEqual(report.bars[0].progress, 0.25, accuracy: 0.001)
        XCTAssertFalse(report.bars[0].isMet)

        XCTAssertEqual(report.quotas.count, 1)
        XCTAssertFalse(report.quotas[0].isMet)
        XCTAssertEqual(report.quotas[0].usedSlots, 2)

        XCTAssertEqual(report.vetos.count, 1)
        XCTAssertTrue(report.vetos[0].isMet)
        XCTAssertEqual(report.vetos[0].label, "被禁言")
        XCTAssertEqual(report.vetos[0].value, "0")

        XCTAssertEqual(report.footerHint, "数据每小时更新")
        XCTAssertEqual(report.statusText, "尚未满足全部要求")
        XCTAssertFalse(report.isStatusMet)
    }

    func testConnectEmptyStateCardIsDetected() throws {
        let html = """
        <html><body><div class="card empty-state">
          <h2 class="card-title">Connect</h2>
          <p>当前 2 级用户</p>
          <p>暂未开放详细数据</p>
        </div></body></html>
        """

        let report = try ConnectTrustParser.parse(html: html)

        XCTAssertTrue(report.isEmptyState)
        XCTAssertEqual(report.title, "Connect")
        XCTAssertEqual(report.emptyParagraphs, ["当前 2 级用户", "暂未开放详细数据"])
    }

    func testConnectChallengePageThrowsCardNotFound() {
        let html = "<html><head><title>Just a moment...</title></head><body></body></html>"
        XCTAssertThrowsError(try ConnectTrustParser.parse(html: html))
    }

    func testFallbackCatalogComputesProgressAndReverseItems() throws {
        let summary = try JSONDecoder().decode(
            DiscourseUserSummary.self,
            from: Data("""
            {"days_visited": 10, "likes_given": 2, "likes_received": 0,
             "post_count": 3, "topics_entered": 10, "posts_read_count": 50,
             "time_read": 1800}
            """.utf8)
        )

        let level1 = TrustFallbackCatalog.requirements(level: 1, summary: summary)
        XCTAssertEqual(level1.count, 7)

        let daysVisited = try XCTUnwrap(level1.first { $0.current == 10 && $0.target == 15 })
        XCTAssertFalse(daysVisited.isMet)
        XCTAssertEqual(daysVisited.progress, 10.0 / 15.0, accuracy: 0.001)

        let likesGiven = try XCTUnwrap(level1.first { $0.current == 2 && $0.target == 1 })
        XCTAssertTrue(likesGiven.isMet)
        XCTAssertEqual(likesGiven.progress, 1.0, accuracy: 0.001)

        // time_read is seconds; catalog converts to minutes (1800s → 30min of 60)
        let reading = try XCTUnwrap(level1.first { $0.current == 30 && $0.target == 60 })
        XCTAssertFalse(reading.isMet)

        let level3 = TrustFallbackCatalog.requirements(level: 3, summary: summary)
        let reverse = try XCTUnwrap(level3.first { $0.isReverse && $0.target == 5 })
        XCTAssertTrue(reverse.isMet)
        XCTAssertEqual(reverse.progress, 1.0, accuracy: 0.001)

        let zeroTolerance = try XCTUnwrap(level3.first { $0.isReverse && $0.target == 0 })
        XCTAssertTrue(zeroTolerance.isMet)
        XCTAssertTrue(zeroTolerance.valueText.contains("≤ 0"))
    }

    func testInviteLinkBuildsURLFromKeyWithForumBase() throws {
        let invite = try JSONDecoder().decode(
            DiscourseInviteLink.self,
            from: Data(#"{"id": 1, "invite_key": "abc123"}"#.utf8)
        )
        XCTAssertEqual(
            invite.effectiveURLString(baseURL: "https://example.org/"),
            "https://example.org/invites/abc123"
        )

        let withLink = try JSONDecoder().decode(
            DiscourseInviteLink.self,
            from: Data(#"{"id": 2, "link": "https://forum.tld/invites/xyz"}"#.utf8)
        )
        XCTAssertEqual(
            withLink.effectiveURLString(baseURL: "https://example.org"),
            "https://forum.tld/invites/xyz"
        )
    }
}
