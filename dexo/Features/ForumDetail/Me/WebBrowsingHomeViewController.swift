import UIKit

/// FluxDo「网页浏览」主页：地址栏 + 收藏 / 历史 / 下载入口。
final class WebBrowsingHomeViewController: UIViewController {
    private let api: DiscourseAPI
    private let username: String?
    private let store: BrowserHistoryStore

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let addressContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.85)
        view.layer.cornerRadius = 28
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let addressIcon: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "globe"))
        view.tintColor = .secondaryLabel
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let addressField: UITextField = {
        let field = UITextField()
        field.placeholder = String(localized: "me.browser.input_url", defaultValue: "输入网址")
        field.keyboardType = .URL
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .go
        field.font = .systemFont(ofSize: 16)
        field.clearButtonMode = .whileEditing
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let goButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.forward.circle.fill")
        config.baseForegroundColor = AppSettings.shared.themeStyle.accentColor
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let entriesCard: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let entriesStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let bookmarkSubtitleLabel = UILabel()
    private let historySubtitleLabel = UILabel()

    init(api: DiscourseAPI, username: String?, historyStore: BrowserHistoryStore? = nil) {
        self.api = api
        self.username = username
        self.store = historyStore ?? BrowserHistoryStore.shared(baseURL: api.baseURL, username: username)
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.browser.home", defaultValue: "网页浏览")
        view.backgroundColor = .systemGroupedBackground
        addressField.delegate = self
        goButton.addTarget(self, action: #selector(goTapped), for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        addressContainer.addSubview(addressIcon)
        addressContainer.addSubview(addressField)
        addressContainer.addSubview(goButton)
        entriesCard.addSubview(entriesStack)
        contentStack.addArrangedSubview(addressContainer)
        contentStack.addArrangedSubview(entriesCard)

        entriesStack.addArrangedSubview(
            makeEntryRow(
                symbol: "star.fill",
                tint: .systemOrange,
                title: String(localized: "me.browser.bookmarks", defaultValue: "收藏"),
                subtitleLabel: bookmarkSubtitleLabel,
                action: #selector(openBookmarks)
            )
        )
        entriesStack.addArrangedSubview(makeSeparator())
        entriesStack.addArrangedSubview(
            makeEntryRow(
                symbol: "clock.fill",
                tint: .systemPurple,
                title: String(localized: "me.browser.history", defaultValue: "浏览历史"),
                subtitleLabel: historySubtitleLabel,
                action: #selector(openHistory)
            )
        )
        entriesStack.addArrangedSubview(makeSeparator())
        let downloadSubtitle = UILabel()
        downloadSubtitle.font = .systemFont(ofSize: 13)
        downloadSubtitle.textColor = .secondaryLabel
        downloadSubtitle.text = String(localized: "me.browser.downloads.subtitle", defaultValue: "查看下载的文件")
        entriesStack.addArrangedSubview(
            makeEntryRow(
                symbol: "arrow.down.circle.fill",
                tint: .systemTeal,
                title: String(localized: "me.browser.downloads", defaultValue: "下载管理"),
                subtitleLabel: downloadSubtitle,
                action: #selector(openDownloads)
            )
        )

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),

            addressContainer.heightAnchor.constraint(equalToConstant: 56),
            addressIcon.leadingAnchor.constraint(equalTo: addressContainer.leadingAnchor, constant: 16),
            addressIcon.centerYAnchor.constraint(equalTo: addressContainer.centerYAnchor),
            addressIcon.widthAnchor.constraint(equalToConstant: 20),
            addressIcon.heightAnchor.constraint(equalToConstant: 20),
            goButton.trailingAnchor.constraint(equalTo: addressContainer.trailingAnchor, constant: -8),
            goButton.centerYAnchor.constraint(equalTo: addressContainer.centerYAnchor),
            goButton.widthAnchor.constraint(equalToConstant: 40),
            goButton.heightAnchor.constraint(equalToConstant: 40),
            addressField.leadingAnchor.constraint(equalTo: addressIcon.trailingAnchor, constant: 10),
            addressField.trailingAnchor.constraint(equalTo: goButton.leadingAnchor, constant: -4),
            addressField.centerYAnchor.constraint(equalTo: addressContainer.centerYAnchor),

            entriesStack.topAnchor.constraint(equalTo: entriesCard.topAnchor, constant: 4),
            entriesStack.leadingAnchor.constraint(equalTo: entriesCard.leadingAnchor),
            entriesStack.trailingAnchor.constraint(equalTo: entriesCard.trailingAnchor),
            entriesStack.bottomAnchor.constraint(equalTo: entriesCard.bottomAnchor, constant: -4),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.reload()
        refreshSubtitles()
    }

    private func refreshSubtitles() {
        let bookmarkCount = store.bookmarks.count
        bookmarkSubtitleLabel.text = String(
            format: String(localized: "me.browser.bookmark_count %d", defaultValue: "%d 个收藏"),
            bookmarkCount
        )
        historySubtitleLabel.text = String(localized: "me.browser.history.subtitle", defaultValue: "查看浏览过的网页")
    }

    private func makeSeparator() -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let line = UIView()
        line.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 56),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        return wrap
    }

    private func makeEntryRow(
        symbol: String,
        tint: UIColor,
        title: String,
        subtitleLabel: UILabel,
        action: Selector
    ) -> UIControl {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addTarget(self, action: action, for: .touchUpInside)

        let iconBg = UIView()
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.backgroundColor = tint.withAlphaComponent(0.14)
        iconBg.layer.cornerRadius = 10
        iconBg.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit

        control.addSubview(iconBg)
        iconBg.addSubview(icon)
        control.addSubview(titleLabel)
        control.addSubview(subtitleLabel)
        control.addSubview(chevron)

        NSLayoutConstraint.activate([
            control.heightAnchor.constraint(equalToConstant: 64),
            iconBg.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 14),
            iconBg.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 34),
            iconBg.heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconBg.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: control.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            chevron.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: control.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
        ])
        return control
    }

    @objc private func goTapped() {
        openInputURL()
    }

    private func openInputURL() {
        let text = addressField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        let candidate = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: candidate),
              BrowserHistoryStore.normalizedPageURL(url) != nil
        else {
            let alert = UIAlertController(
                title: nil,
                message: String(localized: "me.browser.invalid_url", defaultValue: "请输入有效网址。"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
            present(alert, animated: true)
            return
        }
        addressField.resignFirstResponder()
        openBrowser(url: url)
    }

    private func openBrowser(url: URL?) {
        let browser = InAppBrowserViewController(
            api: api,
            username: username,
            initialURL: url,
            historyStore: store
        )
        navigationController?.pushViewController(browser, animated: true)
    }

    @objc private func openBookmarks() {
        store.reload()
        refreshSubtitles()
        let library = BrowserLibraryViewController(
            store: store,
            initialSection: .bookmarks
        ) { [weak self] url in
            self?.openBrowser(url: url)
        }
        navigationController?.pushViewController(library, animated: true)
    }

    @objc private func openHistory() {
        store.reload()
        refreshSubtitles()
        let library = BrowserLibraryViewController(
            store: store,
            initialSection: .history
        ) { [weak self] url in
            self?.openBrowser(url: url)
        }
        navigationController?.pushViewController(library, animated: true)
    }

    @objc private func openDownloads() {
        let vc = BrowserDownloadsViewController()
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension WebBrowsingHomeViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        openInputURL()
        return true
    }
}

/// 下载管理（WKWebView 系统级下载入口占位，对齐 FluxDo 入口形态）。
final class BrowserDownloadsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.browser.downloads", defaultValue: "下载管理")
        view.backgroundColor = .systemGroupedBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "arrow.down.circle"))
        icon.tintColor = .tertiaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = String(localized: "me.browser.downloads.empty", defaultValue: "还没有下载记录")
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let hint = UILabel()
        hint.text = String(
            localized: "me.browser.downloads.hint",
            defaultValue: "网页内触发的下载由系统处理，文件可在「文件」App 中查看。"
        )
        hint.textColor = .tertiaryLabel
        hint.font = .systemFont(ofSize: 13)
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(hint)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }
}
