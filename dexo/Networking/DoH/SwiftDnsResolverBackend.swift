import Foundation

#if canImport(DNS)
@_implementationOnly import DNS
#endif

enum SwiftDnsResolverBackend {
    static var isAvailable: Bool {
        #if canImport(DNS)
        true
        #else
        false
        #endif
    }

    static var engineName: String {
        isAvailable ? "swift-dns" : "legacy-wire"
    }
}
