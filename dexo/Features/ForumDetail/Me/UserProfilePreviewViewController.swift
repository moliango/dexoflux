import UIKit

private final class ProfilePreviewButton: UIButton {
    private let minimumHitTarget = CGSize(width: 44, height: 44)

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let horizontalInset = min(0, (bounds.width - minimumHitTarget.width) / 2)
        let verticalInset = min(0, (bounds.height - minimumHitTarget.height) / 2)
        return bounds.insetBy(dx: horizontalInset, dy: verticalInset).contains(point)
    }
}

final class UserProfilePreviewViewController: ObservableViewController {
    var onViewProfile: ((String) -> Void)?

    private let api: DiscourseAPI
    private let viewModel: UserProfileViewModel

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let dimView = UIView()
    private let cardView = UIView()
    private let cardStack = UIStackView()
    private let watermarkLabel = UILabel()
    private let avatarHaloView = UIView()
    private let avatarImageView = UIImageView()
    private let flairImageView = UIImageView()
    private let displayNameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let levelLabel = UILabel()
    private let titleLabel = UILabel()
    private let bioLabel = UILabel()
    private let locationWebsiteStack = UIStackView()
    private let factsLabel = UILabel()
    private let statsLabel = UILabel()
    private let actionSpacerView = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()
    private var lastPresentedRelationshipError: String?

    private lazy var messageButton = makeActionButton(
        title: String(localized: "user.profile.private_message"),
        symbolName: "envelope.fill",
        style: .filled
    )

    private lazy var followButton = makeActionButton(
        title: String(localized: "user.profile.follow"),
        symbolName: "person.badge.plus.fill",
        style: .tinted
    )

    private lazy var viewProfileButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "user.profile.view_profile")
        config.image = UIImage(systemName: "person.crop.circle")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseForegroundColor = AppSettings.shared.themeStyle.accentColor
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        config.titleTextAttributesTransformer = compactButtonTextAttributes(size: 11.5)
        let button = ProfilePreviewButton(type: .system)
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.addTarget(self, action: #selector(viewProfileTapped), for: .touchUpInside)
        return button
    }()

    private lazy var moreButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "ellipsis")
        config.cornerStyle = .capsule
        config.baseForegroundColor = .label
        config.contentInsets = .zero
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let button = ProfilePreviewButton(type: .system)
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 16
        button.layer.cornerCurve = .continuous
        button.accessibilityLabel = String(localized: "user.profile.more")
        button.showsMenuAsPrimaryAction = true
        return button
    }()

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.viewModel = UserProfileViewModel(api: api, username: username)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        Task {
            await viewModel.load()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cardView.layer.shadowPath = UIBezierPath(
            roundedRect: cardView.bounds,
            cornerRadius: cardView.layer.cornerRadius
        ).cgPath
    }

    override func updateUI() {
        applyTheme()

        loadingIndicator.isHidden = !viewModel.isLoading
        viewModel.isLoading ? loadingIndicator.startAnimating() : loadingIndicator.stopAnimating()
        errorLabel.isHidden = viewModel.errorMessage == nil
        errorLabel.text = viewModel.errorMessage

        guard let profile = viewModel.userCard ?? viewModel.userProfile else {
            configurePlaceholder()
            return
        }

        cardView.alpha = 1
        configureProfile(profile, summary: viewModel.summary)
        configureActions(profile: profile)
        presentRelationshipErrorIfNeeded()
    }

    private func setupUI() {
        view.backgroundColor = .clear

        blurView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blurView)

        dimView.translatesAutoresizingMaskIntoConstraints = false
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backgroundTapped)))
        view.addSubview(dimView)

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 24
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.18
        cardView.layer.shadowRadius = 24
        cardView.layer.shadowOffset = CGSize(width: 0, height: 12)
        view.addSubview(cardView)

        watermarkLabel.translatesAutoresizingMaskIntoConstraints = false
        watermarkLabel.text = "LINUX DO"
        watermarkLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 54,
            weight: .black,
            fallback: .systemFont(ofSize: 54, weight: .black)
        )
        watermarkLabel.textAlignment = .center
        watermarkLabel.adjustsFontSizeToFitWidth = true
        watermarkLabel.minimumScaleFactor = 0.55
        cardView.addSubview(watermarkLabel)

        cardStack.axis = .vertical
        cardStack.spacing = 11
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(cardStack)

        setupIdentity()
        setupBody()
        setupActions()
        setupAvatar()
        setupLoadingAndError()

        let centerY = cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -44)
        centerY.priority = .defaultHigh
        let preferredWidth = cardView.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -44)
        preferredWidth.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 22),
            cardView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -22),
            cardView.widthAnchor.constraint(lessThanOrEqualToConstant: 390),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 330),
            preferredWidth,
            cardView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            centerY,

            watermarkLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            watermarkLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor, constant: -8),
            watermarkLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: -18),
            watermarkLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: 18),

            cardStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 42),
            cardStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 17),
            cardStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -17),
            cardStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    private func setupIdentity() {
        displayNameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 18,
            weight: .heavy,
            fallback: .systemFont(ofSize: 18, weight: .heavy)
        )
        displayNameLabel.textColor = .label
        displayNameLabel.numberOfLines = 1
        displayNameLabel.adjustsFontSizeToFitWidth = true
        displayNameLabel.minimumScaleFactor = 0.72

        usernameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 11,
            weight: .semibold,
            fallback: .systemFont(ofSize: 11, weight: .semibold)
        )
        usernameLabel.textColor = .secondaryLabel
        usernameLabel.numberOfLines = 1
        usernameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        levelLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 11,
            weight: .bold,
            fallback: .systemFont(ofSize: 11, weight: .bold)
        )
        levelLabel.textAlignment = .center
        levelLabel.layer.cornerRadius = 6
        levelLabel.layer.cornerCurve = .continuous
        levelLabel.clipsToBounds = true
        levelLabel.isHidden = true
        levelLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 11,
            weight: .semibold,
            fallback: .systemFont(ofSize: 11, weight: .semibold)
        )
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 1

        let usernameRow = UIStackView(arrangedSubviews: [usernameLabel, levelLabel])
        usernameRow.axis = .horizontal
        usernameRow.alignment = .center
        usernameRow.spacing = 5

        let nameStack = UIStackView(arrangedSubviews: [displayNameLabel, usernameRow, titleLabel])
        nameStack.axis = .vertical
        nameStack.spacing = 3
        nameStack.alignment = .leading

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let row = UIStackView(arrangedSubviews: [spacer, nameStack])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 0
        cardStack.addArrangedSubview(row)

        let levelHeightConstraint = levelLabel.heightAnchor.constraint(equalToConstant: 22)
        levelHeightConstraint.priority = UILayoutPriority(999)
        let levelWidthConstraint = levelLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 68)
        levelWidthConstraint.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([levelHeightConstraint, levelWidthConstraint])
    }

    private func setupBody() {
        bioLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 12.75,
            weight: .regular,
            fallback: .systemFont(ofSize: 12.75, weight: .regular)
        )
        bioLabel.textColor = .label
        bioLabel.numberOfLines = 3
        bioLabel.lineBreakMode = .byTruncatingTail
        cardStack.addArrangedSubview(bioLabel)

        locationWebsiteStack.axis = .horizontal
        locationWebsiteStack.alignment = .center
        locationWebsiteStack.spacing = 12
        cardStack.addArrangedSubview(locationWebsiteStack)

        factsLabel.numberOfLines = 0
        factsLabel.lineBreakMode = .byWordWrapping
        cardStack.addArrangedSubview(factsLabel)

        statsLabel.numberOfLines = 0
        statsLabel.lineBreakMode = .byWordWrapping
        statsLabel.adjustsFontSizeToFitWidth = true
        statsLabel.minimumScaleFactor = 0.85
        cardStack.addArrangedSubview(statsLabel)
    }

    private func setupActions() {
        messageButton.addTarget(self, action: #selector(messageTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(followTapped), for: .touchUpInside)

        let primaryRow = UIStackView(arrangedSubviews: [messageButton, followButton])
        primaryRow.axis = .horizontal
        primaryRow.distribution = .fillEqually
        primaryRow.spacing = 8

        let bottomRow = UIStackView(arrangedSubviews: [viewProfileButton, moreButton])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 8

        actionSpacerView.isUserInteractionEnabled = false
        actionSpacerView.setContentHuggingPriority(.defaultLow, for: .vertical)
        actionSpacerView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        cardStack.addArrangedSubview(actionSpacerView)
        cardStack.addArrangedSubview(primaryRow)
        cardStack.setCustomSpacing(6, after: primaryRow)
        cardStack.addArrangedSubview(bottomRow)

        NSLayoutConstraint.activate([
            actionSpacerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 14),
            messageButton.heightAnchor.constraint(equalToConstant: 34),
            followButton.heightAnchor.constraint(equalToConstant: 34),
            viewProfileButton.heightAnchor.constraint(equalToConstant: 32),
            moreButton.widthAnchor.constraint(equalToConstant: 42),
            moreButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func setupAvatar() {
        avatarHaloView.translatesAutoresizingMaskIntoConstraints = false
        avatarHaloView.layer.cornerRadius = 36
        avatarHaloView.layer.cornerCurve = .continuous
        avatarHaloView.layer.borderWidth = 2
        avatarHaloView.isUserInteractionEnabled = false
        view.addSubview(avatarHaloView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 31
        avatarImageView.layer.borderWidth = 2
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.backgroundColor = .secondarySystemFill
        avatarHaloView.addSubview(avatarImageView)

        flairImageView.translatesAutoresizingMaskIntoConstraints = false
        flairImageView.contentMode = .scaleAspectFit
        flairImageView.clipsToBounds = true
        flairImageView.layer.cornerRadius = 10
        flairImageView.layer.cornerCurve = .continuous
        flairImageView.layer.borderWidth = 1.5
        flairImageView.isHidden = true
        flairImageView.isUserInteractionEnabled = false
        view.addSubview(flairImageView)

        NSLayoutConstraint.activate([
            avatarHaloView.widthAnchor.constraint(equalToConstant: 72),
            avatarHaloView.heightAnchor.constraint(equalTo: avatarHaloView.widthAnchor),
            avatarHaloView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            avatarHaloView.centerYAnchor.constraint(equalTo: cardView.topAnchor),

            avatarImageView.centerXAnchor.constraint(equalTo: avatarHaloView.centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: avatarHaloView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 62),
            avatarImageView.heightAnchor.constraint(equalToConstant: 62),

            flairImageView.trailingAnchor.constraint(equalTo: avatarHaloView.trailingAnchor, constant: 3),
            flairImageView.bottomAnchor.constraint(equalTo: avatarHaloView.bottomAnchor, constant: 1),
            flairImageView.widthAnchor.constraint(equalToConstant: 22),
            flairImageView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func setupLoadingAndError() {
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(loadingIndicator)

        errorLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 13,
            weight: .medium,
            fallback: .systemFont(ofSize: 13, weight: .medium)
        )
        errorLabel.textColor = .secondaryLabel
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            loadingIndicator.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            errorLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            errorLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
        ])
    }

    private func configurePlaceholder() {
        displayNameLabel.text = viewModel.username
        usernameLabel.text = "@\(viewModel.username)"
        levelLabel.text = nil
        levelLabel.isHidden = true
        titleLabel.text = nil
        titleLabel.isHidden = true
        bioLabel.text = viewModel.isLoading ? " " : String(localized: "user.profile.no_bio")
        factsLabel.attributedText = nil
        statsLabel.attributedText = nil
        locationWebsiteStack.isHidden = true
        flairImageView.isHidden = true
        cardView.alpha = viewModel.isLoading ? 0.88 : 1
    }

    private func configureProfile(_ profile: DiscourseUserProfile, summary: DiscourseUserSummary?) {
        displayNameLabel.text = UserProfileFormatting.displayName(profile: profile, fallbackUsername: viewModel.username)
        usernameLabel.text = "@\(profile.username)"
        let levelText = UserProfileFormatting.trustLevelText(profile.trustLevel)
        levelLabel.text = levelText
        levelLabel.isHidden = levelText == nil
        titleLabel.text = profile.title
        titleLabel.isHidden = (profile.title ?? "").isEmpty

        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: profile.avatarTemplate,
            baseURL: api.baseURL,
            size: 240
        )
        configureFlair(profile.flairUrl)

        bioLabel.text = UserProfileFormatting.cleanBio(profile.bioExcerpt) ?? String(localized: "user.profile.no_bio")
        configureLocationWebsite(profile: profile)
        configureFacts(profile: profile)
        configureStats(profile: profile, summary: summary)
    }

    private func configureFlair(_ flairUrl: String?) {
        guard let url = resolvedFlairURL(flairUrl) else {
            flairImageView.isHidden = true
            flairImageView.image = nil
            return
        }

        flairImageView.isHidden = false
        ForumImageLoader.setImage(on: flairImageView, url: url)
    }

    private func configureLocationWebsite(profile: DiscourseUserProfile) {
        locationWebsiteStack.arrangedSubviews.forEach { view in
            locationWebsiteStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let location = profile.location?.trimmedNonEmpty {
            locationWebsiteStack.addArrangedSubview(makeInlineIconText(symbolName: "location", text: location))
        }

        if let website = (profile.websiteName?.trimmedNonEmpty ?? profile.website?.trimmedNonEmpty) {
            locationWebsiteStack.addArrangedSubview(makeInlineIconText(symbolName: "link", text: website))
        }

        locationWebsiteStack.isHidden = locationWebsiteStack.arrangedSubviews.isEmpty
    }

    private func configureFacts(profile: DiscourseUserProfile) {
        var items: [(String, String)] = []
        if let lastPostedAt = profile.lastPostedAt {
            items.append((String(localized: "user.profile.last_posted"), UserProfileFormatting.relativeDate(lastPostedAt)))
        }
        items.append((String(localized: "user.profile.joined"), UserProfileFormatting.shortDate(profile.createdAt)))
        items.append((String(localized: "user.profile.read_time"), UserProfileFormatting.duration(seconds: profile.timeRead)))
        factsLabel.attributedText = makeInlineMetricText(items: items, baseSize: 10.25, separator: "   ")
    }

    private func configureStats(profile: DiscourseUserProfile, summary: DiscourseUserSummary?) {
        var socialItems: [(String, String)] = []
        if let following = profile.followingCount {
            socialItems.append((String(localized: "user.profile.following"), UserProfileFormatting.compactNumber(following)))
        }
        if let followers = profile.followerCount {
            socialItems.append((String(localized: "user.profile.followers"), UserProfileFormatting.compactNumber(followers)))
        }
        if let score = profile.gamificationScore {
            socialItems.append((String(localized: "user.profile.score"), UserProfileFormatting.compactNumber(score)))
        }

        let fallbackItems: [(String, String)] = [
            (String(localized: "me.stats.topics"), UserProfileFormatting.compactNumber(summary?.topicCount)),
            (String(localized: "me.stats.posts"), UserProfileFormatting.compactNumber(summary?.postCount)),
            (String(localized: "me.stats.likes"), UserProfileFormatting.compactNumber(summary?.likesReceived)),
            (String(localized: "me.stats.profile_views"), UserProfileFormatting.compactNumber(profile.profileViewCount)),
        ]
        statsLabel.attributedText = makeInlineMetricText(
            items: socialItems.isEmpty ? fallbackItems : socialItems,
            baseSize: 10.75,
            separator: "   "
        )
    }

    private func configureActions(profile: DiscourseUserProfile) {
        let state = viewModel.relationshipController.state
        let currentUsername = AuthManager.shared.username(for: api.baseURL)
        let isCurrentUser = currentUsername?.caseInsensitiveCompare(profile.username) == .orderedSame

        messageButton.isHidden = isCurrentUser || !state.canSendPrivateMessage
        followButton.isHidden = isCurrentUser || !state.canFollow
        messageButton.isEnabled = !state.isMutating
        followButton.isEnabled = !state.isMutating
        moreButton.isEnabled = !state.isMutating

        var followConfig = followButton.configuration
        followConfig?.title = state.isFollowed
            ? String(localized: "user.profile.unfollow", defaultValue: "Unfollow")
            : String(localized: "user.profile.follow")
        followConfig?.image = UIImage(systemName: state.isFollowed ? "person.badge.minus.fill" : "person.badge.plus.fill")
        followButton.configuration = followConfig

        moreButton.menu = makeMoreMenu(isCurrentUser: isCurrentUser)
    }

    private func makeMoreMenu(isCurrentUser: Bool) -> UIMenu {
        let state = viewModel.relationshipController.state
        var children: [UIMenuElement] = []

        if !isCurrentUser {
            if state.isMuted || state.isIgnored {
                children.append(UIAction(
                    title: String(localized: "user.profile.restore_notifications", defaultValue: "Restore notifications"),
                    image: UIImage(systemName: "bell")
                ) { [weak self] _ in
                    self?.performRelationshipMutation(.restore)
                })
            } else {
                if state.canMute {
                    children.append(UIAction(
                        title: String(localized: "user.profile.mute", defaultValue: "Mute"),
                        image: UIImage(systemName: "speaker.slash")
                    ) { [weak self] _ in
                        self?.performRelationshipMutation(.mute)
                    })
                }
                if state.canIgnore {
                    children.append(makeIgnoreMenu())
                }
            }
        }

        children.append(UIAction(
            title: String(localized: "user.profile.share", defaultValue: "Share user"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.shareUser()
        })
        return UIMenu(children: children)
    }

    private func makeIgnoreMenu() -> UIMenu {
        let calendar = Calendar.current
        let now = Date()
        let presets: [(String, Date)] = [
            (String(localized: "user.profile.ignore.day", defaultValue: "For one day"), calendar.date(byAdding: .day, value: 1, to: now) ?? now),
            (String(localized: "user.profile.ignore.week", defaultValue: "For one week"), calendar.date(byAdding: .day, value: 7, to: now) ?? now),
            (String(localized: "user.profile.ignore.month", defaultValue: "For one month"), calendar.date(byAdding: .month, value: 1, to: now) ?? now),
        ]
        var actions: [UIAction] = presets.map { title, expiry in
            UIAction(title: title, image: UIImage(systemName: "clock")) { [weak self] _ in
                self?.performRelationshipMutation(.ignore(until: expiry))
            }
        }
        actions.append(UIAction(
            title: String(localized: "user.profile.ignore.custom", defaultValue: "Custom date"),
            image: UIImage(systemName: "calendar")
        ) { [weak self] _ in
            self?.showCustomIgnorePicker()
        })
        return UIMenu(
            title: String(localized: "user.profile.ignore", defaultValue: "Ignore"),
            image: UIImage(systemName: "person.crop.circle.badge.xmark"),
            children: actions
        )
    }

    private func performRelationshipMutation(_ mutation: UserRelationshipMutation) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { @MainActor [weak self] in
            await self?.viewModel.relationshipController.perform(mutation)
        }
    }

    private func showCustomIgnorePicker() {
        let picker = UIDatePicker()
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        picker.minimumDate = Date().addingTimeInterval(60 * 10)
        picker.date = Date().addingTimeInterval(60 * 60 * 24)
        picker.translatesAutoresizingMaskIntoConstraints = false

        let controller = UIViewController()
        controller.view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: controller.view.topAnchor),
            picker.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        ])
        controller.preferredContentSize = CGSize(width: 330, height: 360)

        let alert = UIAlertController(
            title: String(localized: "user.profile.ignore", defaultValue: "Ignore"),
            message: nil,
            preferredStyle: .alert
        )
        alert.setValue(controller, forKey: "contentViewController")
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(
            title: String(localized: "action.confirm", defaultValue: "Confirm"),
            style: .default
        ) { [weak self] _ in
            self?.performRelationshipMutation(.ignore(until: picker.date))
        })
        present(alert, animated: true)
    }

    private func shareUser() {
        let username = viewModel.userCard?.username ?? viewModel.userProfile?.username ?? viewModel.username
        let base = api.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/u/\(username)") else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = moreButton
        activity.popoverPresentationController?.sourceRect = moreButton.bounds
        present(activity, animated: true)
    }

    private func presentRelationshipErrorIfNeeded() {
        guard let message = viewModel.relationshipController.state.errorMessage,
              message != lastPresentedRelationshipError,
              presentedViewController == nil
        else { return }
        lastPresentedRelationshipError = message
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel) { [weak self] _ in
            self?.viewModel.relationshipController.clearError()
        })
        present(alert, animated: true)
    }

    private func makeInlineIconText(symbolName: String, text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.font = AppSettings.shared.appInterfaceFont(
            ofSize: 10.5,
            weight: .medium,
            fallback: .systemFont(ofSize: 10.5, weight: .medium)
        )
        label.textColor = .secondaryLabel
        label.text = text
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 12),
            icon.heightAnchor.constraint(equalToConstant: 12),
        ])

        return stack
    }

    private func makeInlineMetricText(items: [(String, String)], baseSize: CGFloat, separator: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let labelFont = AppSettings.shared.appInterfaceFont(
            ofSize: baseSize,
            weight: .medium,
            fallback: .systemFont(ofSize: baseSize, weight: .medium)
        )
        let valueFont = AppSettings.shared.appInterfaceFont(
            ofSize: baseSize,
            weight: .heavy,
            fallback: .systemFont(ofSize: baseSize, weight: .heavy)
        )

        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: separator))
            }
            result.append(NSAttributedString(
                string: "\(item.0) ",
                attributes: [.font: labelFont, .foregroundColor: UIColor.secondaryLabel]
            ))
            result.append(NSAttributedString(
                string: item.1,
                attributes: [.font: valueFont, .foregroundColor: UIColor.label]
            ))
        }
        return result
    }

    private func makeActionButton(title: String, symbolName: String, style: ActionButtonStyle) -> UIButton {
        var config: UIButton.Configuration = style == .filled ? .filled() : .tinted()
        config.title = title
        config.image = UIImage(systemName: symbolName)
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.baseForegroundColor = style == .filled ? .white : AppSettings.shared.themeStyle.accentColor
        config.baseBackgroundColor = AppSettings.shared.themeStyle.accentColor
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        config.titleTextAttributesTransformer = compactButtonTextAttributes(size: 11.5)
        let button = ProfilePreviewButton(type: .system)
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func compactButtonTextAttributes(size: CGFloat) -> UIConfigurationTextAttributesTransformer {
        let font = AppSettings.shared.appInterfaceFont(
            ofSize: size,
            weight: .bold,
            fallback: .systemFont(ofSize: size, weight: .bold)
        )
        return UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = font
            return updated
        }
    }

    private func applyTheme() {
        let theme = AppSettings.shared.themeStyle
        let cardBackground = theme.topicCardBackgroundColor
        let resolvedCardBackground = cardBackground.resolvedColor(with: traitCollection)
        cardView.backgroundColor = cardBackground.withAlphaComponent(0.98)
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = theme.accentColor.withAlphaComponent(0.14).cgColor
        watermarkLabel.textColor = theme.accentColor.withAlphaComponent(0.08)

        avatarHaloView.backgroundColor = cardBackground
        avatarHaloView.layer.borderColor = theme.accentColor.withAlphaComponent(0.28).cgColor
        avatarImageView.layer.borderColor = resolvedCardBackground.cgColor
        flairImageView.backgroundColor = cardBackground
        flairImageView.layer.borderColor = resolvedCardBackground.cgColor

        levelLabel.backgroundColor = theme.accentColor.withAlphaComponent(0.14)
        levelLabel.textColor = theme.accentColor
        viewProfileButton.layer.borderColor = theme.accentColor.withAlphaComponent(0.42).cgColor
        moreButton.layer.borderColor = theme.accentColor.withAlphaComponent(0.24).cgColor

        var messageConfig = messageButton.configuration
        messageConfig?.baseBackgroundColor = theme.accentColor
        messageConfig?.baseForegroundColor = .white
        messageButton.configuration = messageConfig

        var followConfig = followButton.configuration
        followConfig?.baseBackgroundColor = theme.accentColor.withAlphaComponent(0.16)
        followConfig?.baseForegroundColor = theme.accentColor
        followButton.configuration = followConfig

        var profileConfig = viewProfileButton.configuration
        profileConfig?.baseForegroundColor = theme.accentColor
        viewProfileButton.configuration = profileConfig
    }

    private func resolvedFlairURL(_ flairUrl: String?) -> URL? {
        guard let flairUrl = flairUrl?.trimmedNonEmpty else { return nil }
        if flairUrl.hasPrefix(":") && flairUrl.hasSuffix(":") {
            let emojiName = String(flairUrl.dropFirst().dropLast())
            if EmojiStore.lookupMap.isEmpty {
                _ = EmojiStore.load(for: api.baseURL)
            }
            guard let urlString = EmojiStore.url(for: emojiName) else { return nil }
            return URL(string: urlString)
        }
        if let absoluteURL = URL(string: flairUrl), absoluteURL.scheme != nil {
            return absoluteURL
        }
        let normalizedPath = flairUrl.hasPrefix("/") ? flairUrl : "/\(flairUrl)"
        return URL(string: api.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + normalizedPath)
    }

    @objc private func backgroundTapped() {
        dismiss(animated: true)
    }

    @objc private func viewProfileTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let username = viewModel.userProfile?.username ?? viewModel.username
        dismiss(animated: true) { [onViewProfile] in
            onViewProfile?(username)
        }
    }

    @objc private func messageTapped() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let username = viewModel.userCard?.username ?? viewModel.userProfile?.username ?? viewModel.username
        let composer = PrivateMessageComposerViewController(api: api, recipient: username)
        present(UINavigationController(rootViewController: composer), animated: true)
    }

    @objc private func followTapped() {
        performRelationshipMutation(.toggleFollow)
    }

    private enum ActionButtonStyle: Equatable {
        case filled
        case tinted
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
