import Foundation
import UIKit

@MainActor
final class NewAPICheckInRuntime {
    static let pluginID = "builtin.newapi-checkin"
    static let shared = NewAPICheckInRuntime(
        scope: PluginScope(baseURL: "https://linux.do", username: nil)
    )

    private static let autoReloginDefaultsKey = "plugin.newapi.auto_relogin"

    /// 登录失效时是否自动打开登录页刷新 Cookie（默认开启，站点 Cookie 常几小时就过期）。
    static var autoReloginEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: autoReloginDefaultsKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoReloginDefaultsKey)
        }
    }

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

    /// Full mini-program root with bottom tabs (签到 / 自定义 / 历史 / 设置).
    func makeViewController() -> UIViewController {
        NewAPICheckInTabBarController(store: store, service: service)
    }
}
