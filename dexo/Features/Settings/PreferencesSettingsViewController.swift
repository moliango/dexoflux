import UIKit

final class PreferencesSettingsViewController: ObservableViewController {
    private let settings = AppSettings.shared

    private let clipboardRow = ReadingToggleRowView()
    private let autoOpenRow = ReadingToggleRowView()

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        return scroll
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 22
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 32, trailing: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        observe(settings)
        title = String(localized: "settings.preferences", defaultValue: "功能设置")
        view.backgroundColor = DataManagementPalette.screenBackground
        view.tintColor = settings.themeStyle.accentColor
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        clipboardRow.onValueChanged = { [weak self] isOn in
            self?.settings.clipboardTopicLinkPromptEnabled = isOn
            self?.refreshDataViews()
        }
        autoOpenRow.onValueChanged = { [weak self] isOn in
            self?.settings.autoOpenLastForum = isOn
            self?.refreshDataViews()
        }

        rebuildContent()
        refreshDataViews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        refreshDataViews()
    }

    override func updateUI() {
        title = String(localized: "settings.preferences", defaultValue: "功能设置")
        rebuildContent()
        refreshDataViews()
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let basic = UIStackView(arrangedSubviews: [clipboardRow, autoOpenRow])
        basic.axis = .vertical
        basic.spacing = 12
        contentStack.addArrangedSubview(makeSection(
            title: String(localized: "settings.preferences.section.basic", defaultValue: "基础"),
            symbolName: "slider.horizontal.3",
            body: basic
        ))
    }

    private func makeSection(title: String, symbolName: String, body: UIView) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 12
        section.translatesAutoresizingMaskIntoConstraints = false
        section.addArrangedSubview(
            DataManagementSectionHeaderView(
                title: title,
                symbolName: symbolName,
                tintColor: settings.themeStyle.accentColor
            )
        )
        section.addArrangedSubview(body)
        return section
    }

    private func refreshDataViews() {
        view.backgroundColor = DataManagementPalette.screenBackground
        view.tintColor = settings.themeStyle.accentColor
        let card = settings.themeStyle.topicCardBackgroundColor
        let accent = settings.themeStyle.accentColor

        clipboardRow.configure(
            title: String(localized: "settings.reading.clipboard_topic", defaultValue: "剪贴板话题链接"),
            subtitle: String(
                localized: "settings.reading.clipboard_topic.subtitle",
                defaultValue: "回到前台时提示打开复制的话题链接"
            ),
            symbolName: "doc.on.clipboard",
            isOn: settings.clipboardTopicLinkPromptEnabled,
            accentColor: accent,
            backgroundColor: card
        )
        autoOpenRow.configure(
            title: String(localized: "settings.auto_open_last_forum"),
            subtitle: String(
                localized: "settings.auto_open_last_forum.subtitle",
                defaultValue: "启动时直接进入上次打开的论坛"
            ),
            symbolName: "arrow.triangle.turn.up.right.circle",
            isOn: settings.autoOpenLastForum,
            accentColor: accent,
            backgroundColor: card
        )
    }
}
