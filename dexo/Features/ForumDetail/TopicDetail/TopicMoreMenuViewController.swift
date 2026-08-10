import UIKit

/// FluxDo-style topic more menu: circular quick actions + list rows, themed for Dexo.
final class TopicMoreMenuViewController: UIViewController {
    struct Model {
        var isBookmarked: Bool
        var isInReadLater: Bool
        var notificationLevel: DiscourseTopicDetail.NotificationLevel?
        var hasActiveFilter: Bool
        var canEdit: Bool
        var showExport: Bool
    }

    enum Action: Equatable {
        case bookmark
        case readLater
        case notification
        case shareLink
        case filter
        case editTopic
        case shareImage
        case export
        case openBrowser
        case readingSettings
    }

    var onAction: ((Action) -> Void)?

    private let model: Model
    private let stack = UIStackView()

    init(model: Model) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        preferredContentSize = CGSize(width: 268, height: 420)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemGroupedBackground

        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10),
        ])

        stack.addArrangedSubview(makeQuickActionsRow())
        stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)

        var rows: [(Action, String, String)] = []
        if model.canEdit {
            rows.append((.editTopic, "pencil", String(localized: "topic.edit", defaultValue: "编辑话题")))
        }
        rows.append((.shareImage, "photo", String(localized: "topic.share_image", defaultValue: "生成分享图片")))
        if model.showExport {
            rows.append((.export, "square.and.arrow.down", String(localized: "topic.export", defaultValue: "导出文章")))
        }
        rows.append((.openBrowser, "globe", String(localized: "topic.open_browser", defaultValue: "在浏览器打开")))

        for (action, symbol, title) in rows {
            stack.addArrangedSubview(makeListRow(action: action, symbol: symbol, title: title))
        }

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.45)
        divider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        let dividerWrap = UIView()
        dividerWrap.translatesAutoresizingMaskIntoConstraints = false
        dividerWrap.addSubview(divider)
        NSLayoutConstraint.activate([
            dividerWrap.heightAnchor.constraint(equalToConstant: 17),
            divider.leadingAnchor.constraint(equalTo: dividerWrap.leadingAnchor, constant: 6),
            divider.trailingAnchor.constraint(equalTo: dividerWrap.trailingAnchor, constant: -6),
            divider.centerYAnchor.constraint(equalTo: dividerWrap.centerYAnchor),
        ])
        stack.addArrangedSubview(dividerWrap)

        stack.addArrangedSubview(
            makeListRow(
                action: .readingSettings,
                symbol: "book",
                title: String(localized: "topic.reading_settings", defaultValue: "阅读设置")
            )
        )

        // Fit height to content after layout.
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let height = stack.systemLayoutSizeFitting(
            CGSize(width: 268 - 20, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height + 22
        preferredContentSize = CGSize(width: 268, height: min(max(height, 280), 520))
    }

    // MARK: - Quick actions

    private func makeQuickActionsRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.translatesAutoresizingMaskIntoConstraints = false

        let accent = AppSettings.shared.themeStyle.accentColor
        let subscribed: Bool = {
            guard let level = model.notificationLevel else { return false }
            return level == .watching || level == .tracking
        }()

        let items: [(Action, String, String, Bool)] = [
            (
                .bookmark,
                model.isBookmarked ? "bookmark.fill" : "bookmark",
                model.isBookmarked
                    ? String(localized: "topic.bookmark.remove", defaultValue: "取消书签")
                    : String(localized: "topic.bookmark.add", defaultValue: "添加书签"),
                model.isBookmarked
            ),
            (
                .readLater,
                "square.stack.3d.up",
                model.isInReadLater
                    ? String(localized: "topic.read_later.remove", defaultValue: "移出稍后阅读")
                    : String(localized: "topic.read_later.add", defaultValue: "稍后阅读"),
                model.isInReadLater
            ),
            (
                .notification,
                notificationSymbol(for: model.notificationLevel),
                String(localized: "topic.notifications", defaultValue: "通知级别"),
                subscribed
            ),
            (
                .shareLink,
                "link",
                String(localized: "topic.share", defaultValue: "分享链接"),
                false
            ),
            (
                .filter,
                model.hasActiveFilter
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease",
                String(localized: "topic.filter", defaultValue: "筛选"),
                model.hasActiveFilter
            ),
        ]

        for (action, symbol, title, active) in items {
            row.addArrangedSubview(makeQuickButton(action: action, symbol: symbol, title: title, active: active, accent: accent))
        }

        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 2),
            row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -6),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -6),
            wrap.heightAnchor.constraint(equalToConstant: 52),
        ])
        return wrap
    }

    private func makeQuickButton(
        action: Action,
        symbol: String,
        title: String,
        active: Bool,
        accent: UIColor
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = title
        button.layer.cornerRadius = 18
        button.layer.cornerCurve = .continuous
        button.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.22, alpha: 1)
                : UIColor(white: 0.93, alpha: 1)
        }
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.tintColor = active ? accent : .label
        button.addAction(UIAction { [weak self] _ in
            self?.emit(action)
        }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
        return button
    }

    private func notificationSymbol(for level: DiscourseTopicDetail.NotificationLevel?) -> String {
        switch level {
        case .watching: return "bell.badge.fill"
        case .tracking: return "bell.fill"
        case .muted: return "bell.slash"
        case .regular, .none: return "bell"
        }
    }

    // MARK: - List rows

    private func makeListRow(action: Action, symbol: String, title: String) -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in
            self?.emit(action)
        }, for: .touchUpInside)

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .label
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textColor = .label

        button.addSubview(icon)
        button.addSubview(label)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            icon.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
        ])

        // Soft highlight
        button.configurationUpdateHandler = { btn in
            btn.backgroundColor = btn.isHighlighted
                ? UIColor.tertiarySystemFill
                : .clear
            btn.layer.cornerRadius = 10
        }
        return button
    }

    private func emit(_ action: Action) {
        dismiss(animated: true) { [weak self] in
            self?.onAction?(action)
        }
    }
}

// MARK: - Presenter

enum TopicMoreMenuPresenter {
    static func present(
        from host: UIViewController,
        barButtonItem: UIBarButtonItem?,
        model: TopicMoreMenuViewController.Model,
        onAction: @escaping (TopicMoreMenuViewController.Action) -> Void
    ) {
        let menu = TopicMoreMenuViewController(model: model)
        menu.onAction = onAction
        if let pop = menu.popoverPresentationController {
            pop.barButtonItem = barButtonItem
            pop.permittedArrowDirections = [.up, .down]
            pop.delegate = PassthroughPopoverDelegate.shared
            // Match card surface
            pop.backgroundColor = .secondarySystemGroupedBackground
        }
        host.present(menu, animated: true)
    }
}

/// Allows tap-outside dismiss while keeping adaptive popover on iPhone.
private final class PassthroughPopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    static let shared = PassthroughPopoverDelegate()

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}
