import SDWebImage
import UIKit

final class ProfileHeaderView: UIView {
    enum StatType: Int {
        case topics = 0
        case posts = 1
        case likes = 2
        case days = 3
    }

    var onLoginTapped: (() -> Void)?
    var onStatTapped: ((StatType) -> Void)?

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 25
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let displayNameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bioLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let joinDateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statsStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // Login prompt state
    private let loginPromptLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "me.login_prompt")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let loginButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "me.login")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // Containers for switching between states
    private let loggedInContainer: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .leading
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let loggedOutContainer: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .center
        sv.spacing = 16
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        // 头像 + 名字横排
        let nameStack = UIStackView(arrangedSubviews: [displayNameLabel, usernameLabel])
        nameStack.axis = .vertical
        nameStack.alignment = .leading
        nameStack.spacing = 2

        let avatarNameRow = UIStackView(arrangedSubviews: [avatarImageView, nameStack])
        avatarNameRow.axis = .horizontal
        avatarNameRow.alignment = .center
        avatarNameRow.spacing = 12

        loggedInContainer.addArrangedSubview(avatarNameRow)
        loggedInContainer.addArrangedSubview(titleLabel)
        loggedInContainer.addArrangedSubview(bioLabel)

        loggedInContainer.setCustomSpacing(8, after: avatarNameRow)
        loggedInContainer.setCustomSpacing(4, after: titleLabel)
        loggedInContainer.setCustomSpacing(8, after: bioLabel)

        loggedInContainer.addArrangedSubview(statsStackView)
        loggedInContainer.setCustomSpacing(16, after: bioLabel)

        loggedInContainer.addArrangedSubview(joinDateLabel)
        loggedInContainer.setCustomSpacing(12, after: statsStackView)

        loggedOutContainer.addArrangedSubview(loginPromptLabel)
//        loggedOutContainer.addArrangedSubview(loginButton)

        addSubview(loggedInContainer)
        addSubview(loggedOutContainer)

        NSLayoutConstraint.activate([
            avatarImageView.widthAnchor.constraint(equalToConstant: 50),
            avatarImageView.heightAnchor.constraint(equalToConstant: 50),

            loggedInContainer.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            loggedInContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            loggedInContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            loggedInContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            loggedOutContainer.topAnchor.constraint(equalTo: topAnchor, constant: 40),
            loggedOutContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            loggedOutContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            loggedOutContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24),

            statsStackView.leadingAnchor.constraint(equalTo: loggedInContainer.leadingAnchor),
            statsStackView.trailingAnchor.constraint(equalTo: loggedInContainer.trailingAnchor),
        ])

//        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)
    }

    func configure(user: DiscourseCurrentUser?, userProfile: DiscourseUserProfile?, summary: DiscourseUserSummary?, baseURL: String) {
        if let user {
            loggedInContainer.isHidden = false
            loggedOutContainer.isHidden = true

            displayNameLabel.text = userProfile?.name ?? user.name ?? user.username
            usernameLabel.text = "@\(user.username)"

            let avatarTemplate = userProfile?.avatarTemplate ?? user.avatarTemplate
            AvatarImageLoader.setImage(
                on: avatarImageView,
                template: avatarTemplate,
                baseURL: baseURL,
                size: 240
            )

            if let title = userProfile?.title, !title.isEmpty {
                titleLabel.text = title
                titleLabel.isHidden = false
            } else {
                titleLabel.isHidden = true
            }

            if let bio = userProfile?.bioExcerpt, !bio.isEmpty {
                bioLabel.text = bio
                bioLabel.isHidden = false
            } else {
                bioLabel.isHidden = true
            }

            if let createdAt = userProfile?.createdAt {
                joinDateLabel.text = formatJoinDate(createdAt)
                joinDateLabel.isHidden = false
            } else {
                joinDateLabel.isHidden = true
            }

            configureStats(summary: summary)
        } else {
            loggedInContainer.isHidden = true
            loggedOutContainer.isHidden = false
        }
    }

    private func formatJoinDate(_ dateString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = isoFormatter.date(from: dateString)
            ?? ISO8601DateFormatter().date(from: dateString)
        guard let date else { return "" }
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .none
        return String(localized: "me.joined_date \(displayFormatter.string(from: date))")
    }

    private func configureStats(summary: DiscourseUserSummary?) {
        statsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let summary else { return }

        let items: [(String, Int, StatType)] = [
            (String(localized: "me.stats.topics"), summary.topicCount, .topics),
            (String(localized: "me.stats.posts"), summary.postCount, .posts),
            (String(localized: "me.stats.likes"), summary.likesReceived, .likes),
            (String(localized: "me.stats.days"), summary.daysVisited, .days),
        ]

        for (label, value, statType) in items {
            let statView = createStatView(title: label, value: value, statType: statType)
            statsStackView.addArrangedSubview(statView)
        }
    }

    private func createStatView(title: String, value: Int, statType: StatType) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.alignment = .center
        container.spacing = 2
        container.isUserInteractionEnabled = true
        container.tag = statType.rawValue

        let tap = UITapGestureRecognizer(target: self, action: #selector(statTapped(_:)))
        container.addGestureRecognizer(tap)

        let valueLabel = UILabel()
        valueLabel.font = .systemFont(ofSize: 18, weight: .bold)
        valueLabel.text = "\(value)"
        valueLabel.textAlignment = .center

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabel
        titleLabel.text = title
        titleLabel.textAlignment = .center

        container.addArrangedSubview(valueLabel)
        container.addArrangedSubview(titleLabel)
        return container
    }

    @objc private func statTapped(_ gesture: UITapGestureRecognizer) {
        guard let view = gesture.view,
              let statType = StatType(rawValue: view.tag) else { return }
        onStatTapped?(statType)
    }

    @objc private func loginTapped() {
        onLoginTapped?()
    }
}
