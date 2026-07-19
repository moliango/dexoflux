import XCTest
@testable import dexoflux

@MainActor
final class NewAPICheckInTests: XCTestCase {
    func testStoreIsScopedAndKeepsCredentialsOutOfJSON() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = MemoryNewAPICredentialVault()
        let samStore = NewAPICheckInStore(
            scope: PluginScope(baseURL: "HTTPS://LINUX.DO/", username: "Sam"),
            directoryURL: directory,
            credentialVault: vault
        )
        let alexStore = NewAPICheckInStore(
            scope: PluginScope(baseURL: "https://linux.do", username: "alex"),
            directoryURL: directory,
            credentialVault: vault
        )
        let platform = NewAPICheckInPlatform(name: "Example", baseURL: "https://api.example.com")
        let credential = NewAPICheckInCredential(
            accessToken: "secret-token",
            userID: "42",
            cookieHeader: "session=secret-cookie"
        )

        try await samStore.save(platform, credential: credential)

        let samPlatforms = await samStore.platforms()
        let alexPlatforms = await alexStore.platforms()
        let storedCredential = try await samStore.credential(for: platform.id)
        XCTAssertEqual(samPlatforms.map(\.id), [platform.id])
        XCTAssertTrue(alexPlatforms.isEmpty)
        XCTAssertEqual(storedCredential, credential)

        let data = try Data(contentsOf: NewAPICheckInStore.storageURL(in: directory))
        let raw = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(raw.contains("secret-token"))
        XCTAssertFalse(raw.contains("secret-cookie"))
    }

    func testServiceBuildsAuthenticatedRequestClassifiesAndPersistsResult() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = MemoryNewAPICredentialVault()
        let store = NewAPICheckInStore(
            scope: PluginScope(baseURL: "https://linux.do", username: "sam"),
            directoryURL: directory,
            credentialVault: vault
        )
        let platform = NewAPICheckInPlatform(name: "Example", baseURL: "https://api.example.com")
        try await store.save(
            platform,
            credential: NewAPICheckInCredential(
                accessToken: "token-value",
                userID: "7",
                cookieHeader: "session=cookie-value"
            )
        )

        MockNewAPIURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/api/user/checkin")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-value")
            XCTAssertEqual(request.value(forHTTPHeaderField: "New-Api-User"), "7")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=cookie-value")
            let body = Data(#"{"success":true,"message":"签到成功","data":{"quota":1000000}}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockNewAPIURLProtocol.self]
        let service = NewAPICheckInService(store: store, session: URLSession(configuration: configuration))

        let result = await service.signIn(platform)
        let attempts = await store.attempts()
        let storedPlatforms = await store.platforms()

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.quotaValue, 1_000_000)
        XCTAssertEqual(attempts.first?.status, .success)
        XCTAssertEqual(storedPlatforms.first?.lastQuotaValue, 1_000_000)
    }

    func testResponseClassificationRecognizesAlreadySignedAndExpiredAuthentication() {
        let already = NewAPICheckInService.classify(
            data: Data(#"{"success":false,"message":"今日已签到"}"#.utf8),
            statusCode: 200,
            durationMilliseconds: 1
        )
        let expired = NewAPICheckInService.classify(
            data: Data(#"{"message":"请先登录"}"#.utf8),
            statusCode: 200,
            durationMilliseconds: 1
        )

        XCTAssertEqual(already.status, .alreadySigned)
        XCTAssertEqual(expired.status, .authenticationExpired)
    }

    func testLoginSupportExtractsLocalStorageHintsAndCookieHeader() throws {
        let hints = NewAPICheckInLoginSupport.parseLocalStorageResult(
            #"{"id":"42","accessToken":"token-value"}"#
        )
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "session",
            .value: "cookie-value",
            .domain: ".example.com",
            .path: "/",
            .secure: "TRUE",
        ]))
        let unrelated = try XCTUnwrap(HTTPCookie(properties: [
            .name: "other",
            .value: "ignored",
            .domain: ".unrelated.test",
            .path: "/",
        ]))
        let baseURL = try XCTUnwrap(URL(string: "https://api.example.com"))
        let header = NewAPICheckInLoginSupport.cookieHeader(
            from: [unrelated, cookie],
            baseURL: baseURL,
            currentURL: URL(string: "https://oauth.unrelated.test/login")
        )

        XCTAssertEqual(hints, NewAPICheckInLoginHints(userID: "42", accessToken: "token-value"))
        XCTAssertEqual(header, "session=cookie-value")
    }

    func testWebLoginURLNormalizationKeepsLoginPathAndQuery() {
        let url = NewAPICheckInLoginSupport.normalizedLoginURL(
            "  api.example.com/oauth/start?tenant=dexo#login  "
        )

        XCTAssertEqual(url?.absoluteString, "https://api.example.com/oauth/start?tenant=dexo#login")
    }

    func testLocalStorageIdentityCompletesLoginOnlyWithTargetCookie() {
        let hints = NewAPICheckInLoginHints(userID: "42", accessToken: nil)

        XCTAssertTrue(NewAPICheckInLoginSupport.hasValidLoginEvidence(
            apiLoggedIn: false,
            hints: hints,
            hasTargetCookies: true
        ))
        XCTAssertFalse(NewAPICheckInLoginSupport.hasValidLoginEvidence(
            apiLoggedIn: false,
            hints: hints,
            hasTargetCookies: false
        ))
        XCTAssertTrue(NewAPICheckInLoginSupport.hasValidLoginEvidence(
            apiLoggedIn: true,
            hints: NewAPICheckInLoginHints(userID: nil, accessToken: nil),
            hasTargetCookies: false
        ))
    }

    func testLoginProbeUsesHintsAndParsesServerCredentials() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = NewAPICheckInStore(
            scope: PluginScope(baseURL: "https://linux.do", username: "sam"),
            directoryURL: directory,
            credentialVault: MemoryNewAPICredentialVault()
        )
        MockNewAPIURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/api/user/self")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "New-Api-User"), "7")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=cookie")
            let data = Data(#"{"success":true,"data":{"id":8,"access_token":"server-token","quota":500000}}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockNewAPIURLProtocol.self]
        let service = NewAPICheckInService(store: store, session: URLSession(configuration: configuration))

        let result = await service.probeLogin(
            baseURL: try XCTUnwrap(URL(string: "https://api.example.com")),
            cookieHeader: "session=cookie",
            hints: NewAPICheckInLoginHints(userID: "7", accessToken: "local-token")
        )

        XCTAssertTrue(result.isLoggedIn)
        XCTAssertEqual(result.userID, "8")
        XCTAssertEqual(result.accessToken, "server-token")
        XCTAssertEqual(result.quotaValue, 500_000)
    }

    func testCurlParserParsesBrowserCopiedRequest() throws {
        let command = #"""
        curl 'https://api.example.com/api/user/checkin?source=ios' \
          -X put \
          -H 'New-Api-User: 42' \
          -H 'Content-Type: application/json' \
          -H 'Cookie: session=abc; theme=dark' \
          --data-raw '{"message":"it'\''s ready","enabled":true}'
        """#

        let request = try NewAPICurlParser.parse(command)

        XCTAssertEqual(request.url.absoluteString, "https://api.example.com/api/user/checkin?source=ios")
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.headers["New-Api-User"], "42")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(request.headers["Cookie"], "session=abc; theme=dark")
        XCTAssertEqual(request.body, #"{"message":"it's ready","enabled":true}"#)
    }

    func testCurlParserInfersMethodAndHandlesWindowsLineContinuations() throws {
        let command = "curl --location \"https://api.example.com/checkin\" \\\r\n  --data-binary \"{\\\"value\\\":\\\"a b\\\"}\""

        let request = try NewAPICurlParser.parse(command)

        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.body, #"{"value":"a b"}"#)
    }

    func testCurlParserNormalizesCookieFlagWithoutOverwritingCookieHeader() throws {
        let request = try NewAPICurlParser.parse(
            "curl https://api.example.com -b 'session=from-flag' -H 'cookie: session=from-header'"
        )

        XCTAssertEqual(request.headers.count, 1)
        XCTAssertEqual(request.headers["cookie"], "session=from-header")
    }

    func testCurlParserSupportsLongOptionsWithEquals() throws {
        let request = try NewAPICurlParser.parse(
            "curl --request=PATCH --header='X-Mode: full sync' --data='{}' https://api.example.com/checkin"
        )

        XCTAssertEqual(request.method, "PATCH")
        XCTAssertEqual(request.headers["X-Mode"], "full sync")
        XCTAssertEqual(request.body, "{}")
    }

    func testCurlParserRejectsMissingAndNonHTTPURLs() {
        XCTAssertThrowsError(try NewAPICurlParser.parse("curl -X POST")) { error in
            XCTAssertEqual(error as? NewAPICurlParseError, .missingURL)
        }
        XCTAssertThrowsError(try NewAPICurlParser.parse("curl file:///tmp/token")) { error in
            XCTAssertEqual(error as? NewAPICurlParseError, .invalidURL("file:///tmp/token"))
        }
        XCTAssertThrowsError(try NewAPICurlParser.parse("curl 'https://api.example.com")) { error in
            XCTAssertEqual(error as? NewAPICurlParseError, .malformed("unterminated single quote"))
        }
    }

    func testClearingAttemptsKeepsPlatformsAndCredentials() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = MemoryNewAPICredentialVault()
        let store = NewAPICheckInStore(
            scope: PluginScope(baseURL: "https://linux.do", username: "sam"),
            directoryURL: directory,
            credentialVault: vault
        )
        let platform = NewAPICheckInPlatform(name: "Example", baseURL: "https://api.example.com")
        try await store.save(platform, credential: NewAPICheckInCredential(accessToken: "token"))
        try await store.record(
            NewAPICheckInResult(
                status: .success,
                statusCode: 200,
                message: "ok",
                rawResponse: "{}",
                durationMilliseconds: 10,
                quotaValue: nil,
                quotaUnit: nil
            ),
            for: platform.id
        )

        try await store.clearAttempts()

        let attempts = await store.attempts()
        let platformIDs = await store.platforms().map(\.id)
        let storedCredential = try await store.credential(for: platform.id)
        XCTAssertTrue(attempts.isEmpty)
        XCTAssertEqual(platformIDs, [platform.id])
        XCTAssertEqual(storedCredential?.accessToken, "token")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("newapi-checkin-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class MemoryNewAPICredentialVault: NewAPICheckInCredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    nonisolated func data(for key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    nonisolated func setData(_ data: Data, for key: String) throws {
        lock.lock()
        values[key] = data
        lock.unlock()
    }

    nonisolated func removeData(for key: String) throws {
        lock.lock()
        values.removeValue(forKey: key)
        lock.unlock()
    }
}

private final class MockNewAPIURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

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
