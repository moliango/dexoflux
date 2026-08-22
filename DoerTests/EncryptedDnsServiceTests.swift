import Network
import XCTest
@testable import Doer

final class EncryptedDnsServiceTests: XCTestCase {
    func testAliDNSSpecUsesBootstrapIPs() throws {
        let spec = try XCTUnwrap(
            EncryptedDnsService.spec(
                urlString: "https://dns.alidns.com/dns-query",
                providerRaw: AppSettings.DoHProvider.alidns.rawValue
            )
        )
        XCTAssertEqual(spec.url.absoluteString, "https://dns.alidns.com/dns-query")
        XCTAssertEqual(spec.bootstrapIPs, ["223.5.5.5", "223.6.6.6"])
        XCTAssertEqual(EncryptedDnsService.bootstrapEndpoints(spec.bootstrapIPs).count, 2)
    }

    func testCustomIPURLBootstrapsFromHost() throws {
        let spec = try XCTUnwrap(
            EncryptedDnsService.spec(
                urlString: "https://223.5.5.5/dns-query",
                providerRaw: AppSettings.DoHProvider.custom.rawValue
            )
        )
        XCTAssertEqual(spec.bootstrapIPs, ["223.5.5.5"])
    }

    func testRejectsNonHTTPSURL() {
        XCTAssertNil(
            EncryptedDnsService.spec(
                urlString: "http://dns.alidns.com/dns-query",
                providerRaw: AppSettings.DoHProvider.alidns.rawValue
            )
        )
        XCTAssertNil(
            EncryptedDnsService.spec(
                urlString: "",
                providerRaw: AppSettings.DoHProvider.custom.rawValue
            )
        )
    }
}
