import XCTest
@testable import dexoflux

@MainActor
final class AppUpdateServiceTests: XCTestCase {
    override func tearDown() {
        MockAppUpdateURLProtocol.handler = nil
        super.tearDown()
    }

    func testReleaseTagParsingAndVersionComparison() throws {
        let current = AppVersion(marketingVersion: "1.2", buildNumber: 7)

        XCTAssertEqual(
            AppVersion(releaseTag: "v1.2-build.8"),
            AppVersion(marketingVersion: "1.2", buildNumber: 8)
        )
        XCTAssertFalse(try XCTUnwrap(AppVersion(releaseTag: "v1.2-build.8")).isNewer(than: current))
        XCTAssertFalse(try XCTUnwrap(AppVersion(releaseTag: "v1.2-build.7")).isNewer(than: current))
        XCTAssertFalse(try XCTUnwrap(AppVersion(releaseTag: "v1.2-build.6")).isNewer(than: current))
        XCTAssertTrue(try XCTUnwrap(AppVersion(releaseTag: "v1.3-build.1")).isNewer(than: current))
        XCTAssertTrue(
            AppVersion(marketingVersion: "1.2.1", buildNumber: 1)
                .isNewer(than: AppVersion(marketingVersion: "1.2", buildNumber: 99))
        )
        XCTAssertFalse(
            AppVersion(marketingVersion: "1.2", buildNumber: 99)
                .isNewer(than: AppVersion(marketingVersion: "1.2.0", buildNumber: 1))
        )
    }

    func testReleaseTagParserRejectsUnsupportedFormats() {
        XCTAssertNil(AppVersion(releaseTag: "1.2-build.7"))
        XCTAssertNil(AppVersion(releaseTag: "v1.2.7"))
        XCTAssertNil(AppVersion(releaseTag: "v1.2-build.beta"))
        XCTAssertNil(AppVersion(releaseTag: "v1..2-build.7"))
        XCTAssertNil(AppVersion(releaseTag: "v999999999999999999999-build.7"))
    }

    func testReleaseDecodingSelectsUnsignedIPAAndStableReleaseCanTriggerUpdate() async throws {
        MockAppUpdateURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "DexoFlux-iOS")
            return Self.response(request: request, statusCode: 200, headers: ["ETag": #""release-etag""#])
        }
        let service = makeService()

        let release = try await service.check(mode: .manual)

        XCTAssertEqual(release.tagName, "v1.2-build.8")
        XCTAssertEqual(release.version, AppVersion(marketingVersion: "1.2", buildNumber: 8))
        XCTAssertEqual(release.releaseNotes, "Release notes")
        XCTAssertEqual(release.htmlURL.absoluteString, "https://github.com/moliango/dexoflux/releases/tag/v1.2-build.8")
        XCTAssertEqual(release.ipaAsset?.name, "dexoflux-unsigned.ipa")
        XCTAssertEqual(release.ipaAsset?.size, 12_345_678)
        XCTAssertFalse(release.isUpdateAvailable(comparedTo: AppVersion(marketingVersion: "1.2", buildNumber: 7)))
        XCTAssertTrue(release.isUpdateAvailable(comparedTo: AppVersion(marketingVersion: "1.1", buildNumber: 999)))
    }

    func testDraftAndPrereleaseNeverTriggerUpdate() throws {
        let data = Self.releaseData(draft: true)
        let draft = try JSONDecoder.githubReleaseDecoder.decode(AppRelease.self, from: data)
        let prerelease = try JSONDecoder.githubReleaseDecoder.decode(
            AppRelease.self,
            from: Self.releaseData(prerelease: true)
        )
        let current = AppVersion(marketingVersion: "1.2", buildNumber: 1)

        XCTAssertFalse(draft.isUpdateAvailable(comparedTo: current))
        XCTAssertFalse(prerelease.isUpdateAvailable(comparedTo: current))
    }

    func testMalformedReleaseTagIsRejectedDuringDecoding() {
        XCTAssertThrowsError(
            try JSONDecoder.githubReleaseDecoder.decode(
                AppRelease.self,
                from: Self.releaseData(tagName: "v1.3")
            )
        )
    }

    func testReleaseWithoutIPAStillDecodesAndKeepsReleasePage() throws {
        let release = try JSONDecoder.githubReleaseDecoder.decode(
            AppRelease.self,
            from: Self.releaseData(includeIPA: false)
        )

        XCTAssertNil(release.ipaAsset)
        XCTAssertEqual(
            release.htmlURL.absoluteString,
            "https://github.com/moliango/dexoflux/releases/tag/v1.2-build.8"
        )
    }

    func testInstalledVersionReadsBundleValuesAndFallsBackSafely() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppUpdateServiceTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuredURL = directory.appendingPathComponent("Configured.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: configuredURL, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "com.naine.dexoflux.tests.configured",
                "CFBundlePackageType": "BNDL",
                "CFBundleShortVersionString": "1.2",
                "CFBundleVersion": "7",
            ],
            format: .xml,
            options: 0
        ).write(to: configuredURL.appendingPathComponent("Info.plist"))

        let fallbackURL = directory.appendingPathComponent("Fallback.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: fallbackURL, withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleIdentifier": "com.naine.dexoflux.tests.fallback",
                "CFBundlePackageType": "BNDL",
            ],
            format: .xml,
            options: 0
        ).write(to: fallbackURL.appendingPathComponent("Info.plist"))

        let configuredBundle = try XCTUnwrap(Bundle(url: configuredURL))
        let fallbackBundle = try XCTUnwrap(Bundle(url: fallbackURL))
        XCTAssertEqual(
            AppVersion.installed(in: configuredBundle),
            AppVersion(marketingVersion: "1.2", buildNumber: 7)
        )
        XCTAssertEqual(
            AppVersion.installed(in: fallbackBundle),
            AppVersion(marketingVersion: "0", buildNumber: 0)
        )
    }

    func testAutomaticCheckUsesFreshCacheWithoutNetworkRequest() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        var requestCount = 0
        MockAppUpdateURLProtocol.handler = { request in
            requestCount += 1
            return Self.response(request: request, statusCode: 200, headers: ["ETag": #""release-etag""#])
        }
        let service = makeService(clock: clock)
        _ = try await service.check(mode: .manual)
        clock.now = clock.now.addingTimeInterval(3_599)

        let cached = try await service.check(mode: .automatic)

        XCTAssertEqual(cached.tagName, "v1.2-build.8")
        XCTAssertEqual(requestCount, 1)
    }

    func testManualCheckUsesETagAnd304RefreshesCacheAge() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 2_000))
        var requestCount = 0
        MockAppUpdateURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
                return Self.response(request: request, statusCode: 200, headers: ["ETag": #""release-etag""#])
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), #""release-etag""#)
            return Self.response(request: request, statusCode: 304, data: Data())
        }
        let service = makeService(clock: clock)
        _ = try await service.check(mode: .manual)
        clock.now = clock.now.addingTimeInterval(7_200)

        let notModified = try await service.check(mode: .manual)
        clock.now = clock.now.addingTimeInterval(3_599)
        let fresh = try await service.check(mode: .automatic)

        XCTAssertEqual(notModified.tagName, "v1.2-build.8")
        XCTAssertEqual(fresh.tagName, "v1.2-build.8")
        XCTAssertEqual(requestCount, 2)
    }

    func testRateLimitResponsesFallBackToStaleCache() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 3_000))
        var statusCode = 200
        MockAppUpdateURLProtocol.handler = { request in
            Self.response(request: request, statusCode: statusCode)
        }
        let service = makeService(clock: clock)
        _ = try await service.check(mode: .manual)
        clock.now = clock.now.addingTimeInterval(7_200)

        statusCode = 403
        let forbiddenFallback = try await service.check(mode: .manual)
        XCTAssertEqual(forbiddenFallback.tagName, "v1.2-build.8")
        statusCode = 429
        let rateLimitFallback = try await service.check(mode: .manual)
        XCTAssertEqual(rateLimitFallback.tagName, "v1.2-build.8")
    }

    func testServerFailureFallsBackToStaleCache() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 3_500))
        var statusCode = 200
        MockAppUpdateURLProtocol.handler = { request in
            Self.response(request: request, statusCode: statusCode)
        }
        let service = makeService(clock: clock)
        _ = try await service.check(mode: .manual)
        clock.now = clock.now.addingTimeInterval(7_200)
        statusCode = 503

        let fallback = try await service.check(mode: .manual)

        XCTAssertEqual(fallback.tagName, "v1.2-build.8")
    }

    func testNetworkFailureFallsBackToStaleCache() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 4_000))
        var shouldFail = false
        MockAppUpdateURLProtocol.handler = { request in
            if shouldFail { throw URLError(.notConnectedToInternet) }
            return Self.response(request: request, statusCode: 200)
        }
        let service = makeService(clock: clock)
        _ = try await service.check(mode: .manual)
        clock.now = clock.now.addingTimeInterval(7_200)
        shouldFail = true

        let cached = try await service.check(mode: .manual)

        XCTAssertEqual(cached.tagName, "v1.2-build.8")
    }

    func testFailureWithoutCacheThrowsRecoverableError() async {
        MockAppUpdateURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let service = makeService()

        do {
            _ = try await service.check(mode: .manual)
            XCTFail("Expected network failure")
        } catch let error as AppUpdateError {
            guard case .network = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    private func makeService(
        clock: TestClock = TestClock(Date(timeIntervalSince1970: 100))
    ) -> AppUpdateService {
        let suiteName = "AppUpdateServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockAppUpdateURLProtocol.self]
        return AppUpdateService(
            session: URLSession(configuration: configuration),
            defaults: defaults,
            now: { clock.now }
        )
    }

    private static func response(
        request: URLRequest,
        statusCode: Int,
        headers: [String: String]? = nil,
        data: Data? = nil
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!,
            data ?? releaseData()
        )
    }

    private static func releaseData(
        tagName: String = "v1.2-build.8",
        draft: Bool = false,
        prerelease: Bool = false,
        includeIPA: Bool = true
    ) -> Data {
        let ipaAsset = includeIPA
            ? """
              ,
                {
                  "name": "dexoflux-unsigned.ipa",
                  "browser_download_url": "https://example.com/dexoflux-unsigned.ipa",
                  "size": 12345678
                }
              """
            : ""
        return Data(
            """
            {
              "tag_name": "\(tagName)",
              "name": "DexoFlux 1.2 build 8",
              "body": "Release notes",
              "html_url": "https://github.com/moliango/dexoflux/releases/tag/v1.2-build.8",
              "draft": \(draft),
              "prerelease": \(prerelease),
              "published_at": "2026-07-18T10:00:00Z",
              "assets": [
                {
                  "name": "checksums.txt",
                  "browser_download_url": "https://example.com/checksums.txt",
                  "size": 64
                }
                \(ipaAsset)
              ]
            }
            """.utf8
        )
    }
}

private final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private final class MockAppUpdateURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler?(request) ?? {
                throw URLError(.badServerResponse)
            }()
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
