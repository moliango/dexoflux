import Foundation

@MainActor
final class NewAPICheckInRuntime {
    static let pluginID = "builtin.newapi-checkin"
    static let shared = NewAPICheckInRuntime(
        scope: PluginScope(baseURL: "https://linux.do", username: nil)
    )

    let store: NewAPICheckInStore
    let service: NewAPICheckInService

    init(
        scope: PluginScope,
        directoryURL: URL? = nil,
        credentialVault: NewAPICheckInCredentialVault = NewAPICheckInKeychainVault(),
        session: URLSession = .shared
    ) {
        let store = NewAPICheckInStore(
            scope: scope,
            directoryURL: directoryURL,
            credentialVault: credentialVault
        )
        self.store = store
        self.service = NewAPICheckInService(store: store, session: session)
    }

    func makeViewController() -> NewAPICheckInViewController {
        NewAPICheckInViewController(store: store, service: service)
    }
}
