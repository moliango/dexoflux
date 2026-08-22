import Alamofire
import Foundation
import Security

nonisolated struct MitmTrustEvaluator: ServerTrustEvaluating {
    func evaluate(_ trust: SecTrust, forHost host: String) throws {
        if MitmCertificateAuthority.shared.evaluate(trust, host: host) {
            return
        }
        try DefaultTrustEvaluator().evaluate(trust, forHost: host)
    }
}

enum FluxDoMitmTrustManager {
    static func make() -> ServerTrustManager {
        ServerTrustManager(
            allHostsMustBeEvaluated: false,
            evaluators: ["linux.do": MitmTrustEvaluator()]
        )
    }
}

enum MitmTrust {
    static func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              MitmCertificateAuthority.shared.evaluate(trust, host: challenge.protectionSpace.host)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
