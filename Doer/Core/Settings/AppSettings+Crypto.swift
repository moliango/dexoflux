import Foundation

extension AppSettings {
    var cryptoRememberPassword: Bool {
        get { defaults.bool(forKey: "cryptoRememberPassword") }
        set {
            defaults.set(newValue, forKey: "cryptoRememberPassword")
            notifyChanged()
        }
    }

    var cryptoRecentAlgorithms: [String] {
        get { defaults.stringArray(forKey: "cryptoRecentAlgorithms") ?? [] }
        set {
            defaults.set(newValue, forKey: "cryptoRecentAlgorithms")
            notifyChanged()
        }
    }

    func rememberCryptoAlgorithm(_ id: String) {
        var next = [id] + cryptoRecentAlgorithms.filter { $0 != id }
        if next.count > 6 { next = Array(next.prefix(6)) }
        cryptoRecentAlgorithms = next
    }
}
