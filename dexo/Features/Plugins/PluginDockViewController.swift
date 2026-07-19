import UIKit

private final class PluginDockPassthroughView: UIView {
    var activeEdge: UIRectEdge = .right
    var edgeGestureWidth: CGFloat = 22

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0.01 {
            let localPoint = subview.convert(point, from: self)
            if subview.point(inside: localPoint, with: event) {
                return true
            }
        }

        if activeEdge == .left {
            return point.x <= edgeGestureWidth
        }
        return point.x >= bounds.width - edgeGestureWidth
    }
}

@MainActor
final class PluginDockViewController: UIViewController {
    private enum PluginKind: String {
        case newAPI
        case ldcStore
    }

    private let api: DiscourseAPI
    private let username: String?
    private let settings = AppSettings.shared
    private let registry = DexoPluginRuntime.shared.registry
    private var settingsObservationToken: NSObjectProtocol?
    private var pluginStateObservationToken: NSObjectProtocol?
    private var handleCenterYConstraint: NSLayoutConstraint?
    private var handleLeadingConstraint: NSLayoutConstraint?
    private var handleTrailingConstraint: NSLayoutConstraint?
    private var menuLeadingConstraint: NSLayoutConstraint?
    private var menuTrailingConstraint: NSLayoutConstraint?
    private var edgeGesture: UIScreenEdgePanGestureRecognizer?
    private var activeWindow: PluginWindowContainerViewController?
    private var cachedWindows: [PluginKind: PluginWindowContainerViewController] = [:]

    private let handleButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.78)
        button.tintColor = AppSettings.shared.themeStyle.accentColor
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1.0 / UIScreen.main.scale
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.52).cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.14
        button.layer.shadowRadius = 14
        button.layer.shadowOffset = CGSize(width: 0, height: 6)
        button.setImage(
            UIImage(systemName: "square.stack.3d.up.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)),
            for: .normal
        )
        button.accessibilityLabel = String(localized: "plugin.dock.open", defaultValue: "打开插件 Dock")
        return button
    }()

    private let menuView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 22
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.30).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.18
        view.layer.shadowRadius = 20
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.clipsToBounds = false
        view.alpha = 0
        view.isHidden = true
        return view
    }()

    private let menuStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }()

    init(api: DiscourseAPI, username: String?) {
        self.api = api
        self.username = username
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = PluginDockPassthroughView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(menuView)
        menuView.contentView.addSubview(menuStack)
        view.addSubview(handleButton)

        handleCenterYConstraint = handleButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            handleButton.widthAnchor.constraint(equalToConstant: 44),
            handleButton.heightAnchor.constraint(equalToConstant: 44),
            handleCenterYConstraint!,
            menuView.widthAnchor.constraint(equalToConstant: 230),
            menuView.centerYAnchor.constraint(equalTo: handleButton.centerYAnchor),
            menuStack.topAnchor.constraint(equalTo: menuView.contentView.topAnchor, constant: 12),
            menuStack.leadingAnchor.constraint(equalTo: menuView.contentView.leadingAnchor, constant: 12),
            menuStack.trailingAnchor.constraint(equalTo: menuView.contentView.trailingAnchor, constant: -12),
            menuStack.bottomAnchor.constraint(equalTo: menuView.contentView.bottomAnchor, constant: -12),
        ])

        handleButton.addTarget(self, action: #selector(handleTapped), for: .touchUpInside)
        handleButton.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePanned(_:))))
        rebuildMenu()
        observeSettings()
        observePluginState()
        applySettings(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateHandleVerticalPosition()
    }

    deinit {
        if let settingsObservationToken {
            NotificationCenter.default.removeObserver(settingsObservationToken)
        }
        if let pluginStateObservationToken {
            NotificationCenter.default.removeObserver(pluginStateObservationToken)
        }
    }

    private var scope: PluginScope {
        PluginScope(baseURL: api.baseURL, username: username)
    }

    private func observeSettings() {
        settingsObservationToken = NotificationCenter.default.addObserver(
            forName: DexoObservableObject.didChangeNotification,
            object: settings,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applySettings(animated: true)
            }
        }
    }

    private func observePluginState() {
        pluginStateObservationToken = NotificationCenter.default.addObserver(
            forName: PluginStateStore.stateDidChangeNotification,
            object: DexoPluginRuntime.shared.stateStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pluginStateDidChange()
            }
        }
    }

    private func pluginStateDidChange() {
        rebuildMenu()
        closeDisabledCachedWindows()
    }

    private func applySettings(animated: Bool) {
        let enabled = settings.pluginDockEnabled
        view.isHidden = !enabled
        view.isUserInteractionEnabled = enabled
        if !enabled {
            setMenuVisible(false, animated: false)
            hideActiveWindowImmediately()
            edgeGesture?.isEnabled = false
            return
        }

        installEdgeGesture()
        edgeGesture?.isEnabled = true
        applyDockSide(animated: animated)
        updateHandleVerticalPosition()
        rebuildMenu()
        handleButton.tintColor = settings.themeStyle.accentColor
    }

    private func installEdgeGesture() {
        edgeGesture?.view?.removeGestureRecognizer(edgeGesture!)
        let gesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned(_:)))
        gesture.edges = settings.pluginDockSide == .left ? .left : .right
        view.addGestureRecognizer(gesture)
        edgeGesture = gesture
    }

    private func applyDockSide(animated: Bool) {
        handleLeadingConstraint?.isActive = false
        handleTrailingConstraint?.isActive = false
        menuLeadingConstraint?.isActive = false
        menuTrailingConstraint?.isActive = false
        (view as? PluginDockPassthroughView)?.activeEdge = settings.pluginDockSide == .left ? .left : .right
        if settings.pluginDockSide == .left {
            handleLeadingConstraint = handleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -8)
            handleLeadingConstraint?.isActive = true
            menuLeadingConstraint = menuView.leadingAnchor.constraint(equalTo: handleButton.trailingAnchor, constant: 10)
            menuLeadingConstraint?.isActive = true
        } else {
            handleTrailingConstraint = handleButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 8)
            handleTrailingConstraint?.isActive = true
            menuTrailingConstraint = menuView.trailingAnchor.constraint(equalTo: handleButton.leadingAnchor, constant: -10)
            menuTrailingConstraint?.isActive = true
        }
        let updates = { self.view.layoutIfNeeded() }
        animated ? UIView.animate(withDuration: 0.2, animations: updates) : updates()
    }

    private func updateHandleVerticalPosition() {
        let safeFrame = view.safeAreaLayoutGuide.layoutFrame
        guard safeFrame.height > 64 else { return }
        let minY = safeFrame.minY + 42
        let maxY = safeFrame.maxY - 42
        let y = minY + CGFloat(settings.pluginDockVerticalPosition) * (maxY - minY)
        handleCenterYConstraint?.constant = y - safeFrame.minY
    }

    private func rebuildMenu() {
        menuStack.arrangedSubviews.forEach { view in
            menuStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if registry.isPluginEnabled(BuiltInPluginID.newAPICheckIn, for: scope) {
            menuStack.addArrangedSubview(makeMenuButton(
                title: String(localized: "plugins.newapi.title", defaultValue: "NewAPI 签到"),
                subtitle: String(localized: "plugin.dock.newapi.subtitle", defaultValue: "管理账号并执行签到"),
                image: UIImage(systemName: "checkmark.circle.fill")
            ) { [weak self] in self?.openPlugin(.newAPI) })
        }
        if registry.isPluginEnabled(BuiltInPluginID.ldcStore, for: scope) {
            menuStack.addArrangedSubview(makeMenuButton(
                title: String(localized: "plugins.ldc_store.title", defaultValue: "LD 士多"),
                subtitle: String(localized: "plugin.dock.ldc_store.subtitle", defaultValue: "在独立窗口中浏览"),
                image: UIImage(named: "LDStoreLogo") ?? UIImage(systemName: "shippingbox.fill")
            ) { [weak self] in self?.openPlugin(.ldcStore) })
        }
    }

    private func closeDisabledCachedWindows() {
        if !registry.isPluginEnabled(BuiltInPluginID.newAPICheckIn, for: scope) {
            closeCachedWindow(.newAPI)
        }
        if !registry.isPluginEnabled(BuiltInPluginID.ldcStore, for: scope) {
            closeCachedWindow(.ldcStore)
        }
    }

    private func closeCachedWindow(_ kind: PluginKind) {
        guard let window = cachedWindows.removeValue(forKey: kind) else { return }
        hideWindow(window, preserving: false, animated: false)
    }

    private func makeMenuButton(title: String, subtitle: String, image: UIImage?, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.subtitle = subtitle
        configuration.image = image
        configuration.imagePadding = 12
        configuration.titleAlignment = .leading
        configuration.baseForegroundColor = settings.themeStyle.accentColor
        configuration.background.cornerRadius = 15
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 62).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    @objc private func handleTapped() {
        setMenuVisible(menuView.isHidden, animated: true)
    }

    @objc private func edgePanned(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard activeWindow == nil else { return }
        let translation = gesture.translation(in: view)
        let inward = settings.pluginDockSide == .left ? translation.x : -translation.x
        if gesture.state == .ended, inward > 52 {
            setMenuVisible(true, animated: true)
        }
    }

    @objc private func handlePanned(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        switch gesture.state {
        case .changed:
            let safeFrame = view.safeAreaLayoutGuide.layoutFrame
            let y = min(max(location.y, safeFrame.minY + 42), safeFrame.maxY - 42)
            handleCenterYConstraint?.constant = y - safeFrame.minY
            view.layoutIfNeeded()
        case .ended, .cancelled:
            let safeFrame = view.safeAreaLayoutGuide.layoutFrame
            let minY = safeFrame.minY + 42
            let maxY = safeFrame.maxY - 42
            let y = min(max(location.y, minY), maxY)
            settings.pluginDockVerticalPosition = Double((y - minY) / max(maxY - minY, 1))
            settings.pluginDockSide = location.x < view.bounds.midX ? .left : .right
            installEdgeGesture()
            applyDockSide(animated: true)
        default:
            break
        }
    }

    private func setMenuVisible(_ visible: Bool, animated: Bool) {
        if visible {
            menuView.isHidden = false
            menuView.alpha = 0
            menuView.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }
        let updates = {
            self.menuView.alpha = visible ? 1 : 0
            self.menuView.transform = visible ? .identity : CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
        let completion: (Bool) -> Void = { _ in
            if !visible { self.menuView.isHidden = true }
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.2, animations: updates, completion: completion)
        } else {
            updates()
            completion(true)
        }
    }

    private func openPlugin(_ kind: PluginKind) {
        setMenuVisible(false, animated: true)
        let window = cachedWindows[kind] ?? makeWindow(for: kind)
        cachedWindows[kind] = window
        showWindow(window)
    }

    private func makeWindow(for kind: PluginKind) -> PluginWindowContainerViewController {
        let content: UIViewController
        switch kind {
        case .newAPI:
            content = UINavigationController(rootViewController: NewAPICheckInRuntime.shared.makeViewController())
        case .ldcStore:
            let browser = InAppBrowserViewController(
                api: api,
                username: username,
                initialURL: URL(string: "https://ldcstore.com/"),
                hidesHostTabBarAtRoot: false,
                hidesBrowserControlBar: true
            )
            content = UINavigationController(rootViewController: browser)
        }
        let window = PluginWindowContainerViewController(content: content)
        window.onMinimize = { [weak self, weak window] in
            guard let self, let window else { return }
            hideWindow(window, preserving: true)
        }
        window.onClose = { [weak self, weak window] in
            guard let self, let window else { return }
            hideWindow(window, preserving: false)
            cachedWindows[kind] = nil
        }
        return window
    }

    private func showWindow(_ window: PluginWindowContainerViewController) {
        if let activeWindow, activeWindow !== window {
            hideWindow(activeWindow, preserving: true)
        }
        activeWindow = window
        if window.parent == nil {
            addChild(window)
            view.addSubview(window.view)
            window.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                window.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 22),
                window.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                window.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                window.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            ])
            window.didMove(toParent: self)
        } else if window.view.superview == nil {
            view.addSubview(window.view)
        }
        window.view.isHidden = false
        view.bringSubviewToFront(window.view)
        handleButton.isHidden = true
        window.view.alpha = 0
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.18) {
                window.view.alpha = 1
            }
        } else {
            window.view.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.25,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                window.view.alpha = 1
                window.view.transform = .identity
            }
        }
    }

    private func minimizeActiveWindow() {
        guard let activeWindow else { return }
        hideWindow(activeWindow, preserving: true)
    }

    private func hideActiveWindowImmediately() {
        guard let activeWindow else { return }
        hideWindow(activeWindow, preserving: true, animated: false)
    }

    private func hideWindow(
        _ window: PluginWindowContainerViewController,
        preserving: Bool,
        animated: Bool = true
    ) {
        let completion: (Bool) -> Void = { _ in
            if preserving {
                window.view.isHidden = true
            } else {
                window.willMove(toParent: nil)
                window.view.removeFromSuperview()
                window.removeFromParent()
            }
            if self.activeWindow === window { self.activeWindow = nil }
            self.handleButton.isHidden = !self.settings.pluginDockEnabled || self.activeWindow != nil
        }
        let updates = {
            window.view.alpha = 0
            window.view.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        }
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.18, animations: updates, completion: completion)
        } else {
            updates()
            completion(true)
        }
    }
}

@MainActor
private final class PluginWindowContainerViewController: UIViewController {
    var onMinimize: (() -> Void)?
    var onClose: (() -> Void)?

    private let content: UIViewController

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.layer.cornerRadius = 28
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.20
        view.layer.shadowRadius = 30
        view.layer.shadowOffset = CGSize(width: 0, height: 14)

        let chrome = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        chrome.translatesAutoresizingMaskIntoConstraints = false
        chrome.layer.cornerRadius = 28
        chrome.layer.cornerCurve = .continuous
        chrome.layer.borderWidth = 1.0 / UIScreen.main.scale
        chrome.layer.borderColor = UIColor.white.withAlphaComponent(0.48).cgColor
        chrome.clipsToBounds = true

        let minimize = makeHeaderButton(
            systemName: "minus",
            accessibilityLabel: String(localized: "plugin.window.minimize", defaultValue: "最小化插件窗口"),
            action: #selector(minimizeTapped)
        )
        let close = makeHeaderButton(
            systemName: "xmark",
            accessibilityLabel: String(localized: "plugin.window.close", defaultValue: "关闭插件窗口"),
            action: #selector(closeTapped)
        )

        let contentContainer = UIView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.backgroundColor = .systemBackground
        contentContainer.layer.cornerRadius = 18
        contentContainer.layer.cornerCurve = .continuous
        contentContainer.layer.borderWidth = 1.0 / UIScreen.main.scale
        contentContainer.layer.borderColor = UIColor.separator.withAlphaComponent(0.22).cgColor
        contentContainer.clipsToBounds = true

        view.addSubview(chrome)
        chrome.contentView.addSubview(contentContainer)
        chrome.contentView.addSubview(minimize)
        chrome.contentView.addSubview(close)
        addChild(content)
        contentContainer.addSubview(content.view)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        content.didMove(toParent: self)

        NSLayoutConstraint.activate([
            chrome.topAnchor.constraint(equalTo: view.topAnchor),
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            close.topAnchor.constraint(equalTo: chrome.contentView.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: chrome.contentView.trailingAnchor, constant: -9),
            close.widthAnchor.constraint(equalToConstant: 36),
            close.heightAnchor.constraint(equalToConstant: 36),
            minimize.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -6),
            minimize.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            minimize.widthAnchor.constraint(equalToConstant: 36),
            minimize.heightAnchor.constraint(equalToConstant: 36),
            contentContainer.topAnchor.constraint(equalTo: chrome.contentView.topAnchor, constant: 52),
            contentContainer.leadingAnchor.constraint(equalTo: chrome.contentView.leadingAnchor, constant: 10),
            contentContainer.trailingAnchor.constraint(equalTo: chrome.contentView.trailingAnchor, constant: -10),
            contentContainer.bottomAnchor.constraint(equalTo: chrome.contentView.bottomAnchor, constant: -10),
            content.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            content.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private func makeHeaderButton(systemName: String, accessibilityLabel: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
            for: .normal
        )
        button.tintColor = .label
        button.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.82)
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.layer.borderWidth = 1.0 / UIScreen.main.scale
        button.layer.borderColor = UIColor.separator.withAlphaComponent(0.18).cgColor
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func minimizeTapped() { onMinimize?() }
    @objc private func closeTapped() { onClose?() }
}
