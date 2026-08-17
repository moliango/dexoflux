import UIKit

final class RelatedLinksCardView: UIView {
    var onTapURL: ((URL) -> Void)?

    private let links: [RelatedLink]
    private let baseURL: String
    private var isExpanded = AppSettings.shared.defaultExpandRelatedLinks
    private var showsAllLinks = false

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let linksStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let chevronView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.down"))
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    init?(linkCounts: [DiscourseTopicDetail.LinkCount], baseURL: String) {
        let filtered = Self.makeRelatedLinks(from: linkCounts)
        guard !filtered.isEmpty else { return nil }
        self.links = filtered
        self.baseURL = baseURL
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .tertiarySystemGroupedBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        clipsToBounds = true

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        stackView.addArrangedSubview(makeHeader())
        stackView.addArrangedSubview(linksStackView)
        chevronView.transform = isExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        rebuildLinks()
    }

    private func makeHeader() -> UIView {
        let accentColor = AppSettings.shared.themeStyle.accentColor
        let button = UIButton(type: .system)
        button.tintColor = .label
        button.contentHorizontalAlignment = .fill
        button.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)

        let iconView = UIImageView(image: UIImage(systemName: "link"))
        iconView.tintColor = accentColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = String(localized: "post.related_links")
        titleLabel.font = TopicDetailTypography.interfaceFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = accentColor

        let countLabel = UILabel()
        countLabel.text = "\(links.count)"
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = accentColor
        countLabel.textAlignment = .center
        countLabel.backgroundColor = accentColor.withAlphaComponent(0.12)
        countLabel.layer.cornerRadius = 8
        countLabel.clipsToBounds = true
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleStack = UIStackView(arrangedSubviews: [iconView, titleLabel, countLabel])
        titleStack.axis = .horizontal
        titleStack.spacing = 8
        titleStack.alignment = .center
        titleStack.isUserInteractionEnabled = false
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        button.addSubview(titleStack)
        button.addSubview(chevronView)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            countLabel.heightAnchor.constraint(equalToConstant: 18),

            titleStack.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
            titleStack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            titleStack.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -10),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -8),

            chevronView.centerYAnchor.constraint(equalTo: titleStack.centerYAnchor),
            chevronView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            chevronView.widthAnchor.constraint(equalToConstant: 16),
            chevronView.heightAnchor.constraint(equalToConstant: 16),
        ])

        return button
    }

    private func rebuildLinks() {
        linksStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        linksStackView.isHidden = !isExpanded
        guard isExpanded else { return }

        let separator = UIView()
        separator.backgroundColor = UIColor.separator.withAlphaComponent(0.45)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        linksStackView.addArrangedSubview(separator)

        let maxVisibleLinks = 5
        let visibleLinks = showsAllLinks ? links : Array(links.prefix(maxVisibleLinks))
        for link in visibleLinks {
            linksStackView.addArrangedSubview(makeLinkRow(link))
        }

        if links.count > maxVisibleLinks, !showsAllLinks {
            let remaining = links.count - maxVisibleLinks
            let button = UIButton(type: .system)
            button.addAction(UIAction { [weak self] _ in
                self?.showsAllLinks = true
                self?.rebuildLinks()
                self?.invalidateTableHeight()
            }, for: .touchUpInside)

            let label = UILabel()
            label.text = String.localizedStringWithFormat(String(localized: "post.more_links %lld"), Int64(remaining))
            label.font = TopicDetailTypography.interfaceFont(ofSize: 12, weight: .medium)
            label.textColor = AppSettings.shared.themeStyle.accentColor
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false

            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
                label.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
                label.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -10),
            ])
            linksStackView.addArrangedSubview(button)
        }
    }

    private func makeLinkRow(_ link: RelatedLink) -> UIView {
        let button = UIButton(type: .system)
        button.tintColor = .label
        button.contentHorizontalAlignment = .fill
        button.addAction(UIAction { [weak self] _ in
            guard let url = self?.resolvedURL(for: link.url) else { return }
            self?.onTapURL?(url)
        }, for: .touchUpInside)

        let iconView = UIImageView(image: UIImage(systemName: "arrow.turn.down.right"))
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = link.title
        titleLabel.font = TopicDetailTypography.interfaceFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = AppSettings.shared.themeStyle.accentColor
        titleLabel.numberOfLines = 2

        let clickLabel = UILabel()
        clickLabel.text = Self.formatClicks(link.clicks)
        clickLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        clickLabel.textColor = .secondaryLabel
        clickLabel.textAlignment = .center
        clickLabel.backgroundColor = .secondarySystemFill
        clickLabel.layer.cornerRadius = 7
        clickLabel.clipsToBounds = true
        clickLabel.isHidden = link.clicks <= 0
        clickLabel.translatesAutoresizingMaskIntoConstraints = false

        let outwardView = UIImageView(image: UIImage(systemName: "arrow.up.forward"))
        outwardView.tintColor = .tertiaryLabel
        outwardView.contentMode = .scaleAspectFit
        outwardView.translatesAutoresizingMaskIntoConstraints = false

        let rowStack = UIStackView(arrangedSubviews: [iconView, titleLabel, clickLabel, outwardView])
        rowStack.axis = .horizontal
        rowStack.spacing = 8
        rowStack.alignment = .center
        rowStack.isUserInteractionEnabled = false
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(rowStack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            clickLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            clickLabel.heightAnchor.constraint(equalToConstant: 18),
            outwardView.widthAnchor.constraint(equalToConstant: 14),
            outwardView.heightAnchor.constraint(equalToConstant: 14),

            rowStack.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
            rowStack.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -12),
            rowStack.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -10),
        ])

        return button
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
        UIView.animate(withDuration: 0.2) {
            self.chevronView.transform = self.isExpanded ? CGAffineTransform(rotationAngle: .pi) : .identity
        }
        rebuildLinks()
        invalidateTableHeight()
    }

    private func invalidateTableHeight() {
        setNeedsLayout()
        layoutIfNeeded()
        var view: UIView? = superview
        while let current = view {
            if let tableView = current as? UITableView {
                tableView.doer_invalidateSelfSizingRows()
                return
            }
            view = current.superview
        }
    }

    private func resolvedURL(for rawURL: String) -> URL? {
        if let url = URL(string: rawURL), url.scheme != nil {
            return url
        }
        return URL(string: rawURL, relativeTo: URL(string: baseURL))?.absoluteURL
    }

    private static func makeRelatedLinks(from linkCounts: [DiscourseTopicDetail.LinkCount]) -> [RelatedLink] {
        var seen = Set<String>()
        var links: [RelatedLink] = []

        for linkCount in linkCounts {
            guard linkCount.internalLink,
                  linkCount.reflection,
                  !linkCount.url.isEmpty,
                  let title = linkCount.title,
                  !title.isEmpty
            else { continue }

            let key = "\(title.lowercased())|\(linkCount.url.lowercased())"
            guard seen.insert(key).inserted else { continue }
            links.append(RelatedLink(title: title, url: linkCount.url, clicks: linkCount.clicks))
        }

        return links
    }

    private static func formatClicks(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000)
        }
        return "\(count)"
    }
}

private struct RelatedLink: Hashable {
    let title: String
    let url: String
    let clicks: Int
}

/// FluxDo-style topic recommendations shown after the last post.
/// The footer is frame-sized by its table view; it never fits itself recursively.
final class SuggestedTopicsFooterView: UIView {
    var onSelectTopic: ((Int) -> Void)?
    var onBrowseCategory: ((Int, String) -> Void)?

    private enum Selection {
        case related
        case suggested
    }

    private let filterStack = UIStackView()
    private let topicsStack = UIStackView()
    private let browseButton = UIButton(type: .system)
    private var relatedButton: UIButton?
    private var suggestedButton: UIButton?
    private var rows: [SuggestedTopicRowControl] = []
    private var relatedTopics: [DiscourseTopicDetail.SuggestedTopic] = []
    private var suggestedTopics: [DiscourseTopicDetail.SuggestedTopic] = []
    private var selection: Selection = .related
    private var baseURL = ""
    private var categoryId: Int?
    private var categoryName: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.flexibleWidth]
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear

        filterStack.axis = .horizontal
        filterStack.alignment = .center
        filterStack.spacing = 6
        filterStack.translatesAutoresizingMaskIntoConstraints = false

        topicsStack.axis = .vertical
        topicsStack.spacing = 0
        topicsStack.translatesAutoresizingMaskIntoConstraints = false

        var browseConfiguration = UIButton.Configuration.plain()
        browseConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        browseButton.configuration = browseConfiguration
        browseButton.contentHorizontalAlignment = .leading
        browseButton.titleLabel?.adjustsFontForContentSizeCategory = true
        browseButton.addTarget(self, action: #selector(browseCategory), for: .touchUpInside)
        browseButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(filterStack)
        addSubview(topicsStack)
        addSubview(browseButton)
        NSLayoutConstraint.activate([
            filterStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            filterStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            filterStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            filterStack.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),

            topicsStack.topAnchor.constraint(equalTo: filterStack.bottomAnchor, constant: 8),
            topicsStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            topicsStack.trailingAnchor.constraint(equalTo: trailingAnchor),

            browseButton.topAnchor.constraint(equalTo: topicsStack.bottomAnchor, constant: 6),
            browseButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            browseButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            browseButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    func configure(
        relatedTopics: [DiscourseTopicDetail.SuggestedTopic],
        suggestedTopics: [DiscourseTopicDetail.SuggestedTopic],
        baseURL: String,
        categoryId: Int? = nil,
        categoryName: String? = nil
    ) {
        self.relatedTopics = Array(relatedTopics.prefix(6))
        self.suggestedTopics = Array(suggestedTopics.prefix(6))
        self.baseURL = baseURL
        self.categoryId = categoryId
        self.categoryName = categoryName

        let hasRelated = !self.relatedTopics.isEmpty
        let hasSuggested = !self.suggestedTopics.isEmpty
        guard hasRelated || hasSuggested else {
            isHidden = true
            return
        }
        isHidden = false
        if selection == .related, !hasRelated { selection = .suggested }
        if selection == .suggested, !hasSuggested { selection = .related }

        rebuildFilters()
        rebuildTopics()
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard !isHidden, width > 0 else { return 0 }
        let available = max(width, 1)
        let rowsHeight = rows.reduce(CGFloat.zero) { $0 + $1.preferredHeight(forWidth: available) }
        let browseHeight: CGFloat = categoryId != nil && categoryName != nil ? 40 : 0
        return 12 + 38 + 8 + rowsHeight + (rows.isEmpty ? 0 : 6) + browseHeight + 8
    }

    private func rebuildFilters() {
        filterStack.arrangedSubviews.forEach {
            filterStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        relatedButton = nil
        suggestedButton = nil

        if !relatedTopics.isEmpty {
            let button = makeFilterButton(
                title: String(localized: "topic.related.title", defaultValue: "相关话题"),
                symbolName: "sparkles",
                selected: selection == .related,
                action: #selector(selectRelated)
            )
            relatedButton = button
            filterStack.addArrangedSubview(button)
        }
        if !suggestedTopics.isEmpty {
            let button = makeFilterButton(
                title: String(localized: "topic.recommended.title", defaultValue: "建议话题"),
                symbolName: nil,
                selected: selection == .suggested,
                action: #selector(selectSuggested)
            )
            suggestedButton = button
            filterStack.addArrangedSubview(button)
        }

        let theme = AppSettings.shared.themeStyle
        let browseTitle: String
        if let categoryName, categoryId != nil {
            browseTitle = String.localizedStringWithFormat(
                String(localized: "topic.browse.category", defaultValue: "想阅读更多？浏览 %@ 分类"),
                categoryName
            )
            browseButton.isHidden = false
        } else {
            browseTitle = ""
            browseButton.isHidden = true
        }
        browseButton.setTitle(browseTitle, for: .normal)
        browseButton.setTitleColor(theme.accentColor, for: .normal)
        browseButton.titleLabel?.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .semibold,
            fallback: .preferredFont(forTextStyle: .subheadline)
        )
    }

    private func makeFilterButton(
        title: String,
        symbolName: String?,
        selected: Bool,
        action: Selector
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = symbolName.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 6
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: selected ? .semibold : .medium,
            fallback: .preferredFont(forTextStyle: .body)
        )
        applyFilterStyle(button, selected: selected)
        return button
    }

    private func applyFilterStyle(_ button: UIButton, selected: Bool) {
        let theme = AppSettings.shared.themeStyle
        var configuration = button.configuration ?? .plain()
        configuration.baseForegroundColor = selected ? theme.accentColor : .label
        configuration.background.backgroundColor = selected
            ? theme.accentColor.withAlphaComponent(0.14)
            : .clear
        button.configuration = configuration
    }

    private func rebuildTopics() {
        topicsStack.arrangedSubviews.forEach {
            topicsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        rows.removeAll(keepingCapacity: true)

        let topics = selection == .related ? relatedTopics : suggestedTopics
        for (index, topic) in topics.enumerated() {
            let row = SuggestedTopicRowControl(
                topic: topic,
                baseURL: baseURL,
                showsSeparator: index < topics.count - 1
            )
            row.addTarget(self, action: #selector(topicTapped(_:)), for: .touchUpInside)
            rows.append(row)
            topicsStack.addArrangedSubview(row)
        }
    }

    @objc private func selectRelated() {
        guard !relatedTopics.isEmpty else { return }
        selection = .related
        rebuildFilters()
        rebuildTopics()
        invalidateTableHeight()
    }

    @objc private func selectSuggested() {
        guard !suggestedTopics.isEmpty else { return }
        selection = .suggested
        rebuildFilters()
        rebuildTopics()
        invalidateTableHeight()
    }

    @objc private func topicTapped(_ sender: SuggestedTopicRowControl) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSelectTopic?(sender.topicId)
    }

    @objc private func browseCategory() {
        guard let categoryId, let categoryName else { return }
        onBrowseCategory?(categoryId, categoryName)
    }

    private func invalidateTableHeight() {
        setNeedsLayout()
        layoutIfNeeded()
        var view: UIView? = superview
        while let current = view {
            if let tableView = current as? UITableView {
                tableView.doer_invalidateSelfSizingRows()
                return
            }
            view = current.superview
        }
    }
}

enum SuggestedTopicListItem {
    @MainActor
    static func context(
        from topic: DiscourseTopicDetail.SuggestedTopic,
        baseURL: String,
        showCategory: Bool,
        showTags: Bool
    ) -> TopicListTopicContext {
        let presentation = showCategory
            ? TopicCategoryBadgePresentation.resolve(
                categoryId: topic.categoryId,
                displayName: topic.categoryName,
                baseURL: baseURL
            )
            : nil
        let categoryName: String?
        if showCategory {
            let resolved = presentation?.name ?? topic.categoryName
            let trimmed = resolved?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            categoryName = trimmed.isEmpty ? nil : trimmed
        } else {
            categoryName = nil
        }
        let postsCount = topic.postsCount ?? max((topic.replyCount ?? 0) + 1, 1)
        let replyCount = topic.replyCount ?? max(postsCount - 1, 0)
        let createdAt = topic.createdAt ?? topic.lastPostedAt ?? ""
        let listTopic = DiscourseTopicList.Topic.makeRecommendation(
            id: topic.id,
            title: topic.title,
            fancyTitle: topic.fancyTitle,
            postsCount: postsCount,
            replyCount: replyCount,
            categoryId: topic.categoryId,
            createdAt: createdAt,
            lastPostedAt: topic.lastPostedAt ?? topic.createdAt,
            tags: showTags ? topic.tags : []
        )
        return TopicListTopicContext(
            topic: listTopic,
            avatarURL: AvatarImageLoader.url(
                from: topic.posters.first?.avatarTemplate,
                baseURL: baseURL,
                size: AvatarImageLoader.primaryAvatarPixelSize
            ),
            categoryName: categoryName,
            categoryColor: TopicTaxonomyColor.resolve(hex: presentation?.colorHex ?? ""),
            tags: showTags ? Array(topic.tags.prefix(2).filter { !$0.isEmpty }) : [],
            categoryPresentation: presentation,
            categoryBaseURL: baseURL
        )
    }
}

private final class SuggestedTopicRowControl: UIControl {
    let topicId: Int

    private let embeddedCell: UITableViewCell

    init(topic: DiscourseTopicDetail.SuggestedTopic, baseURL: String, showsSeparator _: Bool) {
        self.topicId = topic.id
        let context = SuggestedTopicListItem.context(
            from: topic,
            baseURL: baseURL,
            showCategory: AppSettings.shared.showTopicCardCategory,
            showTags: AppSettings.shared.showTopicCardTags
        )
        self.embeddedCell = TopicListCellFactory.makeStandaloneTopicCell(context: context)
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            embeddedCell.setHighlighted(isHighlighted, animated: true)
        }
    }

    private func setupUI() {
        backgroundColor = .clear
        clipsToBounds = true
        embeddedCell.translatesAutoresizingMaskIntoConstraints = false
        embeddedCell.contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(embeddedCell)
        NSLayoutConstraint.activate([
            embeddedCell.topAnchor.constraint(equalTo: topAnchor),
            embeddedCell.leadingAnchor.constraint(equalTo: leadingAnchor),
            embeddedCell.trailingAnchor.constraint(equalTo: trailingAnchor),
            embeddedCell.bottomAnchor.constraint(equalTo: bottomAnchor),
            embeddedCell.contentView.topAnchor.constraint(equalTo: embeddedCell.topAnchor),
            embeddedCell.contentView.leadingAnchor.constraint(equalTo: embeddedCell.leadingAnchor),
            embeddedCell.contentView.trailingAnchor.constraint(equalTo: embeddedCell.trailingAnchor),
            embeddedCell.contentView.bottomAnchor.constraint(equalTo: embeddedCell.bottomAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = embeddedCell.accessibilityLabel
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        let estimated = TopicListLayoutKind.current.estimatedRowHeight
        let target = CGSize(width: max(width, 1), height: UIView.layoutFittingCompressedSize.height)
        embeddedCell.bounds = CGRect(origin: .zero, size: CGSize(width: max(width, 1), height: estimated))
        embeddedCell.contentView.bounds = embeddedCell.bounds
        let fitted = embeddedCell.contentView.systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return max(estimated, ceil(fitted))
    }
}
