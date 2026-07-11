import XCTest
@testable import dexoflux

@MainActor
final class CloudflareRecoveryTests: XCTestCase {
    func testVerificationTargetPrefersSameOriginChallengeURL() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://linux.do"))
        let responseURL = try XCTUnwrap(URL(string: "https://linux.do/t/123.json"))

        XCTAssertEqual(
            CloudflareVerificationPolicy.verificationURL(baseURL: baseURL, responseURL: responseURL).path,
            "/challenge"
        )
    }

    func testVerificationTargetRejectsExternalChallengeURL() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://linux.do"))
        let responseURL = try XCTUnwrap(URL(string: "https://example.com/challenge"))

        XCTAssertEqual(
            CloudflareVerificationPolicy.verificationURL(baseURL: baseURL, responseURL: responseURL).path,
            "/challenge"
        )
    }

    func testVerificationTargetRejectsImageChallengeURL() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://linux.do"))
        let responseURL = try XCTUnwrap(URL(string: "https://linux.do/user_avatar/linux.do/example/96/1.png"))

        XCTAssertEqual(
            CloudflareVerificationPolicy.verificationURL(baseURL: baseURL, responseURL: responseURL).path,
            "/challenge"
        )
    }

    func testAutomaticVerificationRequiresFreshClearance() {
        XCTAssertFalse(
            CloudflareVerificationPolicy.hasUsableClearance(
                currentValue: "old",
                initialValue: "old",
                requiresFreshValue: true
            )
        )
        XCTAssertTrue(
            CloudflareVerificationPolicy.hasUsableClearance(
                currentValue: "new",
                initialValue: "old",
                requiresFreshValue: true
            )
        )
        XCTAssertFalse(
            CloudflareVerificationPolicy.hasUsableClearance(
                currentValue: nil,
                initialValue: "old",
                requiresFreshValue: true
            )
        )
    }

    func testVerificationCompletionRequiresLoadedVerifiedPage() {
        XCTAssertFalse(
            CloudflareVerificationPolicy.canCompleteVerification(
                currentValue: "new",
                initialValue: "old",
                requiresFreshValue: true,
                hasVerifiedPage: false,
                hasActiveChallenge: false
            )
        )
    }

    func testVerificationCompletionRejectsActiveChallenge() {
        XCTAssertFalse(
            CloudflareVerificationPolicy.canCompleteVerification(
                currentValue: "new",
                initialValue: "old",
                requiresFreshValue: true,
                hasVerifiedPage: true,
                hasActiveChallenge: true
            )
        )
        XCTAssertTrue(
            CloudflareVerificationPolicy.canCompleteVerification(
                currentValue: "new",
                initialValue: "old",
                requiresFreshValue: true,
                hasVerifiedPage: true,
                hasActiveChallenge: false
            )
        )
    }

    func testOriginChallenge404CanCompleteAutomatically() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://linux.do"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: "https://linux.do/challenge")),
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Server": "nginx"]
        ))

        XCTAssertTrue(
            CloudflareVerificationPolicy.isVerifiedChallengeLanding(
                response,
                baseURL: baseURL
            )
        )
    }

    func testCloudflareMitigatedChallenge404CannotCompleteAutomatically() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://linux.do"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(URL(string: "https://linux.do/challenge")),
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["cf-mitigated": "challenge", "Server": "cloudflare"]
        ))

        XCTAssertFalse(
            CloudflareVerificationPolicy.isVerifiedChallengeLanding(
                response,
                baseURL: baseURL
            )
        )
    }

    func testHeaderOnlyImageChallengeIsDetected() throws {
        let url = try XCTUnwrap(URL(string: "https://linux.do/user_avatar/example.png"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["cf-mitigated": "challenge"]
        ))

        XCTAssertTrue(DiscourseAPI.isCloudflareChallengeResponse(response, data: nil))
    }

    func testServiceUnavailableCloudflareImageChallengeIsDetected() throws {
        let url = try XCTUnwrap(URL(string: "https://linux.do/user_avatar/example.png"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 503,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html", "Server": "cloudflare"]
        ))

        XCTAssertTrue(DiscourseAPI.isCloudflareChallengeResponse(response, data: nil))
    }

    func testOrdinaryForbiddenImageIsNotACloudflareChallenge() throws {
        let url = try XCTUnwrap(URL(string: "https://linux.do/user_avatar/missing.png"))
        let response = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png", "Server": "nginx"]
        ))

        XCTAssertFalse(DiscourseAPI.isCloudflareChallengeResponse(response, data: nil))
    }
}
