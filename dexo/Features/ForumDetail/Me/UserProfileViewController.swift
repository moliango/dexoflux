import UIKit

final class UserProfileViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: UserProfileViewModel
    private let contentViewModel: UserProfileContentViewModel
    private let tabPreferences: UserProfileTabPreferences

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let heroView = UIView()
    private let backgroundImageView = UIImageView()
    private let heroGradientLayer = CAGradientLayer()
    private let textureView = UIView()
    private let avatarImageView = UIImageView()
    private let displayNameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let levelLabel = UILabel()
    private let titleLabel = UILabel()
    private let followButton = UIButton(type: .system)
    private let bioCard = UIControl()
    private let bioLabel = UILabel()
    private let statsStack = UIStackView()
    private let recencyPill = UIView()
    private let recencyLabel = UILabel()
    private let panelView = UIView()
    private let panelStack = UIStackView()
    private let tabScrollView = UIScrollView()
    private let tabStack = UIStackView()
    private let profileContentView = UserProfileContentView()
    private let topicListStack = UIStackView()
    private let entryStack = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private lazy var searchBarButton = UIBarButtonItem(
        image: UIImage(systemName: "magnifyingglass"),
        style: .plain,
        target: self,
        action: #selector(searchTapped)
    )
    private lazy var messageBarButton = UIBarButtonItem(
        image: UIImage(systemName: "envelope"),
        style: .plain,
        target: self,
        action: #selector(messageTapped)
    )
    private lazy var moreBarButton = UIBarButtonItem(
        image: UIImage(systemName: "ellipsis"),
        style: .plain,
        target: nil,
        action: nil
    )

    private var savedStandardAppearance: UINavigationBarAppearance?
    private var savedScrollEdgeAppearance: UINavigationBarAppearance?
    private var savedCompactAppearance: UINavigationBarAppearance?
    private var savedTintColor: UIColor?
    private var lastPresentedRelationshipError: String?

    init(api: DiscourseAPI, username: String) {
        let tabPreferences = UserProfileTabPreferences()
        self.api = api
        self.viewModel = UserProfileViewModel(api: api, username: username)
        self.tabPreferences = tabPreferences
        self.contentViewModel = UserProfileContentViewModel(
            username: username,
            service: api,
            initialSection: tabPreferences.visibleSections.first ?? .summary
        )
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureTransparentNavigationBar()
        reconcileVisibleProfileSection()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restoreNavigationBar()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = nil
        setupNavigationItems()
        setupUI()
        let profileViewModel = viewModel
        let profileContentViewModel = contentViewModel
        let initialContentGeneration = profileContentViewModel.contentGeneration
        Task { @MainActor in
            await profileViewModel.load()
            let summary = profileViewModel.summary
            guard profileContentViewModel.applySummary(
                summary,
                ifGeneration: initialContentGeneration
            ) else { return }
            if summary == nil {
                await profileContentViewModel.refresh()
            }
        }
        if profileContentViewModel.section != .summary {
            Task { @MainActor in
                await profileContentViewModel.refresh()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        heroGradientLayer.frame = heroView.bounds
        panelView.layer.shadowPath = UIBezierPath(
            roundedRect: panelView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: 30, height: 30)
        ).cgPath
    }

    override func updateUI() {
        applyTheme()

        if viewModel.isLoading, viewModel.userProfile == nil {
            loadingIndicator.startAnimating()
        } else {
            loadingIndicator.stopAnimating()
        }

        errorLabel.isHidden = viewModel.errorMessage == nil
        errorLabel.text = viewModel.errorMessage

        guard let profile = viewModel.userProfile else {
            contentView.alpha = viewModel.isLoading ? 0.45 : 1
            profileContentView.render(viewModel: contentViewModel)
            return
        }

        contentView.alpha = 1
        configure(profile: profile, summary: viewModel.summary)
        profileContentView.render(viewModel: contentViewModel)
    }

    private func setupNavigationItems() {
        navigationItem.rightBarButtonItems = [moreBarButton, messageBarButton, searchBarButton]
    }

    private func setupUI() {
        view.backgroundColor = .black

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        setupHero()
        setupPanel()
        setupLoadingAndError()

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            heroView.topAnchor.constraint(equalTo: contentView.topAnchor),
            heroView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            heroView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            heroView.heightAnchor.constraint(equalToConstant: 530),

            panelView.topAnchor.constraint(equalTo: heroView.bottomAnchor, constant: -110),
            panelView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            panelView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func setupHero() {
        heroView.translatesAutoresizingMaskIntoConstraints = false
        heroView.clipsToBounds = true
        contentView.addSubview(heroView)

        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.alpha = 0
        heroView.addSubview(backgroundImageView)

        heroView.layer.insertSublayer(heroGradientLayer, above: backgroundImageView.layer)

        textureView.translatesAutoresizingMaskIntoConstraints = false
        textureView.backgroundColor = UIColor(patternImage: Self.makeTextureImage())
        textureView.alpha = 0.22
        heroView.addSubview(textureView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 36
        avatarImageView.layer.borderWidth = 3
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.backgroundColor = .secondarySystemFill

        displayNameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 26,
            weight: .heavy,
            fallback: .systemFont(ofSize: 26, weight: .heavy)
        )
        displayNameLabel.textColor = .white
        displayNameLabel.numberOfLines = 1
        displayNameLabel.adjustsFontSizeToFitWidth = true
        displayNameLabel.minimumScaleFactor = 0.68

        usernameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .semibold,
            fallback: .systemFont(ofSize: 14, weight: .semibold)
        )
        usernameLabel.textColor = UIColor.white.withAlphaComponent(0.78)

        levelLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 12,
            weight: .bold,
            fallback: .systemFont(ofSize: 12, weight: .bold)
        )
        levelLabel.textColor = .white
        levelLabel.textAlignment = .center
        levelLabel.layer.cornerRadius = 8
        levelLabel.layer.cornerCurve = .continuous
        levelLabel.clipsToBounds = true
        levelLabel.isHidden = true

        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 12,
            weight: .semibold,
            fallback: .systemFont(ofSize: 12, weight: .semibold)
        )
        titleLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        titleLabel.numberOfLines = 1

        var followConfig = UIButton.Configuration.filled()
        followConfig.title = String(localized: "user.profile.follow")
        followConfig.image = UIImage(systemName: "plus")
        followConfig.imagePadding = 8
        followConfig.cornerStyle = .capsule
        followConfig.baseForegroundColor = .black
        followConfig.baseBackgroundColor = .white
        followButton.configuration = followConfig
        followButton.translatesAutoresizingMaskIntoConstraints = false
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)

        let nameStack = UIStackView(arrangedSubviews: [displayNameLabel, usernameLabel, levelLabel, titleLabel])
        nameStack.axis = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 7
        nameStack.translatesAutoresizingMaskIntoConstraints = false

        setupBioCard()
        setupStatsStack()
        setupRecencyPill()

        heroView.addSubview(avatarImageView)
        heroView.addSubview(nameStack)
        heroView.addSubview(followButton)
        heroView.addSubview(bioCard)
        heroView.addSubview(statsStack)
        heroView.addSubview(recencyPill)

        let levelHeightConstraint = levelLabel.heightAnchor.constraint(equalToConstant: 24)
        levelHeightConstraint.priority = UILayoutPriority(999)
        let levelWidthConstraint = levelLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        levelWidthConstraint.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: heroView.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: heroView.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: heroView.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: heroView.bottomAnchor),

            textureView.topAnchor.constraint(equalTo: heroView.topAnchor),
            textureView.leadingAnchor.constraint(equalTo: heroView.leadingAnchor),
            textureView.trailingAnchor.constraint(equalTo: heroView.trailingAnchor),
            textureView.bottomAnchor.constraint(equalTo: heroView.bottomAnchor),

            avatarImageView.leadingAnchor.constraint(equalTo: heroView.leadingAnchor, constant: 28),
            avatarImageView.topAnchor.constraint(equalTo: heroView.safeAreaLayoutGuide.topAnchor, constant: 22),
            avatarImageView.widthAnchor.constraint(equalToConstant: 72),
            avatarImageView.heightAnchor.constraint(equalToConstant: 72),

            nameStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 18),
            nameStack.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -14),
            nameStack.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),

            followButton.trailingAnchor.constraint(equalTo: heroView.trailingAnchor, constant: -24),
            followButton.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            followButton.heightAnchor.constraint(equalToConstant: 40),
            followButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),

            levelHeightConstraint,
            levelWidthConstraint,

            bioCard.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 22),
            bioCard.leadingAnchor.constraint(equalTo: heroView.leadingAnchor, constant: 24),
            bioCard.trailingAnchor.constraint(equalTo: heroView.trailingAnchor, constant: -24),
            bioCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),

            statsStack.topAnchor.constraint(equalTo: bioCard.bottomAnchor, constant: 16),
            statsStack.leadingAnchor.constraint(equalTo: heroView.leadingAnchor, constant: 26),
            statsStack.trailingAnchor.constraint(lessThanOrEqualTo: heroView.trailingAnchor, constant: -24),

            recencyPill.topAnchor.constraint(equalTo: statsStack.bottomAnchor, constant: 10),
            recencyPill.leadingAnchor.constraint(equalTo: heroView.leadingAnchor, constant: 26),
            recencyPill.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func setupBioCard() {
        bioCard.translatesAutoresizingMaskIntoConstraints = false
        bioCard.layer.cornerRadius = 10
        bioCard.layer.cornerCurve = .continuous
        bioCard.addTarget(self, action: #selector(bioTapped), for: .touchUpInside)

        bioLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .medium,
            fallback: .systemFont(ofSize: 14, weight: .medium)
        )
        bioLabel.textColor = UIColor.white.withAlphaComponent(0.88)
        bioLabel.numberOfLines = 2
        bioLabel.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = UIColor.white.withAlphaComponent(0.62)
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        bioCard.addSubview(bioLabel)
        bioCard.addSubview(chevron)

        NSLayoutConstraint.activate([
            bioLabel.topAnchor.constraint(equalTo: bioCard.topAnchor, constant: 13),
            bioLabel.leadingAnchor.constraint(equalTo: bioCard.leadingAnchor, constant: 16),
            bioLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -10),
            bioLabel.bottomAnchor.constraint(equalTo: bioCard.bottomAnchor, constant: -13),

            chevron.trailingAnchor.constraint(equalTo: bioCard.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: bioCard.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
        ])
    }

    private func setupStatsStack() {
        statsStack.axis = .vertical
        statsStack.alignment = .leading
        statsStack.spacing = 10
        statsStack.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupRecencyPill() {
        recencyPill.translatesAutoresizingMaskIntoConstraints = false
        recencyPill.layer.cornerRadius = 16
        recencyPill.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: "bolt.fill"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.76)
        icon.translatesAutoresizingMaskIntoConstraints = false

        recencyLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 13,
            weight: .semibold,
            fallback: .systemFont(ofSize: 13, weight: .semibold)
        )
        recencyLabel.textColor = UIColor.white.withAlphaComponent(0.76)

        let stack = UIStackView(arrangedSubviews: [icon, recencyLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        recencyPill.addSubview(stack)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13),
            stack.leadingAnchor.constraint(equalTo: recencyPill.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: recencyPill.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: recencyPill.centerYAnchor),
        ])
    }

    private func setupPanel() {
        panelView.translatesAutoresizingMaskIntoConstraints = false
        panelView.layer.cornerRadius = 30
        panelView.layer.cornerCurve = .continuous
        panelView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panelView.layer.shadowColor = UIColor.black.cgColor
        panelView.layer.shadowOpacity = 0.16
        panelView.layer.shadowRadius = 24
        panelView.layer.shadowOffset = CGSize(width: 0, height: -8)
        contentView.addSubview(panelView)

        panelStack.axis = .vertical
        panelStack.spacing = 12
        panelStack.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(panelStack)

        tabScrollView.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.showsHorizontalScrollIndicator = false
        tabScrollView.alwaysBounceHorizontal = true
        panelStack.addArrangedSubview(tabScrollView)
        tabScrollView.heightAnchor.constraint(equalToConstant: 44).isActive = true

        tabStack.axis = .horizontal
        tabStack.distribution = .fill
        tabStack.spacing = 0
        tabStack.translatesAutoresizingMaskIntoConstraints = false
        tabScrollView.addSubview(tabStack)
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.topAnchor),
            tabStack.leadingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.trailingAnchor),
            tabStack.bottomAnchor.constraint(equalTo: tabScrollView.contentLayoutGuide.bottomAnchor),
            tabStack.heightAnchor.constraint(equalTo: tabScrollView.frameLayoutGuide.heightAnchor),
        ])

        panelStack.addArrangedSubview(profileContentView)
        profileContentView.heightAnchor.constraint(equalToConstant: 620).isActive = true
        profileContentView.onRefresh = { [weak self] in
            Task { @MainActor in
                await self?.contentViewModel.refresh()
            }
        }
        profileContentView.onLoadMore = { [weak self] in
            Task { @MainActor in
                await self?.contentViewModel.loadMore()
            }
        }
        profileContentView.onSelectRow = { [weak self] row in
            self?.openContentRow(row)
        }

        NSLayoutConstraint.activate([
            panelStack.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 14),
            panelStack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor, constant: 18),
            panelStack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor, constant: -18),
            panelStack.bottomAnchor.constraint(equalTo: panelView.bottomAnchor, constant: -34),
        ])
    }

    private func setupLoadingAndError() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingIndicator)

        errorLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 13,
            weight: .medium,
            fallback: .systemFont(ofSize: 13, weight: .medium)
        )
        errorLabel.textColor = .secondaryLabel
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            errorLabel.topAnchor.constraint(equalTo: loadingIndicator.bottomAnchor, constant: 14),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func configure(profile: DiscourseUserProfile, summary: DiscourseUserSummary?) {
        let displayName = UserProfileFormatting.displayName(profile: profile, fallbackUsername: viewModel.username)
        displayNameLabel.text = displayName
        usernameLabel.text = "@\(profile.username)"
        let levelText = UserProfileFormatting.trustLevelText(profile.trustLevel)
        levelLabel.text = levelText
        levelLabel.isHidden = levelText == nil
        titleLabel.text = profile.title
        titleLabel.isHidden = (profile.title ?? "").isEmpty
        bioLabel.text = UserProfileFormatting.cleanBio(profile.bioExcerpt) ?? String(localized: "user.profile.no_bio")
        recencyLabel.text = profile.lastPostedAt.map(UserProfileFormatting.relativeDate) ?? String(localized: "user.profile.last_posted")

        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: profile.avatarTemplate,
            baseURL: api.baseURL,
            size: 240
        )
        configureBackground(profile: profile)
        configureStats(profile: profile, card: viewModel.userCard, summary: summary)
        configureRelationshipActions(profile: profile)
        configureTabs()
    }

    private func configureBackground(profile: DiscourseUserProfile) {
        let rawURL = profile.profileBackgroundURL?.nilIfBlank ?? profile.cardBackgroundURL?.nilIfBlank
        guard let url = resolveURL(rawURL) else {
            backgroundImageView.alpha = 0
            backgroundImageView.image = nil
            return
        }

        backgroundImageView.alpha = 0.38
        ForumImageLoader.setImage(on: backgroundImageView, url: url)
    }

    private func configureStats(
        profile: DiscourseUserProfile,
        card: DiscourseUserProfile?,
        summary: DiscourseUserSummary?
    ) {
        statsStack.arrangedSubviews.forEach { view in
            statsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let firstRowItems: [(String, String, UserSocialListViewController.Mode)] = [
            (card?.followingCount ?? profile.followingCount).map {
                (UserProfileFormatting.compactNumber($0), String(localized: "user.profile.following"), .following)
            },
            (card?.followerCount ?? profile.followerCount).map {
                (UserProfileFormatting.compactNumber($0), String(localized: "user.profile.followers"), .followers)
            },
        ].compactMap { $0 }

        if !firstRowItems.isEmpty {
            statsStack.addArrangedSubview(makeSocialStatRow(firstRowItems))
        }

        let secondRowItems: [(String, String)] = [
            (UserProfileFormatting.compactNumber(summary?.likesReceived), String(localized: "me.stats.likes")),
            (UserProfileFormatting.compactNumber(card?.profileViewCount ?? profile.profileViewCount), String(localized: "me.stats.profile_views")),
            (UserProfileFormatting.compactNumber(summary?.topicCount), String(localized: "me.stats.topics")),
            (UserProfileFormatting.compactNumber(summary?.postCount), String(localized: "user.profile.replies")),
        ]
        statsStack.addArrangedSubview(makeStatRow(secondRowItems, valueSize: 18, labelSize: 12, spacing: 12))
    }

    private func configureTabs(selectedSection: UserProfileSection? = nil) {
        tabStack.arrangedSubviews.forEach { view in
            tabStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let selectedSection = selectedSection ?? contentViewModel.section
        for (index, section) in tabPreferences.visibleSections.enumerated() {
            let button = ProfileTabButton()
            button.configure(title: section.title, selected: section == selectedSection)
            button.tag = index
            button.addTarget(self, action: #selector(profileTabTapped(_:)), for: .touchUpInside)
            tabStack.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        }
        if selectedSection == .summary {
            tabScrollView.setContentOffset(.zero, animated: false)
        }
    }

    private func configureSummaryTopics(_ topics: [DiscourseUserSummaryTopic]) {
        topicListStack.arrangedSubviews.forEach { view in
            topicListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard !topics.isEmpty else {
            topicListStack.isHidden = true
            return
        }

        topicListStack.isHidden = false
        topicListStack.addArrangedSubview(makeSectionHeader(symbolName: "list.bullet.rectangle", title: String(localized: "user.profile.top_topics")))

        for topic in topics.prefix(5) {
            let card = SummaryTopicCard()
            card.configure(topic: topic)
            card.tag = topic.id
            card.addTarget(self, action: #selector(openSummaryTopic(_:)), for: .touchUpInside)
            topicListStack.addArrangedSubview(card)
        }
    }

    private func configureEntryCards() {
        entryStack.arrangedSubviews.forEach { view in
            entryStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let topicsCard = UserProfileActionCard()
        topicsCard.configure(
            title: String(localized: "user.topics_title"),
            subtitle: String(localized: "user.profile.topics_subtitle"),
            symbolName: "text.bubble.fill",
            tintColor: .systemBlue
        )
        topicsCard.addTarget(self, action: #selector(openTopics), for: .touchUpInside)

        let postsCard = UserProfileActionCard()
        postsCard.configure(
            title: String(localized: "user.posts_title"),
            subtitle: String(localized: "user.profile.posts_subtitle"),
            symbolName: "quote.bubble.fill",
            tintColor: .systemIndigo
        )
        postsCard.addTarget(self, action: #selector(openPosts), for: .touchUpInside)

        entryStack.addArrangedSubview(topicsCard)
        entryStack.addArrangedSubview(postsCard)
    }

    private func makeStatRow(_ items: [(String, String)], valueSize: CGFloat, labelSize: CGFloat, spacing: CGFloat) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = spacing

        for item in items {
            let label = UILabel()
            label.attributedText = statText(value: item.0, label: item.1, valueSize: valueSize, labelSize: labelSize)
            row.addArrangedSubview(label)
        }
        return row
    }

    private func makeSocialStatRow(_ items: [(String, String, UserSocialListViewController.Mode)]) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        for item in items {
            let button = UIButton(type: .system)
            button.tag = item.2 == .following ? 0 : 1
            button.setAttributedTitle(statText(value: item.0, label: item.1, valueSize: 17, labelSize: 12), for: .normal)
            button.addTarget(self, action: #selector(socialStatTapped(_:)), for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func configureRelationshipActions(profile: DiscourseUserProfile) {
        let state = viewModel.relationshipController.state
        let currentUsername = AuthManager.shared.username(for: api.baseURL)
        let isCurrentUser = currentUsername?.caseInsensitiveCompare(profile.username) == .orderedSame
        followButton.isHidden = isCurrentUser || !state.canFollow
        followButton.isEnabled = !state.isMutating
        moreBarButton.isEnabled = !state.isMutating
        navigationItem.rightBarButtonItems = (isCurrentUser || !state.canSendPrivateMessage)
            ? [moreBarButton, searchBarButton]
            : [moreBarButton, messageBarButton, searchBarButton]

        var configuration = followButton.configuration
        configuration?.title = state.isFollowed
            ? String(localized: "user.profile.unfollow", defaultValue: "Unfollow")
            : String(localized: "user.profile.follow")
        configuration?.image = UIImage(systemName: state.isFollowed ? "minus" : "plus")
        followButton.configuration = configuration
        moreBarButton.menu = makeRelationshipMenu(isCurrentUser: isCurrentUser)

        if let message = state.errorMessage,
           message != lastPresentedRelationshipError,
           presentedViewController == nil {
            lastPresentedRelationshipError = message
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel) { [weak self] _ in
                self?.viewModel.relationshipController.clearError()
            })
            present(alert, animated: true)
        }
    }

    private func makeRelationshipMenu(isCurrentUser: Bool) -> UIMenu {
        let state = viewModel.relationshipController.state
        var children: [UIMenuElement] = []
        if !isCurrentUser {
            if state.isMuted || state.isIgnored {
                children.append(UIAction(
                    title: String(localized: "user.profile.restore_notifications", defaultValue: "Restore notifications"),
                    image: UIImage(systemName: "bell")
                ) { [weak self] _ in self?.performRelationship(.restore) })
            } else {
                if state.canMute {
                    children.append(UIAction(
                        title: String(localized: "user.profile.mute", defaultValue: "Mute"),
                        image: UIImage(systemName: "speaker.slash")
                    ) { [weak self] _ in self?.performRelationship(.mute) })
                }
                if state.canIgnore {
                    let now = Date()
                    let calendar = Calendar.current
                    let ignoreActions = [
                        (String(localized: "user.profile.ignore.day", defaultValue: "For one day"), calendar.date(byAdding: .day, value: 1, to: now) ?? now),
                        (String(localized: "user.profile.ignore.week", defaultValue: "For one week"), calendar.date(byAdding: .day, value: 7, to: now) ?? now),
                        (String(localized: "user.profile.ignore.month", defaultValue: "For one month"), calendar.date(byAdding: .month, value: 1, to: now) ?? now),
                    ].map { title, expiry in
                        UIAction(title: title) { [weak self] _ in self?.performRelationship(.ignore(until: expiry)) }
                    }
                    children.append(UIMenu(
                        title: String(localized: "user.profile.ignore", defaultValue: "Ignore"),
                        image: UIImage(systemName: "person.crop.circle.badge.xmark"),
                        children: ignoreActions
                    ))
                }
            }
        }
        children.append(UIAction(
            title: String(localized: "user.profile.share", defaultValue: "Share user"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in self?.shareUser() })
        return UIMenu(children: children)
    }

    private func performRelationship(_ mutation: UserRelationshipMutation) {
        Task { @MainActor [weak self] in
            await self?.viewModel.relationshipController.perform(mutation)
        }
    }

    private func statText(value: String, label: String, valueSize: CGFloat, labelSize: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: value,
            attributes: [
                .font: AppSettings.shared.appInterfaceFont(ofSize: valueSize, weight: .heavy, fallback: .systemFont(ofSize: valueSize, weight: .heavy)),
                .foregroundColor: UIColor.white,
            ]
        ))
        result.append(NSAttributedString(
            string: " \(label)",
            attributes: [
                .font: AppSettings.shared.appInterfaceFont(ofSize: labelSize, weight: .semibold, fallback: .systemFont(ofSize: labelSize, weight: .semibold)),
                .foregroundColor: UIColor.white.withAlphaComponent(0.68),
            ]
        ))
        return result
    }

    private func makeSectionHeader(symbolName: String, title: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = AppSettings.shared.themeStyle.accentColor
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.font = AppSettings.shared.appInterfaceFont(
            ofSize: 18,
            weight: .heavy,
            fallback: .systemFont(ofSize: 18, weight: .heavy)
        )
        label.textColor = AppSettings.shared.themeStyle.accentColor
        label.text = title

        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
        ])
        return row
    }

    private func applyTheme() {
        let theme = AppSettings.shared.themeStyle
        scrollView.backgroundColor = .black
        panelView.backgroundColor = theme.contentBackgroundColor
        bioCard.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        recencyPill.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        levelLabel.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        avatarImageView.layer.borderColor = UIColor.white.withAlphaComponent(0.92).cgColor

        let darkBase = UIColor.black
        heroGradientLayer.colors = [
            darkBase.withAlphaComponent(0.82).cgColor,
            theme.accentColor.withAlphaComponent(0.36).cgColor,
            darkBase.withAlphaComponent(0.92).cgColor,
        ]
        heroGradientLayer.startPoint = CGPoint(x: 0.05, y: 0)
        heroGradientLayer.endPoint = CGPoint(x: 1, y: 1)

        profileContentView.backgroundColor = .clear
    }

    private func configureTransparentNavigationBar() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        savedStandardAppearance = navigationBar.standardAppearance
        savedScrollEdgeAppearance = navigationBar.scrollEdgeAppearance
        savedCompactAppearance = navigationBar.compactAppearance
        savedTintColor = navigationBar.tintColor

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = .white
    }

    private func restoreNavigationBar() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        if let savedStandardAppearance {
            navigationBar.standardAppearance = savedStandardAppearance
        }
        navigationBar.scrollEdgeAppearance = savedScrollEdgeAppearance
        navigationBar.compactAppearance = savedCompactAppearance
        navigationBar.tintColor = savedTintColor
    }

    private func resolveURL(_ rawURL: String?) -> URL? {
        guard let rawURL else { return nil }
        if rawURL.hasPrefix("//") {
            return URL(string: "https:\(rawURL)")
        }
        if let absoluteURL = URL(string: rawURL), absoluteURL.scheme != nil {
            return absoluteURL
        }
        let normalizedBase = api.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        return URL(string: rawURL, relativeTo: URL(string: normalizedBase))?.absoluteURL
    }

    private static func makeTextureImage() -> UIImage {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.08).setFill()
            for index in stride(from: 0, to: 28, by: 4) {
                context.fill(CGRect(x: index, y: (index * 7) % 28, width: 1, height: 1))
            }
        }
    }

    @objc private func profileTabTapped(_ sender: UIControl) {
        let visibleSections = tabPreferences.visibleSections
        guard visibleSections.indices.contains(sender.tag) else { return }
        let section = visibleSections[sender.tag]
        let profileContentViewModel = contentViewModel
        Task { @MainActor in
            await profileContentViewModel.select(section)
        }
    }

    private func reconcileVisibleProfileSection() {
        let visibleSections = tabPreferences.visibleSections
        guard let firstSection = visibleSections.first else { return }
        guard visibleSections.contains(contentViewModel.section) else {
            configureTabs(selectedSection: firstSection)
            let profileContentViewModel = contentViewModel
            Task { @MainActor [weak self] in
                await profileContentViewModel.select(firstSection)
                self?.configureTabs()
            }
            return
        }
        configureTabs()
    }

    private func openContentRow(_ row: UserProfileContentRow) {
        switch row {
        case .summaryTopic(let topic):
            openTopic(id: topic.id, floor: nil)
        case .summaryReply(let reply):
            guard let topicId = reply.topicId else { return }
            openTopic(id: topicId, floor: reply.postNumber)
        case .summaryLink(let link):
            guard let url = URL(string: link.url) else { return }
            UIApplication.shared.open(url)
        case .summaryUser(_, let user):
            guard !user.username.isEmpty else { return }
            navigationController?.pushViewController(
                UserProfileViewController(api: api, username: user.username),
                animated: true
            )
        case .summaryCategory(let category):
            let alert = UIAlertController(
                title: category.name,
                message: "\(category.topicCount) topics · \(category.postCount) posts",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
            present(alert, animated: true)
        case .summaryBadge(let badge):
            let alert = UIAlertController(title: badge.name, message: badge.description, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
            present(alert, animated: true)
        case .action(let action):
            openTopic(id: action.topicId, floor: action.postNumber)
        case .reaction(let reaction):
            openTopic(id: reaction.topicId, floor: reaction.postNumber)
        case .header:
            break
        }
    }

    private func openTopic(id: Int, floor: Int?) {
        guard id > 0 else { return }
        let detail = TopicDetailViewController(api: api, topicId: id, initialFloor: floor)
        navigationController?.pushViewController(detail, animated: true)
    }

    @objc private func openTopics() {
        let vc = UserPostsViewController(api: api, username: viewModel.username, filter: .topics)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func openPosts() {
        let vc = UserPostsViewController(api: api, username: viewModel.username, filter: .posts)
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func openSummaryTopic(_ sender: UIControl) {
        guard sender.tag > 0 else { return }
        let detailVC = TopicDetailViewController(api: api, topicId: sender.tag)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    @objc private func searchTapped() {
        let query = "@\(viewModel.username) order:latest"
        navigationController?.pushViewController(
            SearchViewController(api: api, initialQuery: query),
            animated: true
        )
    }

    @objc private func messageTapped() {
        let composer = PrivateMessageComposerViewController(api: api, recipient: viewModel.username)
        present(UINavigationController(rootViewController: composer), animated: true)
    }

    @objc private func followTapped() {
        performRelationship(.toggleFollow)
    }

    @objc private func bioTapped() {
        let profile = viewModel.userProfile
        let bio = UserProfileFormatting.cleanBio(profile?.bioCooked ?? profile?.bioRaw ?? profile?.bioExcerpt)
            ?? String(localized: "user.profile.no_bio")
        let controller = UIViewController()
        controller.title = UserProfileFormatting.displayName(profile: profile, fallbackUsername: viewModel.username)
        controller.view.backgroundColor = AppSettings.shared.themeStyle.contentBackgroundColor
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.font = AppSettings.shared.contentFont(ofSize: 17)
        textView.text = bio
        controller.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        ])
        let navigation = UINavigationController(rootViewController: controller)
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done,
            primaryAction: UIAction { [weak navigation] _ in navigation?.dismiss(animated: true) }
        )
        present(navigation, animated: true)
    }

    @objc private func socialStatTapped(_ sender: UIButton) {
        let mode: UserSocialListViewController.Mode = sender.tag == 0 ? .following : .followers
        navigationController?.pushViewController(
            UserSocialListViewController(api: api, username: viewModel.username, mode: mode),
            animated: true
        )
    }

    private func shareUser() {
        let base = api.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/u/\(viewModel.username)") else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = moreBarButton
        present(activity, animated: true)
    }

}

private final class ProfileTabButton: UIControl {
    private let titleLabel = UILabel()
    private let indicatorView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        indicatorView.layer.cornerRadius = 2
        indicatorView.layer.cornerCurve = .continuous
        addSubview(indicatorView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),

            indicatorView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            indicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicatorView.widthAnchor.constraint(equalToConstant: 26),
            indicatorView.heightAnchor.constraint(equalToConstant: 3),
        ])
    }

    func configure(title: String, selected: Bool) {
        titleLabel.text = title
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 15,
            weight: selected ? .bold : .semibold,
            fallback: .systemFont(ofSize: 15, weight: selected ? .bold : .semibold)
        )
        titleLabel.textColor = selected ? AppSettings.shared.themeStyle.accentColor : .secondaryLabel
        indicatorView.backgroundColor = selected ? AppSettings.shared.themeStyle.accentColor : .clear
        accessibilityTraits = selected ? [.button, .selected] : [.button]
    }
}

private final class SummaryTopicCard: UIControl {
    private let titleLabel = UILabel()
    private let likesLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        accessibilityTraits = .button

        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 17,
            weight: .heavy,
            fallback: .systemFont(ofSize: 17, weight: .heavy)
        )
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

        let heart = UIImageView(image: UIImage(systemName: "heart"))
        heart.tintColor = .secondaryLabel
        heart.contentMode = .scaleAspectFit
        heart.translatesAutoresizingMaskIntoConstraints = false

        likesLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .bold,
            fallback: .systemFont(ofSize: 14, weight: .bold)
        )
        likesLabel.textColor = .secondaryLabel

        let right = UIStackView(arrangedSubviews: [heart, likesLabel])
        right.axis = .horizontal
        right.alignment = .center
        right.spacing = 6

        let row = UIStackView(arrangedSubviews: [titleLabel, right])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
            heart.widthAnchor.constraint(equalToConstant: 18),
            heart.heightAnchor.constraint(equalToConstant: 18),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    func configure(topic: DiscourseUserSummaryTopic) {
        titleLabel.text = topic.title
        likesLabel.text = UserProfileFormatting.compactNumber(topic.likesCount)
        accessibilityLabel = topic.title
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
