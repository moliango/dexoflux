import UIKit

/// Topic more menu — compact popover with inline expansions (no bottom action sheets).
final class TopicMoreMenuViewController: UIViewController {
    struct Model {
        var isBookmarked: Bool
        var isInReadLater: Bool
        var notificationLevel: DiscourseTopicDetail.NotificationLevel?
        var hasActiveFilter: Bool
        var isFilteringByOP: Bool = false
        var isFilteringTopLevel: Bool = false
        var isNestedViewEnabled: Bool = false
        var canEdit: Bool
        var showExport: Bool
        var canAssign: Bool = false
        var assignedToUsername: String? = nil
    }

    enum Action: Equatable {
        case bookmark
        case readLater
        case shareLink
        case editTopic
        case shareImage
        case openBrowser
        case readingSettings
        case markUnreadStepBack
        case markUnreadClear
        case assignToMe
        case assignPickUser
        case unassign
        case filterOP
        case filterTopLevel
        case filterNested
        case filterClear
        case notification(DiscourseTopicDetail.NotificationLevel)
        case export(TopicExportFormat, TopicExportRange)
    }

    var onAction: ((Action) -> Void)?

    private let model: Model
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var expandedSection: ExpandedSection?
    private var expansionHost: UIStackView?

    private enum ExpandedSection: Equatable {
        case markUnread
        case assign
        case filter
        case notification
        case export
    }

    private var themeStyle: AppSettings.ThemeStyle { AppSettings.shared.themeStyle }
    private var accent: UIColor { themeStyle.accentColor }
    private var menuSurface: UIColor { themeStyle.topicCardBackgroundColor }
    private var menuCanvas: UIColor {
        UIColor { trait in
            let style = AppSettings.shared.themeStyle
            let card = style.topicCardBackgroundColor.resolvedColor(with: trait)
            let accent = style.accentColor.resolvedColor(with: trait)
            let wash = trait.userInterfaceStyle == .dark ? 0.10 : 0.06
            return TopicMoreMenuViewController.blend(card, onto: accent, alpha: wash)
        }
    }

    fileprivate static func blend(_ base: UIColor, onto tint: UIColor, alpha: CGFloat) -> UIColor {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        guard base.getRed(&br, green: &bg, blue: &bb, alpha: &ba),
              tint.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        else { return base }
        let a = min(max(alpha, 0), 1)
        return UIColor(
            red: br * (1 - a) + tr * a,
            green: bg * (1 - a) + tg * a,
            blue: bb * (1 - a) + tb * a,
            alpha: 1
        )
    }

    init(model: Model) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        preferredContentSize = CGSize(width: 280, height: 360)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = menuCanvas

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        rebuild()
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        expansionHost = nil

        stack.addArrangedSubview(makeQuickActionsRow())
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)

        // Content
        if model.canEdit {
            stack.addArrangedSubview(makeRow(
                symbol: "pencil",
                title: String(localized: "topic.edit", defaultValue: "编辑话题"),
                action: .editTopic
            ))
        }
        stack.addArrangedSubview(makeRow(
            symbol: "photo",
            title: String(localized: "topic.share_image", defaultValue: "生成分享图片"),
            action: .shareImage
        ))
        if model.showExport {
            stack.addArrangedSubview(makeExpandableRow(
                symbol: "square.and.arrow.down",
                title: String(localized: "topic.export", defaultValue: "导出话题"),
                section: .export,
                isActive: false
            ))
            if expandedSection == .export {
                stack.addArrangedSubview(makeExportPanel())
            }
        }
        stack.addArrangedSubview(makeRow(
            symbol: "safari",
            title: String(localized: "topic.open_browser", defaultValue: "在浏览器打开"),
            action: .openBrowser
        ))

        stack.addArrangedSubview(makeSectionDivider(title: String(localized: "topic.menu.section.reading", defaultValue: "阅读")))

        stack.addArrangedSubview(makeExpandableRow(
            symbol: "eye.slash",
            title: String(localized: "topic.mark_unread", defaultValue: "标记未读"),
            section: .markUnread,
            isActive: false
        ))
        if expandedSection == .markUnread {
            stack.addArrangedSubview(makeMarkUnreadPanel())
        }

        stack.addArrangedSubview(makeRow(
            symbol: "text.book.closed",
            title: String(localized: "topic.reading_settings", defaultValue: "阅读设置"),
            action: .readingSettings
        ))

        if model.canAssign {
            stack.addArrangedSubview(makeSectionDivider(title: String(localized: "topic.menu.section.assign", defaultValue: "指定")))
            let assignTitle: String = {
                if let name = model.assignedToUsername, !name.isEmpty {
                    return String(
                        format: String(localized: "topic.assign.current", defaultValue: "已指定 @%@"),
                        name
                    )
                }
                return String(localized: "topic.assign", defaultValue: "指定处理人")
            }()
            stack.addArrangedSubview(makeExpandableRow(
                symbol: "person.badge.plus",
                title: assignTitle,
                section: .assign,
                isActive: model.assignedToUsername != nil
            ))
            if expandedSection == .assign {
                stack.addArrangedSubview(makeAssignPanel())
            }
        }

        refitPreferredSize()
    }

    private func refitPreferredSize() {
        // Avoid layoutIfNeeded + systemLayoutSizeFitting recursion while rebuilding
        // the stack (can EXC_BAD_ACCESS on the stack). Estimate from arranged views.
        let width: CGFloat = 260
        var height: CGFloat = 20
        for view in stack.arrangedSubviews {
            let fitting = view.systemLayoutSizeFitting(
                CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            )
            height += max(fitting.height, 36) + stack.spacing
        }
        preferredContentSize = CGSize(width: 280, height: min(max(height, 200), 520))
    }

    private func toggleExpand(_ section: ExpandedSection) {
        if expandedSection == section {
            expandedSection = nil
        } else {
            expandedSection = section
        }
        // Rebuild outside an animation block to avoid mid-layout mutation crashes.
        rebuild()
    }

    // MARK: - Quick actions

    private func makeQuickActionsRow() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = menuSurface
        card.layer.cornerRadius = themeStyle.chromeCornerRadius + 2
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = accent.withAlphaComponent(0.14).cgColor
        card.layer.shadowColor = accent.cgColor
        card.layer.shadowOpacity = 0.08
        card.layer.shadowRadius = 10
        card.layer.shadowOffset = CGSize(width: 0, height: 4)

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalSpacing
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        let accent = self.accent
        let subscribed: Bool = {
            guard let level = model.notificationLevel else { return false }
            return level == .watching || level == .tracking
        }()

        let items: [(String, String, Bool, () -> Void)] = [
            (
                model.isBookmarked ? "bookmark.fill" : "bookmark",
                model.isBookmarked
                    ? String(localized: "topic.bookmark.remove", defaultValue: "取消书签")
                    : String(localized: "topic.bookmark.add", defaultValue: "添加书签"),
                model.isBookmarked,
                { [weak self] in self?.emit(.bookmark) }
            ),
            (
                "square.stack.3d.up",
                model.isInReadLater
                    ? String(localized: "topic.read_later.remove", defaultValue: "移出稍后阅读")
                    : String(localized: "topic.read_later.add", defaultValue: "稍后阅读"),
                model.isInReadLater,
                { [weak self] in self?.emit(.readLater) }
            ),
            (
                notificationSymbol(for: model.notificationLevel),
                String(localized: "topic.notifications", defaultValue: "通知"),
                subscribed,
                { [weak self] in self?.toggleExpand(.notification) }
            ),
            (
                "link",
                String(localized: "topic.share", defaultValue: "分享"),
                false,
                { [weak self] in self?.emit(.shareLink) }
            ),
            (
                model.hasActiveFilter
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease",
                String(localized: "topic.filter", defaultValue: "筛选"),
                model.hasActiveFilter,
                { [weak self] in self?.toggleExpand(.filter) }
            ),
        ]

        for (symbol, title, active, handler) in items {
            row.addArrangedSubview(makeQuickButton(symbol: symbol, title: title, active: active, accent: accent, handler: handler))
        }

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            card.heightAnchor.constraint(equalToConstant: 56),
        ])

        let wrap = UIStackView()
        wrap.axis = .vertical
        wrap.spacing = 6
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addArrangedSubview(card)

        if expandedSection == .notification {
            wrap.addArrangedSubview(makeNotificationPanel())
        }
        if expandedSection == .filter {
            wrap.addArrangedSubview(makeFilterPanel())
        }
        return wrap
    }

    private func makeQuickButton(
        symbol: String,
        title: String,
        active: Bool,
        accent: UIColor,
        handler: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = title
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.backgroundColor = active
            ? accent.withAlphaComponent(0.20)
            : accent.withAlphaComponent(0.08)
        button.layer.borderWidth = active ? 1 : 0
        button.layer.borderColor = accent.withAlphaComponent(0.28).cgColor
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        button.tintColor = active ? accent : accent.withAlphaComponent(0.85)
        button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
        ])
        return button
    }

    // MARK: - Rows

    private func makeRow(symbol: String, title: String, action: Action, destructive: Bool = false) -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in
            self?.emit(action)
        }, for: .touchUpInside)

        let tint = destructive ? UIColor.systemRed : accent
        let iconWell = makeIconWell(symbol: symbol, tint: tint)
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = destructive ? .systemRed : .label
        label.numberOfLines = 1

        button.addSubview(iconWell)
        button.addSubview(label)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            iconWell.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            iconWell.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6),
        ])
        let highlight = accent.withAlphaComponent(0.10)
        button.configurationUpdateHandler = { btn in
            btn.backgroundColor = btn.isHighlighted ? highlight : .clear
            btn.layer.cornerRadius = 12
            btn.layer.cornerCurve = .continuous
        }
        return button
    }

    private func makeExpandableRow(
        symbol: String,
        title: String,
        section: ExpandedSection,
        isActive: Bool
    ) -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .leading
        button.addAction(UIAction { [weak self] _ in
            self?.toggleExpand(section)
        }, for: .touchUpInside)

        let iconWell = makeIconWell(symbol: symbol, tint: isActive ? accent : accent.withAlphaComponent(0.85))
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .label

        let chevron = UIImageView(image: UIImage(systemName: expandedSection == section ? "chevron.up" : "chevron.down"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = accent.withAlphaComponent(0.55)
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        button.addSubview(iconWell)
        button.addSubview(label)
        button.addSubview(chevron)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            iconWell.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            iconWell.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            chevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -6),
            chevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        let highlight = accent.withAlphaComponent(0.10)
        button.configurationUpdateHandler = { btn in
            btn.backgroundColor = btn.isHighlighted ? highlight : .clear
            btn.layer.cornerRadius = 12
            btn.layer.cornerCurve = .continuous
        }
        return button
    }

    private func makeIconWell(symbol: String, tint: UIColor) -> UIView {
        let well = UIView()
        well.translatesAutoresizingMaskIntoConstraints = false
        well.backgroundColor = tint.withAlphaComponent(0.14)
        well.layer.cornerRadius = 8
        well.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        well.addSubview(icon)
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 28),
            well.heightAnchor.constraint(equalToConstant: 28),
            icon.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 15),
            icon.heightAnchor.constraint(equalToConstant: 15),
        ])
        return well
    }

    private func makeSectionDivider(title: String) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title.uppercased()
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = accent.withAlphaComponent(0.72)
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -4),
        ])
        return wrap
    }

    // MARK: - Inline panels (no bottom sheets)

    private func makeChipRow(items: [(String, Bool, () -> Void)]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false

        let accent = self.accent
        for (title, active, handler) in items {
            var config = UIButton.Configuration.filled()
            config.title = title
            config.cornerStyle = .capsule
            config.baseForegroundColor = active ? .white : accent
            config.baseBackgroundColor = active ? accent : accent.withAlphaComponent(0.12)
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = .systemFont(ofSize: 13, weight: .semibold)
                return out
            }
            let button = UIButton(configuration: config)
            button.addAction(UIAction { _ in handler() }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }

        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 2),
            row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -4),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -6),
            row.heightAnchor.constraint(equalToConstant: 34),
        ])
        return wrap
    }

    private func makeMarkUnreadPanel() -> UIView {
        makeChipRow(items: [
            (
                String(localized: "topic.mark_unread.step_back.short", defaultValue: "回退一层"),
                false,
                { [weak self] in self?.emit(.markUnreadStepBack) }
            ),
            (
                String(localized: "topic.mark_unread.clear.short", defaultValue: "清空进度"),
                false,
                { [weak self] in self?.emit(.markUnreadClear) }
            ),
        ])
    }

    private func makeAssignPanel() -> UIView {
        if model.assignedToUsername != nil {
            return makeChipRow(items: [
                (
                    String(localized: "topic.assign.clear", defaultValue: "取消指定"),
                    false,
                    { [weak self] in self?.emit(.unassign) }
                ),
            ])
        }
        return makeChipRow(items: [
            (
                String(localized: "topic.assign.to_me", defaultValue: "指定给我"),
                true,
                { [weak self] in self?.emit(.assignToMe) }
            ),
            (
                String(localized: "topic.assign.pick_user.short", defaultValue: "指定他人"),
                false,
                { [weak self] in self?.emit(.assignPickUser) }
            ),
        ])
    }

    private func makeFilterPanel() -> UIView {
        var items: [(String, Bool, () -> Void)] = [
            (
                String(localized: "topic.filter_op", defaultValue: "只看题主"),
                model.isFilteringByOP,
                { [weak self] in self?.emit(.filterOP) }
            ),
            (
                String(localized: "topic.filter_top_level", defaultValue: "只看顶层"),
                model.isFilteringTopLevel,
                { [weak self] in self?.emit(.filterTopLevel) }
            ),
            (
                String(localized: "topic.filter_nested", defaultValue: "树形"),
                model.isNestedViewEnabled,
                { [weak self] in self?.emit(.filterNested) }
            ),
        ]
        // FluxDo: cancel when any filter (including nested) is active.
        if model.hasActiveFilter {
            items.append((
                String(localized: "topic.filter_clear", defaultValue: "取消筛选"),
                false,
                { [weak self] in self?.emit(.filterClear) }
            ))
        }
        return makeChipRow(items: items)
    }

    private func makeNotificationPanel() -> UIView {
        let levels: [(DiscourseTopicDetail.NotificationLevel, String)] = [
            (.watching, String(localized: "topic.notification.watching", defaultValue: "关注")),
            (.tracking, String(localized: "topic.notification.tracking", defaultValue: "跟踪")),
            (.regular, String(localized: "topic.notification.regular", defaultValue: "正常")),
            (.muted, String(localized: "topic.notification.muted", defaultValue: "静音")),
        ]
        return makeChipRow(items: levels.map { level, title in
            (
                title,
                model.notificationLevel == level,
                { [weak self] in self?.emit(.notification(level)) }
            )
        })
    }

    private func makeExportPanel() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Common exports only — keeps the panel short.
        let commons: [(TopicExportFormat, TopicExportRange, String)] = [
            (.markdown, .loadedPosts, String(localized: "topic.export.md_all", defaultValue: "Markdown · 已加载")),
            (.markdown, .firstPost, String(localized: "topic.export.md_op", defaultValue: "Markdown · 仅主帖")),
            (.html, .loadedPosts, String(localized: "topic.export.html_all", defaultValue: "HTML · 已加载")),
        ]
        for (format, range, title) in commons {
            stack.addArrangedSubview(makeRow(
                symbol: format == .markdown ? "doc.plaintext" : "chevron.left.forwardslash.chevron.right",
                title: title,
                action: .export(format, range)
            ))
        }

        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: wrap.topAnchor),
            stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -4),
        ])
        return wrap
    }

    private func notificationSymbol(for level: DiscourseTopicDetail.NotificationLevel?) -> String {
        switch level {
        case .watching: return "bell.badge.fill"
        case .tracking: return "bell.fill"
        case .muted: return "bell.slash"
        case .regular, .none: return "bell"
        }
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
            pop.permittedArrowDirections = [.up]
            pop.delegate = PassthroughPopoverDelegate.shared
            pop.backgroundColor = UIColor { trait in
                let style = AppSettings.shared.themeStyle
                let card = style.topicCardBackgroundColor.resolvedColor(with: trait)
                let accent = style.accentColor.resolvedColor(with: trait)
                let wash = trait.userInterfaceStyle == .dark ? 0.10 : 0.06
                return TopicMoreMenuViewController.blend(card, onto: accent, alpha: wash)
            }
        }
        host.present(menu, animated: true)
    }
}

private final class PassthroughPopoverDelegate: NSObject, UIPopoverPresentationControllerDelegate {
    static let shared = PassthroughPopoverDelegate()

    func adaptivePresentationStyle(
        for controller: UIPresentationController,
        traitCollection: UITraitCollection
    ) -> UIModalPresentationStyle {
        .none
    }
}
