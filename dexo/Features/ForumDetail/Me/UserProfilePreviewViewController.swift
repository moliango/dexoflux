import UIKit

final class UserProfilePreviewViewController: ObservableViewController {
    var onViewProfile: ((String) -> Void)?

    private let api: DiscourseAPI
    private let viewModel: UserProfileViewModel

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let dimView = UIView()
    private let cardView = UIView()
    private let cardStack = UIStackView()
    private let grabberView = UIView()
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
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let errorLabel = UILabel()

    private var avatarSizeConstraint: NSLayoutConstraint?

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
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.baseForegroundColor = AppSettings.shared.themeStyle.accentColor
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.addTarget(self, action: #selector(viewProfileTapped), for: .touchUpInside)
        return button
    }()

    private lazy var moreButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "ellipsis")
        config.cornerStyle = .capsule
        config.baseForegroundColor = .label
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.borderWidth = 1
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.accessibilityLabel = String(localized: "user.profile.more")
        button.addTarget(self, action: #selector(unavailableActionTapped), for: .touchUpInside)
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

        guard let profile = viewModel.userProfile else {
            configurePlaceholder()
            return
        }

        cardView.alpha = 1
        configureProfile(profile, summary: viewModel.summary)
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
        cardView.layer.cornerRadius = 28
        cardView.layer.cornerCurve = .continuous
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.22
        cardView.layer.shadowRadius = 32
        cardView.layer.shadowOffset = CGSize(width: 0, height: 18)
        view.addSubview(cardView)

        watermarkLabel.translatesAutoresizingMaskIntoConstraints = false
        watermarkLabel.text = "LINUX DO"
        watermarkLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 78,
            weight: .black,
            fallback: .systemFont(ofSize: 78, weight: .black)
        )
        watermarkLabel.textAlignment = .center
        watermarkLabel.adjustsFontSizeToFitWidth = true
        watermarkLabel.minimumScaleFactor = 0.55
        cardView.addSubview(watermarkLabel)

        grabberView.translatesAutoresizingMaskIntoConstraints = false
        grabberView.layer.cornerRadius = 3
        grabberView.layer.cornerCurve = .continuous
        cardView.addSubview(grabberView)

        cardStack.axis = .vertical
        cardStack.spacing = 16
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(cardStack)

        setupIdentity()
        setupBody()
        setupActions()
        setupAvatar()
        setupLoadingAndError()

        let centerY = cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -80)
        centerY.priority = .defaultHigh

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            cardView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 108),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -26),
            centerY,

            watermarkLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            watermarkLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor, constant: -8),
            watermarkLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: -18),
            watermarkLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: 18),

            grabberView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            grabberView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 42),
            grabberView.heightAnchor.constraint(equalToConstant: 6),

            cardStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 42),
            cardStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 26),
            cardStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -26),
            cardStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24),
        ])
    }

    private func setupIdentity() {
        displayNameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 31,
            weight: .heavy,
            fallback: .systemFont(ofSize: 31, weight: .heavy)
        )
        displayNameLabel.textColor = .label
        displayNameLabel.numberOfLines = 1
        displayNameLabel.adjustsFontSizeToFitWidth = true
        displayNameLabel.minimumScaleFactor = 0.68

        usernameLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 17,
            weight: .semibold,
            fallback: .systemFont(ofSize: 17, weight: .semibold)
        )
        usernameLabel.textColor = .secondaryLabel

        levelLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .bold,
            fallback: .systemFont(ofSize: 14, weight: .bold)
        )
        levelLabel.textAlignment = .center
        levelLabel.layer.cornerRadius = 8
        levelLabel.layer.cornerCurve = .continuous
        levelLabel.clipsToBounds = true

        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: .semibold,
            fallback: .systemFont(ofSize: 16, weight: .semibold)
        )
        titleLabel.textColor = .secondaryLabel
        titleLabel.numberOfLines = 1

        let usernameRow = UIStackView(arrangedSubviews: [usernameLabel, levelLabel])
        usernameRow.axis = .horizontal
        usernameRow.alignment = .center
        usernameRow.spacing = 10

        let nameStack = UIStackView(arrangedSubviews: [displayNameLabel, usernameRow, titleLabel])
        nameStack.axis = .vertical
        nameStack.spacing = 5
        nameStack.alignment = .leading

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let row = UIStackView(arrangedSubviews: [spacer, nameStack])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 2
        cardStack.addArrangedSubview(row)

        NSLayoutConstraint.activate([
            levelLabel.heightAnchor.constraint(equalToConstant: 28),
            levelLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
        ])
    }

    private func setupBody() {
        bioLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 20,
            weight: .regular,
            fallback: .systemFont(ofSize: 20, weight: .regular)
        )
        bioLabel.textColor = .label
        bioLabel.numberOfLines = 4
        bioLabel.lineBreakMode = .byTruncatingTail
        cardStack.addArrangedSubview(bioLabel)

        locationWebsiteStack.axis = .horizontal
        locationWebsiteStack.alignment = .center
        locationWebsiteStack.spacing = 14
        cardStack.addArrangedSubview(locationWebsiteStack)

        factsLabel.numberOfLines = 0
        factsLabel.lineBreakMode = .byWordWrapping
        cardStack.addArrangedSubview(factsLabel)

        statsLabel.numberOfLines = 0
        statsLabel.lineBreakMode = .byWordWrapping
        cardStack.addArrangedSubview(statsLabel)
    }

    private func setupActions() {
        messageButton.addTarget(self, action: #selector(unavailableActionTapped), for: .touchUpInside)
        followButton.addTarget(self, action: #selector(unavailableActionTapped), for: .touchUpInside)

        let primaryRow = UIStackView(arrangedSubviews: [messageButton, followButton])
        primaryRow.axis = .horizontal
        primaryRow.distribution = .fillEqually
        primaryRow.spacing = 12

        let bottomRow = UIStackView(arrangedSubviews: [viewProfileButton, moreButton])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 12

        cardStack.setCustomSpacing(22, after: statsLabel)
        cardStack.addArrangedSubview(primaryRow)
        cardStack.addArrangedSubview(bottomRow)

        NSLayoutConstraint.activate([
            messageButton.heightAnchor.constraint(equalToConstant: 58),
            followButton.heightAnchor.constraint(equalToConstant: 58),
            viewProfileButton.heightAnchor.constraint(equalToConstant: 50),
            moreButton.widthAnchor.constraint(equalToConstant: 58),
            moreButton.heightAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func setupAvatar() {
        avatarHaloView.translatesAutoresizingMaskIntoConstraints = false
        avatarHaloView.layer.cornerRadius = 50
        avatarHaloView.layer.cornerCurve = .continuous
        avatarHaloView.layer.borderWidth = 6
        view.addSubview(avatarHaloView)

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 44
        avatarImageView.layer.borderWidth = 4
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.backgroundColor = .secondarySystemFill
        avatarHaloView.addSubview(avatarImageView)

        flairImageView.translatesAutoresizingMaskIntoConstraints = false
        flairImageView.contentMode = .scaleAspectFit
        flairImageView.clipsToBounds = true
        flairImageView.layer.cornerRadius = 13
        flairImageView.layer.cornerCurve = .continuous
        flairImageView.layer.borderWidth = 2
        flairImageView.isHidden = true
        view.addSubview(flairImageView)

        let sizeConstraint = avatarHaloView.widthAnchor.constraint(equalToConstant: 100)
        avatarSizeConstraint = sizeConstraint

        NSLayoutConstraint.activate([
            sizeConstraint,
            avatarHaloView.heightAnchor.constraint(equalTo: avatarHaloView.widthAnchor),
            avatarHaloView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 28),
            avatarHaloView.centerYAnchor.constraint(equalTo: cardView.topAnchor),

            avatarImageView.centerXAnchor.constraint(equalTo: avatarHaloView.centerXAnchor),
            avatarImageView.centerYAnchor.constraint(equalTo: avatarHaloView.centerYAnchor),
            avatarImageView.widthAnchor.constraint(equalToConstant: 88),
            avatarImageView.heightAnchor.constraint(equalToConstant: 88),

            flairImageView.trailingAnchor.constraint(equalTo: avatarHaloView.trailingAnchor, constant: 4),
            flairImageView.bottomAnchor.constraint(equalTo: avatarHaloView.bottomAnchor, constant: 2),
            flairImageView.widthAnchor.constraint(equalToConstant: 28),
            flairImageView.heightAnchor.constraint(equalToConstant: 28),
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
        levelLabel.text = UserProfileFormatting.trustLevelText(nil)
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
        levelLabel.text = UserProfileFormatting.trustLevelText(profile.trustLevel)
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
        factsLabel.attributedText = makeInlineMetricText(items: items, baseSize: 16, separator: "    ")
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
        statsLabel.attributedText = makeInlineMetricText(items: socialItems.isEmpty ? fallbackItems : socialItems, baseSize: 17, separator: "    ")
    }

    private func makeInlineIconText(symbolName: String, text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = .secondaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.font = AppSettings.shared.appInterfaceFont(
            ofSize: 16,
            weight: .medium,
            fallback: .systemFont(ofSize: 16, weight: .medium)
        )
        label.textColor = .secondaryLabel
        label.text = text
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 17),
            icon.heightAnchor.constraint(equalToConstant: 17),
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
        config.imagePadding = 8
        config.cornerStyle = .capsule
        config.baseForegroundColor = style == .filled ? .white : AppSettings.shared.themeStyle.accentColor
        config.baseBackgroundColor = AppSettings.shared.themeStyle.accentColor
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func applyTheme() {
        let theme = AppSettings.shared.themeStyle
        cardView.backgroundColor = theme.contentBackgroundColor.withAlphaComponent(0.96)
        cardView.layer.borderWidth = 0.8
        cardView.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        grabberView.backgroundColor = theme.accentColor.withAlphaComponent(0.28)
        watermarkLabel.textColor = theme.accentColor.withAlphaComponent(0.12)

        avatarHaloView.backgroundColor = theme.contentBackgroundColor
        avatarHaloView.layer.borderColor = UIColor.white.cgColor
        avatarImageView.layer.borderColor = theme.contentBackgroundColor.cgColor
        flairImageView.backgroundColor = theme.contentBackgroundColor
        flairImageView.layer.borderColor = theme.contentBackgroundColor.cgColor

        levelLabel.backgroundColor = theme.accentColor.withAlphaComponent(0.18)
        levelLabel.textColor = theme.accentColor
        viewProfileButton.layer.borderColor = UIColor.label.withAlphaComponent(0.55).cgColor
        moreButton.layer.borderColor = UIColor.label.withAlphaComponent(0.28).cgColor

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
