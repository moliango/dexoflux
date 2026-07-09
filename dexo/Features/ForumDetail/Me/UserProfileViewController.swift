import UIKit

final class UserProfileViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: UserProfileViewModel

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
    private let tabStack = UIStackView()
    private let topicListStack = UIStackView()
    private let entryStack = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()

    private var savedStandardAppearance: UINavigationBarAppearance?
    private var savedScrollEdgeAppearance: UINavigationBarAppearance?
    private var savedCompactAppearance: UINavigationBarAppearance?
    private var savedTintColor: UIColor?

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.viewModel = UserProfileViewModel(api: api, username: username)
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
        Task {
            await viewModel.load()
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
            return
        }

        contentView.alpha = 1
        configure(profile: profile, summary: viewModel.summary, topics: viewModel.summaryTopics)
    }

    private func setupNavigationItems() {
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: #selector(unavailableActionTapped)),
            UIBarButtonItem(image: UIImage(systemName: "envelope"), style: .plain, target: self, action: #selector(unavailableActionTapped)),
            UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(unavailableActionTapped)),
        ]
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
            heroView.heightAnchor.constraint(equalToConstant: 520),

            panelView.topAnchor.constraint(equalTo: heroView.bottomAnchor, constant: -42),
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
        avatarImageView.layer.cornerRadius = 42
        avatarImageView.layer.borderWidth = 3
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.backgroundColor = .secondarySystemFill

        displayNameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 34,
            weight: .heavy,
            fallback: .systemFont(ofSize: 34, weight: .heavy)
        )
        displayNameLabel.textColor = .white
        displayNameLabel.numberOfLines = 1
        displayNameLabel.adjustsFontSizeToFitWidth = true
        displayNameLabel.minimumScaleFactor = 0.68

        usernameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 18,
            weight: .semibold,
            fallback: .systemFont(ofSize: 18, weight: .semibold)
        )
        usernameLabel.textColor = UIColor.white.withAlphaComponent(0.78)

        levelLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .bold,
            fallback: .systemFont(ofSize: 14, weight: .bold)
        )
        levelLabel.textColor = .white
        levelLabel.textAlignment = .center
        levelLabel.layer.cornerRadius = 8
        levelLabel.layer.cornerCurve = .continuous
        levelLabel.clipsToBounds = true

        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .semibold,
            fallback: .systemFont(ofSize: 14, weight: .semibold)
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
        followButton.addTarget(self, action: #selector(unavailableActionTapped), for: .touchUpInside)

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
            avatarImageView.topAnchor.constraint(equalTo: heroView.safeAreaLayoutGuide.topAnchor, constant: 210),
            avatarImageView.widthAnchor.constraint(equalToConstant: 84),
            avatarImageView.heightAnchor.constraint(equalToConstant: 84),

            nameStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 18),
            nameStack.trailingAnchor.constraint(lessThanOrEqualTo: followButton.leadingAnchor, constant: -14),
            nameStack.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),

            followButton.trailingAnchor.constraint(equalTo: heroView.trailingAnchor, constant: -24),
            followButton.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            followButton.heightAnchor.constraint(equalToConstant: 50),
            followButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104),

            levelLabel.heightAnchor.constraint(equalToConstant: 28),
            levelLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),

            bioCard.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 36),
            bioCard.leadingAnchor.constraint(equalTo: heroView.leadingAnchor, constant: 24),
            bioCard.trailingAnchor.constraint(equalTo: heroView.trailingAnchor, constant: -24),
            bioCard.heightAnchor.constraint(greaterThanOrEqualToConstant: 58),

            statsStack.topAnchor.constraint(equalTo: bioCard.bottomAnchor, constant: 22),
            statsStack.leadingAnchor.constraint(equalTo: heroView.leadingAnchor, constant: 26),
            statsStack.trailingAnchor.constraint(lessThanOrEqualTo: heroView.trailingAnchor, constant: -24),

            recencyPill.topAnchor.constraint(equalTo: statsStack.bottomAnchor, constant: 14),
            recencyPill.leadingAnchor.constraint(equalTo: heroView.leadingAnchor, constant: 26),
            recencyPill.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func setupBioCard() {
        bioCard.translatesAutoresizingMaskIntoConstraints = false
        bioCard.layer.cornerRadius = 10
        bioCard.layer.cornerCurve = .continuous
        bioCard.addTarget(self, action: #selector(unavailableActionTapped), for: .touchUpInside)

        bioLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 17,
            weight: .medium,
            fallback: .systemFont(ofSize: 17, weight: .medium)
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
        panelStack.spacing = 18
        panelStack.translatesAutoresizingMaskIntoConstraints = false
        panelView.addSubview(panelStack)

        tabStack.axis = .horizontal
        tabStack.distribution = .fillEqually
        tabStack.spacing = 0
        panelStack.addArrangedSubview(tabStack)

        topicListStack.axis = .vertical
        topicListStack.spacing = 10
        panelStack.addArrangedSubview(topicListStack)

        entryStack.axis = .vertical
        entryStack.spacing = 14
        panelStack.addArrangedSubview(entryStack)

        NSLayoutConstraint.activate([
            panelStack.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 20),
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

    private func configure(profile: DiscourseUserProfile, summary: DiscourseUserSummary?, topics: [DiscourseUserSummaryTopic]) {
        let displayName = UserProfileFormatting.displayName(profile: profile, fallbackUsername: viewModel.username)
        displayNameLabel.text = displayName
        usernameLabel.text = "@\(profile.username)"
        levelLabel.text = UserProfileFormatting.trustLevelText(profile.trustLevel)
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
        configureStats(profile: profile, summary: summary)
        configureTabs()
        configureSummaryTopics(topics)
        configureEntryCards()
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

    private func configureStats(profile: DiscourseUserProfile, summary: DiscourseUserSummary?) {
        statsStack.arrangedSubviews.forEach { view in
            statsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let firstRowItems = [
            profile.followingCount.map { (UserProfileFormatting.compactNumber($0), String(localized: "user.profile.following")) },
            profile.followerCount.map { (UserProfileFormatting.compactNumber($0), String(localized: "user.profile.followers")) },
        ].compactMap { $0 }

        if !firstRowItems.isEmpty {
            statsStack.addArrangedSubview(makeStatRow(firstRowItems, valueSize: 22, labelSize: 16, spacing: 18))
        }

        let secondRowItems: [(String, String)] = [
            (UserProfileFormatting.compactNumber(summary?.likesReceived), String(localized: "me.stats.likes")),
            (UserProfileFormatting.compactNumber(summary?.daysVisited), String(localized: "me.stats.days")),
            (UserProfileFormatting.compactNumber(summary?.topicCount), String(localized: "me.stats.topics")),
            (UserProfileFormatting.compactNumber(summary?.postCount), String(localized: "me.stats.posts")),
        ]
        statsStack.addArrangedSubview(makeStatRow(secondRowItems, valueSize: 28, labelSize: 17, spacing: 16))
    }

    private func configureTabs() {
        tabStack.arrangedSubviews.forEach { view in
            tabStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let tabs: [(String, Selector?)] = [
            (String(localized: "user.profile.summary"), nil),
            (String(localized: "user.profile.activity"), #selector(unavailableActionTapped)),
            (String(localized: "user.topics_title"), #selector(openTopics)),
            (String(localized: "user.profile.replies"), #selector(openPosts)),
            (String(localized: "me.stats.likes"), #selector(unavailableActionTapped)),
            (String(localized: "user.profile.reactions"), #selector(unavailableActionTapped)),
        ]

        for (index, tab) in tabs.enumerated() {
            let button = ProfileTabButton()
            button.configure(title: tab.0, selected: index == 0)
            if let selector = tab.1 {
                button.addTarget(self, action: selector, for: .touchUpInside)
            }
            tabStack.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 54).isActive = true
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

        for actionCard in entryStack.arrangedSubviews.compactMap({ $0 as? UserProfileActionCard }) {
            actionCard.backgroundColor = theme.topicCardBackgroundColor
        }
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

    @objc private func unavailableActionTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let alert = UIAlertController(
            title: nil,
            message: String(localized: "user.profile.action_unavailable"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
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
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),

            indicatorView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            indicatorView.centerXAnchor.constraint(equalTo: centerXAnchor),
            indicatorView.widthAnchor.constraint(equalToConstant: 34),
            indicatorView.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    func configure(title: String, selected: Bool) {
        titleLabel.text = title
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: selected ? .heavy : .bold,
            fallback: .systemFont(ofSize: 16, weight: selected ? .heavy : .bold)
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
