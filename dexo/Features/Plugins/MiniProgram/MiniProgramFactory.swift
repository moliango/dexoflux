import UIKit

/// First-party Me mini-program identity. Not registered in the plugin registry.
struct MiniProgramDescriptor: Hashable {
    let id: String
    let displayName: String
    let icon: MiniProgramIcon
    let categoryID: String
    let url: URL?

    init(record: MiniProgramRecord) {
        id = record.id
        displayName = record.displayName
        icon = record.icon
        categoryID = record.categoryID
        url = record.urlString.flatMap(URL.init(string:))
    }

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
        icon = .system(symbolName: "app.fill")
        categoryID = MiniProgramCategoryID.other
        url = nil
    }
}

enum MiniProgramFactory {
    /// Visible mini-programs from the global single-forum catalog.
    @MainActor
    static var firstPartyPrograms: [MiniProgramDescriptor] {
        MiniProgramStore.shared.visiblePrograms().map(MiniProgramDescriptor.init(record:))
    }

    @MainActor
    static func makeContent(
        for programID: String,
        api: DiscourseAPI,
        username: String?
    ) -> UIViewController? {
        switch programID {
        case MiniProgramID.metaverse:
            guard let username else { return nil }
            let root = MetaverseServicesViewController(api: api, username: username)
            let navigation = UINavigationController(rootViewController: root)
            navigation.setNavigationBarHidden(false, animated: false)
            return navigation
        case MiniProgramID.ldc:
            return makeBrowserHost(
                api: api,
                username: username,
                url: URL(string: "https://credit.linux.do/home")!
            )
        case MiniProgramID.cdk:
            return makeBrowserHost(
                api: api,
                username: username,
                url: URL(string: "https://cdk.linux.do/dashboard")!
            )
        case MiniProgramID.newAPICheckIn:
            // Tab bar root already embeds a UINavigationController per tab.
            return NewAPICheckInRuntime.shared.makeViewController()
        case MiniProgramID.ldcStore:
            return makeBrowserHost(
                api: api,
                username: username,
                url: URL(string: "https://ldcstore.com/")!
            )
        default:
            guard let record = MiniProgramStore.shared.program(id: programID),
                  record.isVisible,
                  let urlString = record.urlString,
                  let url = URL(string: urlString)
            else { return nil }
            return makeBrowserHost(api: api, username: username, url: url)
        }
    }

    @MainActor
    private static func makeBrowserHost(
        api: DiscourseAPI,
        username: String?,
        url: URL
    ) -> UIViewController {
        let browser = InAppBrowserViewController(
            api: api,
            username: username,
            initialURL: url,
            hidesHostTabBarAtRoot: false,
            hidesBrowserControlBar: true
        )
        // Browser can push history pages through its own navigationController.
        let navigation = UINavigationController(rootViewController: browser)
        navigation.setNavigationBarHidden(true, animated: false)
        return navigation
    }

    @MainActor
    static func present(
        program: MiniProgramDescriptor,
        from presenter: UIViewController,
        api: DiscourseAPI,
        username: String?
    ) {
        guard let content = makeContent(for: program.id, api: api, username: username) else { return }
        MiniProgramRecentStore.recordOpen(programID: program.id)
        // Opening a program full-screen replaces any existing float for the same session UX.
        if MiniProgramFloatingManager.shared.hasFloatedProgram {
            MiniProgramFloatingManager.shared.discard(animated: false)
        }
        let host = MiniProgramHostViewController(
            content: content,
            program: program,
            api: api,
            username: username,
            icon: icon(for: program.id)
        )
        host.modalPresentationStyle = .overFullScreen
        host.modalPresentationCapturesStatusBarAppearance = true
        // Present from the top-most VC so we never stack on a half-dismissed drawer
        // transition (that path used to assert / look like a crash offline).
        let anchor = topMostPresenter(from: presenter)
        guard anchor.presentedViewController == nil else {
            anchor.dismiss(animated: false) {
                anchor.present(host, animated: true)
            }
            return
        }
        anchor.present(host, animated: true)
    }

    @MainActor
    private static func topMostPresenter(from base: UIViewController) -> UIViewController {
        var top = base
        while let presented = top.presentedViewController {
            top = presented
        }
        if let nav = top as? UINavigationController, let visible = nav.visibleViewController {
            return topMostPresenter(from: visible)
        }
        if let tab = top as? UITabBarController, let selected = tab.selectedViewController {
            return topMostPresenter(from: selected)
        }
        return top
    }

    /// Best-effort public URL for「复制链接」. Built-ins without a web URL return nil.
    static func linkURL(for program: MiniProgramDescriptor) -> URL? {
        if let url = program.url { return url }
        if let record = MiniProgramStore.shared.program(id: program.id),
           let raw = record.urlString,
           let url = URL(string: raw) {
            return url
        }
        switch program.id {
        case MiniProgramID.ldc:
            return URL(string: "https://credit.linux.do/home")
        case MiniProgramID.cdk:
            return URL(string: "https://cdk.linux.do/dashboard")
        case MiniProgramID.ldcStore:
            return URL(string: "https://ldcstore.com/")
        default:
            return nil
        }
    }

    /// WeChat-style circular app icon used by drawer / host / float bubble.
    @MainActor
    static func icon(for programID: String, size: CGFloat = MiniProgramIconBadge.defaultSize) -> UIImage? {
        MiniProgramIconBadge.image(for: programID, size: size)
    }
}
