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

/// End-of-topic related/suggested topics (FluxDo parity).
/// Sized via frames for `tableFooterView` — do NOT override intrinsicContentSize with
/// `systemLayoutSizeFitting(self)` (infinite recursion / EXC_BAD_ACCESS on stack).
final class SuggestedTopicsFooterView: UIView {
    var onSelectTopic: ((Int) -> Void)?

    private let titleLabel = UILabel()
    private let stack = UIStackView()
    private var topicCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        // tableFooterView is frame-based; keep autoresizing mask enabled.
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.flexibleWidth]
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: .heavy,
            fallback: .systemFont(ofSize: 16, weight: .heavy)
        )
        titleLabel.textColor = .label
        titleLabel.text = String(localized: "topic.suggested.title", defaultValue: "相关话题")

        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            // Pin bottom so Auto Layout can resolve height when we set bounds width.
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }

    func configure(topics: [DiscourseTopicDetail.SuggestedTopic]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let items = Array(topics.prefix(6))
        topicCount = items.count
        isHidden = items.isEmpty
        guard !items.isEmpty else { return }

        let accent = AppSettings.shared.themeStyle.accentColor
        for topic in items {
            var config = UIButton.Configuration.plain()
            config.title = topic.displayTitle
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
            config.titleLineBreakMode = .byTruncatingTail
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = AppSettings.shared.appInterfaceFont(
                    ofSize: 15,
                    weight: .semibold,
                    fallback: .systemFont(ofSize: 15, weight: .semibold)
                )
                return outgoing
            }

            let button = UIButton(configuration: config)
            button.tag = topic.id
            button.contentHorizontalAlignment = .leading
            button.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
            button.layer.cornerRadius = 14
            button.layer.cornerCurve = .continuous
            button.layer.borderWidth = 1.0 / UIScreen.main.scale
            button.layer.borderColor = UIColor.separator.withAlphaComponent(0.22).cgColor
            button.addTarget(self, action: #selector(topicTapped(_:)), for: .touchUpInside)
            if let replies = topic.replyCount ?? topic.postsCount {
                button.accessibilityValue = "\(replies)"
            }
            let bar = UIView()
            bar.backgroundColor = accent
            bar.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                bar.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
                bar.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -10),
                bar.widthAnchor.constraint(equalToConstant: 3),
                button.heightAnchor.constraint(equalToConstant: 52),
            ])
            stack.addArrangedSubview(button)
        }
    }

    /// Safe height for `tableFooterView` — never calls `systemLayoutSizeFitting` on self.
    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard topicCount > 0, width > 0 else { return 0 }
        // title(16+22) + gap(12) + rows(52*n + 8*(n-1)) + bottom(20)
        let rows = CGFloat(topicCount)
        return 16 + 22 + 12 + rows * 52 + max(0, rows - 1) * 8 + 20
    }

    @objc private func topicTapped(_ sender: UIButton) {
        guard sender.tag > 0 else { return }
        onSelectTopic?(sender.tag)
    }
}
