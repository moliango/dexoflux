import UIKit

/// Presents http(s) links in the in-app `WKWebView` browser.
///
/// When `AppSettings.openExternalLinksInAppBrowser` is off, falls back to the system browser.
/// Non-web schemes (`mailto:`, `tel:`, custom apps) always go to the system.
/// Forum session cookies are shared via `InAppBrowserWebKitRuntime` + `WebCookieStore`.
enum DoerSafariPresenter {
    /// Open `url` in the in-app browser when the setting is on; otherwise system browser.
    @MainActor
    static func present(
        url: URL,
        from host: UIViewController,
        api: DiscourseAPI,
        username: String? = nil
    ) {
        switch BrowserNavigationURLClassifier.classify(url) {
        case .web:
            break
        case .externalApp:
            UIApplication.shared.open(url)
            return
        case .internalWebKit, .invalid:
            return
        }

        guard AppSettings.shared.openExternalLinksInAppBrowser else {
            UIApplication.shared.open(url)
            return
        }

        let resolvedUsername = username ?? AuthManager.shared.username(for: api.baseURL)
        let browser = InAppBrowserViewController(
            api: api,
            username: resolvedUsername,
            initialURL: url
        )

        if let navigationController = host.navigationController {
            navigationController.pushViewController(browser, animated: true)
            return
        }

        let nav = UINavigationController(rootViewController: browser)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        host.present(nav, animated: true)
    }
}
