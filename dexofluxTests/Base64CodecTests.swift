import XCTest
@testable import Doer

final class Base64CodecTests: XCTestCase {
    func testEncodeDecodeRoundTripStandard() {
        let samples = [
            "hello",
            "你好，世界",
            "line1\nline2",
            "symbols !@#$%^&*()",
        ]
        for sample in samples {
            let encoded = Base64Codec.encode(sample, mode: .standard)
            let decoded = Base64Codec.decode(encoded, mode: .standard)
            XCTAssertEqual(decoded, .success(sample), "round-trip failed for \(sample)")
        }
    }

    func testEncodeURLSafeUsesSafeAlphabet() {
        // "???" in UTF-8 produces + and / in standard Base64 for some inputs;
        // use a known payload that yields both characters.
        let text = String(repeating: "\u{00ff}", count: 3) // ÿÿÿ
        let standard = Base64Codec.encode(text, mode: .standard)
        let urlSafe = Base64Codec.encode(text, mode: .urlSafe)

        XCTAssertFalse(urlSafe.contains("+"))
        XCTAssertFalse(urlSafe.contains("/"))
        XCTAssertEqual(
            urlSafe.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"),
            standard
        )
        XCTAssertEqual(Base64Codec.decode(urlSafe, mode: .urlSafe), .success(text))
    }

    func testDecodeAcceptsMissingPadding() {
        let encoded = Base64Codec.encode("hi", mode: .standard) // aGk=
        let withoutPadding = encoded.replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(Base64Codec.decode(withoutPadding, mode: .standard), .success("hi"))
    }

    func testDecodeRejectsInvalidInput() {
        XCTAssertEqual(Base64Codec.decode("   ", mode: .standard), .failure(.emptyInput))
        XCTAssertEqual(Base64Codec.decode("@@@@", mode: .standard), .failure(.invalidBase64))
    }

    func testDecodeIgnoresWhitespace() {
        let encoded = Base64Codec.encode("toolbox", mode: .standard)
        let spaced = encoded.map(String.init).joined(separator: " ")
        XCTAssertEqual(Base64Codec.decode(spaced, mode: .standard), .success("toolbox"))
    }
}
