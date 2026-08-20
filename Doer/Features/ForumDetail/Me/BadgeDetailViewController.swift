import Combine
import SDWebImage
import UIKit

/// FluxDo `BadgePage` — hero icon, info card, grantee list.
final class BadgeDetailViewController: UIViewController {
    private let api: DiscourseAPI
    private let badgeId: Int
    private let username: String?
    private var previewBadge: DiscourseBadge?

    private var badge: DiscourseBadge?
    private var grants: [DiscourseUserBadge] = []
    private var usersById: [Int: DiscourseBadgeUser] = [:]
    private var totalCount = 0
    private var isLoading = false
    private var errorMessage: String?
    private var settingsObservation: AnyCancellable?

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .onDrag
        return view
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let heroContainer = UIView()
    private let heroIconView = UIImageView()
    private let infoCard = UIView()
    private let nameLabel = UILabel()
    private let typePill = UILabel()
    private let descriptionLabel = UILabel()
    private let longDescriptionLabel = UILabel()
    private let longDescriptionBox = UIView()
    private let grantCountLabel = UILabel()
    private let granteesHeader = UILabel()
    private let granteesCountPill = UILabel()
    private let granteesStack = UIStackView()
    private let stateLabel = UILabel()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        return control
    }()

    init(
        api: DiscourseAPI,
        badgeId: Int,
        username: String? = nil,
        previewBadge: DiscourseBadge? = nil
    ) {
        self.api = api
        self.badgeId = badgeId
        self.username = username
        self.previewBadge = previewBadge
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = previewBadge?.name ?? String(localized: "badges.detail_title", defaultValue: "徽章详情")
        navigationItem.largeTitleDisplayMode = .never
        scrollView.refreshControl = refreshControl

        setupHierarchy()
        settingsObservation = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.applyTheme()
            }
        }
        if let previewBadge {
            badge = previewBadge
            renderBadgeChrome()
        }
        applyTheme()
        loadDetail()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
        renderBadgeChrome()
    }

    private func setupHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        heroContainer.translatesAutoresizingMaskIntoConstraints = false
        heroIconView.translatesAutoresizingMaskIntoConstraints = false
        heroIconView.contentMode = .scaleAspectFit
        heroContainer.addSubview(heroIconView)

        infoCard.translatesAutoresizingMaskIntoConstraints = false
        infoCard.layer.cornerRadius = 24
        infoCard.layer.cornerCurve = .continuous

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0
        nameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 22,
            weight: .semibold,
            fallback: .systemFont(ofSize: 22, weight: .semibold)
        )

        typePill.translatesAutoresizingMaskIntoConstraints = false
        typePill.font = .systemFont(ofSize: 13, weight: .semibold)
        typePill.textAlignment = .center
        typePill.layer.cornerRadius = 14
        typePill.layer.borderWidth = 1
        typePill.clipsToBounds = true

        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textAlignment = .center
        descriptionLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: .regular,
            fallback: .systemFont(ofSize: 16, weight: .regular)
        )

        longDescriptionBox.translatesAutoresizingMaskIntoConstraints = false
        longDescriptionBox.layer.cornerRadius = 16
        longDescriptionBox.layer.cornerCurve = .continuous
        longDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        longDescriptionLabel.numberOfLines = 0
        longDescriptionLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 13,
            weight: .regular,
            fallback: .systemFont(ofSize: 13, weight: .regular)
        )
        longDescriptionBox.addSubview(longDescriptionLabel)

        grantCountLabel.translatesAutoresizingMaskIntoConstraints = false
        grantCountLabel.textAlignment = .center
        grantCountLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 15,
            weight: .medium,
            fallback: .systemFont(ofSize: 15, weight: .medium)
        )

        let infoStack = UIStackView(arrangedSubviews: [
            nameLabel,
            typePill,
            descriptionLabel,
            longDescriptionBox,
            makeDivider(),
            grantCountLabel,
        ])
        infoStack.axis = .vertical
        infoStack.alignment = .center
        infoStack.spacing = 12
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.setCustomSpacing(24, after: typePill)
        infoStack.setCustomSpacing(16, after: descriptionLabel)
        infoStack.setCustomSpacing(16, after: longDescriptionBox)
        infoCard.addSubview(infoStack)

        let headerRow = UIStackView(arrangedSubviews: [granteesHeader, UIView(), granteesCountPill])
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        granteesHeader.font = AppSettings.shared.appInterfaceFont(
            ofSize: 18,
            weight: .semibold,
            fallback: .systemFont(ofSize: 18, weight: .semibold)
        )
        granteesHeader.text = String(localized: "badges.grantees", defaultValue: "获得者")
        granteesCountPill.font = .systemFont(ofSize: 12, weight: .semibold)
        granteesCountPill.textAlignment = .center
        granteesCountPill.layer.cornerRadius = 11
        granteesCountPill.clipsToBounds = true

        granteesStack.axis = .vertical
        granteesStack.spacing = 0
        granteesStack.translatesAutoresizingMaskIntoConstraints = false

        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        stateLabel.textAlignment = .center
        stateLabel.textColor = .secondaryLabel
        stateLabel.numberOfLines = 0
        stateLabel.isHidden = true

        contentStack.addArrangedSubview(heroContainer)
        contentStack.addArrangedSubview(infoCard)
        contentStack.addArrangedSubview(headerRow)
        contentStack.addArrangedSubview(granteesStack)
        contentStack.addArrangedSubview(stateLabel)
        contentStack.setCustomSpacing(24, after: infoCard)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40),

            heroContainer.heightAnchor.constraint(equalToConstant: 160),
            heroIconView.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            heroIconView.centerYAnchor.constraint(equalTo: heroContainer.centerYAnchor),
            heroIconView.widthAnchor.constraint(equalToConstant: 96),
            heroIconView.heightAnchor.constraint(equalToConstant: 96),

            infoStack.topAnchor.constraint(equalTo: infoCard.topAnchor, constant: 24),
            infoStack.leadingAnchor.constraint(equalTo: infoCard.leadingAnchor, constant: 20),
            infoStack.trailingAnchor.constraint(equalTo: infoCard.trailingAnchor, constant: -20),
            infoStack.bottomAnchor.constraint(equalTo: infoCard.bottomAnchor, constant: -20),

            typePill.heightAnchor.constraint(equalToConstant: 28),
            typePill.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),

            longDescriptionLabel.topAnchor.constraint(equalTo: longDescriptionBox.topAnchor, constant: 14),
            longDescriptionLabel.leadingAnchor.constraint(equalTo: longDescriptionBox.leadingAnchor, constant: 14),
            longDescriptionLabel.trailingAnchor.constraint(equalTo: longDescriptionBox.trailingAnchor, constant: -14),
            longDescriptionLabel.bottomAnchor.constraint(equalTo: longDescriptionBox.bottomAnchor, constant: -14),
            longDescriptionBox.widthAnchor.constraint(equalTo: infoStack.widthAnchor),

            descriptionLabel.widthAnchor.constraint(equalTo: infoStack.widthAnchor),
            granteesCountPill.heightAnchor.constraint(equalToConstant: 22),
            granteesCountPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
    }

    private func makeDivider() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
        view.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        view.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return view
    }

    private func applyTheme() {
        view.backgroundColor = BadgeUIStyle.pageBackground
        scrollView.backgroundColor = .clear
        refreshControl.tintColor = BadgeUIStyle.chromeAccent
        navigationController?.navigationBar.tintColor = BadgeUIStyle.chromeAccent

        infoCard.backgroundColor = BadgeUIStyle.cardSurface
        infoCard.layer.borderWidth = 1
        infoCard.layer.borderColor = UIColor.separator.withAlphaComponent(0.25).cgColor
        infoCard.layer.shadowColor = UIColor.black.cgColor
        infoCard.layer.shadowOpacity = 0.04
        infoCard.layer.shadowRadius = 16
        infoCard.layer.shadowOffset = CGSize(width: 0, height: 8)

        nameLabel.textColor = .label
        descriptionLabel.textColor = .label
        longDescriptionLabel.textColor = .secondaryLabel
        longDescriptionBox.backgroundColor = BadgeUIStyle.pageBackground.withAlphaComponent(0.85)
        grantCountLabel.textColor = .secondaryLabel
        granteesHeader.textColor = .label
        granteesCountPill.backgroundColor = BadgeUIStyle.pageBackground
        granteesCountPill.textColor = .secondaryLabel

        let type = badge?.type ?? .bronze
        heroContainer.backgroundColor = type.color.withAlphaComponent(
            traitCollection.userInterfaceStyle == .dark ? 0.22 : 0.14
        )
        heroContainer.layer.cornerRadius = 28
        heroContainer.layer.cornerCurve = .continuous
    }

    private func renderBadgeChrome() {
        guard let badge else { return }
        title = badge.name
        nameLabel.text = badge.name
        typePill.text = "  \(badge.type.title)  "
        typePill.textColor = badge.type.color
        typePill.backgroundColor = badge.type.color.withAlphaComponent(0.12)
        typePill.layer.borderColor = badge.type.color.withAlphaComponent(0.22).cgColor

        let desc = BadgeUIStyle.plainText(fromHTML: badge.description)
        descriptionLabel.text = desc.isEmpty ? nil : desc
        descriptionLabel.isHidden = desc.isEmpty

        let longDesc = BadgeUIStyle.plainText(fromHTML: badge.longDescription)
        longDescriptionLabel.text = longDesc
        longDescriptionBox.isHidden = longDesc.isEmpty

        grantCountLabel.text = String(
            format: String(localized: "badges.granted_count %lld", defaultValue: "已颁发 %lld 次"),
            Int64(badge.grantCount)
        )

        BadgeUIStyle.badgeIconImage(
            icon: badge.icon,
            imageURL: badge.imageURL,
            type: badge.type,
            baseURL: api.baseURL,
            pointSize: 64,
            into: heroIconView
        )
        applyTheme()
    }

    private func loadDetail() {
        isLoading = true
        errorMessage = nil
        updateLoadingState()
        Task { @MainActor in
            do {
                async let badgeTask = api.fetchBadge(id: badgeId)
                async let usersTask = api.fetchBadgeUsers(badgeId: badgeId, username: username)
                let (fetchedBadge, detail) = try await (badgeTask, usersTask)
                badge = fetchedBadge
                // Prefer detail.badge if decoder filled it; otherwise fetched.
                if detail.badge.id != 0 {
                    badge = detail.badge
                }
                grants = detail.userBadges
                usersById = Dictionary(uniqueKeysWithValues: detail.users.map { ($0.id, $0) })
                totalCount = detail.totalCount > 0 ? detail.totalCount : detail.userBadges.count
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            refreshControl.endRefreshing()
            renderBadgeChrome()
            renderGrantees()
            updateLoadingState()
        }
    }

    private func renderGrantees() {
        granteesStack.arrangedSubviews.forEach {
            granteesStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        granteesCountPill.text = "  \(totalCount)  "

        if grants.isEmpty {
            let empty = UILabel()
            empty.text = String(localized: "badges.no_grantees", defaultValue: "暂无获得者")
            empty.textColor = .tertiaryLabel
            empty.textAlignment = .center
            empty.font = .systemFont(ofSize: 14, weight: .medium)
            granteesStack.addArrangedSubview(empty)
            return
        }

        for grant in grants {
            let user = usersById[grant.userId]
            let row = BadgeGranteeRowView()
            row.configure(
                grant: grant,
                user: user,
                baseURL: api.baseURL
            )
            row.onTapUser = { [weak self] username in
                guard let self else { return }
                let profile = UserProfileViewController(api: self.api, username: username)
                self.navigationController?.pushViewController(profile, animated: true)
            }
            row.onTapTopic = { [weak self] topicId in
                guard let self else { return }
                let detail = TopicDetailFactory.make(api: self.api, topicId: topicId)
                self.navigationController?.pushViewController(detail, animated: true)
            }
            granteesStack.addArrangedSubview(row)
        }
    }

    private func updateLoadingState() {
        if let errorMessage, badge == nil {
            stateLabel.isHidden = false
            stateLabel.text = errorMessage
        } else if isLoading, badge == nil {
            stateLabel.isHidden = false
            stateLabel.text = String(localized: "badges.loading")
        } else {
            stateLabel.isHidden = true
        }
    }

    @objc private func refreshPulled() {
        loadDetail()
    }
}

// MARK: - Grantee row

private final class BadgeGranteeRowView: UIView {
    var onTapUser: ((String) -> Void)?
    var onTapTopic: ((Int) -> Void)?

    private let avatarView = UIImageView()
    private let nameButton = UIButton(type: .system)
    private let roleIcon = UIImageView()
    private let timeLabel = UILabel()
    private let topicChip = UIButton(type: .system)
    private var topicId: Int?
    private var username: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(grant: DiscourseUserBadge, user: DiscourseBadgeUser?, baseURL: String) {
        username = user?.username
        topicId = grant.topicId

        let displayName = user?.username ?? String(localized: "badges.unknown_user", defaultValue: "用户")
        nameButton.setTitle(displayName, for: .normal)
        nameButton.titleLabel?.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: .semibold,
            fallback: .systemFont(ofSize: 16, weight: .semibold)
        )
        nameButton.setTitleColor(.label, for: .normal)

        if user?.admin == true {
            roleIcon.isHidden = false
            roleIcon.tintColor = .systemRed
            roleIcon.image = UIImage(systemName: "shield.fill")
        } else if user?.moderator == true {
            roleIcon.isHidden = false
            roleIcon.tintColor = .systemBlue
            roleIcon.image = UIImage(systemName: "shield.fill")
        } else {
            roleIcon.isHidden = true
        }

        timeLabel.text = Self.formatGrantedAt(grant.grantedAt)
        timeLabel.textColor = .secondaryLabel
        timeLabel.font = .systemFont(ofSize: 12, weight: .regular)

        if let title = grant.topicTitle, !title.isEmpty {
            topicChip.isHidden = false
            topicChip.setTitle("  \(title)  ", for: .normal)
            topicChip.isEnabled = grant.topicId != nil
        } else {
            topicChip.isHidden = true
        }

        avatarView.backgroundColor = .secondarySystemFill
        avatarView.image = nil
        if let template = user?.avatarTemplate,
           let url = AvatarImageLoader.url(
            from: template,
            baseURL: baseURL,
            size: AvatarImageLoader.primaryAvatarPixelSize
           ) {
            AvatarImageLoader.setImage(
                on: avatarView,
                url: url,
                cloudflareBaseURL: baseURL,
                avatarBaseURL: baseURL,
                userId: user?.id
            )
        }
    }

    private func setupUI() {
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.layer.cornerRadius = 24
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(userTapped)))

        nameButton.addTarget(self, action: #selector(userTapped), for: .touchUpInside)
        nameButton.contentHorizontalAlignment = .leading

        roleIcon.translatesAutoresizingMaskIntoConstraints = false
        roleIcon.contentMode = .scaleAspectFit

        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        topicChip.translatesAutoresizingMaskIntoConstraints = false
        topicChip.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        topicChip.titleLabel?.lineBreakMode = .byTruncatingTail
        topicChip.setTitleColor(.secondaryLabel, for: .normal)
        topicChip.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.65)
        topicChip.layer.cornerRadius = 8
        topicChip.layer.cornerCurve = .continuous
        topicChip.contentHorizontalAlignment = .leading
        topicChip.addTarget(self, action: #selector(topicTapped), for: .touchUpInside)

        let nameRow = UIStackView(arrangedSubviews: [nameButton, roleIcon, UIView()])
        nameRow.axis = .horizontal
        nameRow.alignment = .center
        nameRow.spacing = 4

        let textStack = UIStackView(arrangedSubviews: [nameRow, timeLabel, topicChip])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(avatarView)
        addSubview(textStack)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            avatarView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            avatarView.widthAnchor.constraint(equalToConstant: 48),
            avatarView.heightAnchor.constraint(equalToConstant: 48),

            roleIcon.widthAnchor.constraint(equalToConstant: 14),
            roleIcon.heightAnchor.constraint(equalToConstant: 14),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            topicChip.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            topicChip.widthAnchor.constraint(lessThanOrEqualTo: textStack.widthAnchor),
        ])
    }

    @objc private func userTapped() {
        guard let username else { return }
        onTapUser?(username)
    }

    @objc private func topicTapped() {
        guard let topicId else { return }
        onTapTopic?(topicId)
    }

    private static func formatGrantedAt(_ iso: String?) -> String {
        guard let iso else {
            return String(localized: "badges.granted_unknown_time", defaultValue: "获得时间未知")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: iso)
            ?? {
                let plain = ISO8601DateFormatter()
                return plain.date(from: iso)
            }()
        guard let date else { return iso }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        let base = relative.localizedString(for: date, relativeTo: Date())
        return String(
            format: String(localized: "badges.granted_suffix %@", defaultValue: "%@获得"),
            base
        )
    }
}
