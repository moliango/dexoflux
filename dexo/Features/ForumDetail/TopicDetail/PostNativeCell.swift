import CookedHTML
import SDWebImage
import UIKit

final class PostNativeCell: UITableViewCell {
    struct SharedIssueState {
        let topicId: Int
        let canCreate: Bool
        let count: Int
        let userCreated: Bool
    }

    static let reuseIdentifier = "PostNativeCell"
    static let headerHeight: CGFloat = 44
    static let bottomBarHeight: CGFloat = 36
    static let actionIconPointSize: CGFloat = 12
    static let actionIconCanvasSize = CGSize(width: 22, height: 22)
    static let boostIconImage: UIImage = {
        if let image = UIImage(named: "BoostRocket") {
            return image.withRenderingMode(.alwaysTemplate)
        }
        return UIImage(
            systemName: "paperplane.fill",
            withConfiguration: actionSymbolConfig(pointSize: actionIconPointSize)
        )?.withRenderingMode(.alwaysTemplate) ?? UIImage()
    }()
    static func renderContentWidth(for tableWidth: CGFloat, isFirstPost: Bool) -> CGFloat {
        // tableView 首次 dequeue 时 bounds 可能仍是 0，回退到屏幕宽度，避免 preferredMeasurementWidth=0 导致正文首行被掩盖。
        let resolvedWidth = tableWidth > 1 ? tableWidth : UIScreen.main.bounds.width
        let contentInset = isFirstPost ? Metrics.firstPostContentInset : 0
        let cardOuterHorizontal = isFirstPost ? Metrics.cardOuterHorizontal : Metrics.replyCardOuterHorizontal
        let horizontalInset = (cardOuterHorizontal + Metrics.cardInner + contentInset) * 2
        return max(resolvedWidth - horizontalInset, 1)
    }

    static func firstPostRenderContentWidth(for tableWidth: CGFloat) -> CGFloat {
        renderContentWidth(for: tableWidth, isFirstPost: true)
    }

    enum Metrics {
        static let cardOuterVertical: CGFloat = 0
        static let cardOuterHorizontal: CGFloat = 0
        static let replyCardOuterHorizontal: CGFloat = 8
        static let cardInner: CGFloat = 16
        static let headerTop: CGFloat = 14
        static let avatarSize: CGFloat = 36
        static let maximumAvatarSize: CGFloat = 40
        static let avatarToText: CGFloat = 8
        static let contentTop: CGFloat = 10
        static let firstPostContentInset: CGFloat = 0
        static let actionTop: CGFloat = 10
        static let sharedIssueButtonHeight: CGFloat = 30
        static let reactionSlotWidth: CGFloat = 42
        static let actionButtonWidth: CGFloat = 36
        static let actionSpacing: CGFloat = 2
        static let minimumReplyCardHeight: CGFloat = 80
    }

    weak var delegate: PostCellDelegate?
    var postId: Int = 0
    var postLink: String?
    var currentPost: DiscourseTopicDetail.Post?
    var currentSharedIssueTopicId: Int?
    var cookedHTML: String = ""
    var validReactions: [String] = []
    var isBookmarked = false
    var cardTopConstraint: NSLayoutConstraint?
    var cardBottomConstraint: NSLayoutConstraint?
    var cardLeadingConstraint: NSLayoutConstraint?
    var cardTrailingConstraint: NSLayoutConstraint?

    let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        // Keep oversized content from painting into neighboring rows when height is stale.
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    var cardMinHeightConstraint: NSLayoutConstraint?
    var avatarWidthConstraint: NSLayoutConstraint?
    var avatarHeightConstraint: NSLayoutConstraint?
    var flairWidthConstraint: NSLayoutConstraint?
    var flairHeightConstraint: NSLayoutConstraint?
    var flairImageWidthConstraint: NSLayoutConstraint?
    var flairImageHeightConstraint: NSLayoutConstraint?
    var currentAvatarTemplateSize = AvatarImageLoader.primaryAvatarPixelSize

    // MARK: - Header UI

    let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 16
        iv.layer.borderWidth = 1.0 / UIScreen.main.scale
        iv.layer.borderColor = UIColor.separator.withAlphaComponent(0.45).cgColor
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    let flairBadgeView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        view.layer.borderWidth = 0
        view.layer.borderColor = nil
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    let flairImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.borderWidth = 0
        iv.layer.borderColor = nil
        iv.backgroundColor = .clear
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    let topLineStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let topBadgesStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.isHidden = true
        return stack
    }()

    let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let userTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .systemYellow
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    let metaLineStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    let grantedBadgesStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.isHidden = true
        return stack
    }()

    let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13.67)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let whisperBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .systemPurple
        label.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.12)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.textAlignment = .center
        label.isHidden = true
        label.text = "  " + String(localized: "post.whisper", defaultValue: "悄悄话") + "  "
        return label
    }()

    let editsButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        button.isHidden = true
        return button
    }()

    let floorLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 13.67, weight: .regular)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let sourceButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let replyToLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // MARK: - Content

    let contentCardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        return view
    }()

    let contentStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    var contentStackTopConstraint: NSLayoutConstraint?
    var contentStackLeadingConstraint: NSLayoutConstraint?
    var contentStackTrailingConstraint: NSLayoutConstraint?
    var contentStackBottomConstraint: NSLayoutConstraint?
    var sharedIssueButtonMinWidthConstraint: NSLayoutConstraint?
    var sharedIssueButtonHeightConstraint: NSLayoutConstraint?
    var actionStackTopToContentConstraint: NSLayoutConstraint?
    var actionStackTopToSharedIssueConstraint: NSLayoutConstraint?
    var heightReconcileGeneration = 0
    var lastReconciledHeight: CGFloat = 0
    var needsHeightReconciliation = false

    // MARK: - Bottom Bar

    let showRepliesButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.tintColor = .secondaryLabel
        button.contentHorizontalAlignment = .leading
        button.isHidden = true
        return button
    }()

    let sharedIssueButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = TopicDetailTypography.interfaceFont(
            ofSize: 12.5,
            weight: .semibold
        )
        button.contentHorizontalAlignment = .center
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.init(999), for: .horizontal)
        return button
    }()

    let sharedIssueCountLabel: UILabel = {
        let label = UILabel()
        label.font = TopicDetailTypography.interfaceFont(
            ofSize: 11,
            weight: .semibold
        )
        label.textAlignment = .center
        label.layer.cornerRadius = 9
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    let reactionStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 2
        sv.alignment = .center
        sv.isHidden = true
        sv.isUserInteractionEnabled = false
        sv.accessibilityIdentifier = "post.reactions.summary"
        sv.translatesAutoresizingMaskIntoConstraints = false
        // Keep reaction icons from being crushed when footer is tight.
        sv.setContentCompressionResistancePriority(.required, for: .horizontal)
        sv.setContentHuggingPriority(.required, for: .horizontal)
        return sv
    }()

    // Pre-created reaction views to avoid alloc/dealloc churn during scroll
    let reactionImageViews: [UIImageView] = (0 ..< 3).map { _ in
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
        ])
        return iv
    }

    let reactionCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }()

    let reactionPillControl: UIControl = {
        let control = UIControl()
        control.backgroundColor = .clear
        control.layer.cornerRadius = PostNativeCell.bottomBarHeight / 2
        control.layer.cornerCurve = .continuous
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    var reactionPillWidthConstraint: NSLayoutConstraint?

    let bottomLeftStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.alignment = .center
        sv.isHidden = true
        sv.accessibilityIdentifier = "post.supplementary.footer"
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    let actionStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = Metrics.actionSpacing
        sv.alignment = .center
        sv.accessibilityIdentifier = "post.action.footer"
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return sv
    }()

    let reactButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "heart", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let boostButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        button.setImage(PostNativeCell.boostIconImage, for: .normal)
        button.tintColor = .tertiaryLabel
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = String(localized: "post.boost")
        return button
    }()

    let bookmarkButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let moreButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let replyButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "arrowshape.turn.up.left", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        // Critical: without clipping, underestimated self-sizing rows bleed into the next floor.
        contentView.clipsToBounds = true
        clipsToBounds = true
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupViews() {
        contentView.addSubview(cardView)
        cardView.addSubview(avatarImageView)
        cardView.addSubview(flairBadgeView)
        flairBadgeView.addSubview(flairImageView)
        topLineStackView.addArrangedSubview(nameLabel)
        topLineStackView.addArrangedSubview(topBadgesStackView)
        metaLineStackView.addArrangedSubview(usernameLabel)
        metaLineStackView.addArrangedSubview(userTitleLabel)
        metaLineStackView.addArrangedSubview(grantedBadgesStackView)
        cardView.addSubview(topLineStackView)
        cardView.addSubview(metaLineStackView)
        cardView.addSubview(timeLabel)
        cardView.addSubview(floorLabel)
        cardView.addSubview(whisperBadge)
        cardView.addSubview(editsButton)
        cardView.addSubview(sourceButton)
        cardView.addSubview(replyToLabel)
        cardView.addSubview(contentCardView)
        contentCardView.addSubview(contentStackView)
        sharedIssueButton.addSubview(sharedIssueCountLabel)
        // FluxDo: shared-issue sits above the action row so reactions never get half-clipped.
        bottomLeftStack.addArrangedSubview(showRepliesButton)
        for iv in reactionImageViews {
            reactionStackView.addArrangedSubview(iv)
            iv.isHidden = true
        }
        reactionStackView.addArrangedSubview(reactionCountLabel)
        reactionCountLabel.isHidden = true
        reactionPillControl.addSubview(reactButton)
        actionStackView.addArrangedSubview(reactionStackView)
        actionStackView.addArrangedSubview(reactionPillControl)
        actionStackView.addArrangedSubview(boostButton)
        actionStackView.addArrangedSubview(bookmarkButton)
        actionStackView.addArrangedSubview(replyButton)
        actionStackView.addArrangedSubview(moreButton)
        cardView.addSubview(sharedIssueButton)
        cardView.addSubview(bottomLeftStack)
        cardView.addSubview(actionStackView)
        cardView.addSubview(separatorLine)

        let contentTopConstraint = contentStackView.topAnchor.constraint(equalTo: contentCardView.topAnchor)
        let contentLeadingConstraint = contentStackView.leadingAnchor.constraint(equalTo: contentCardView.leadingAnchor)
        let contentTrailingConstraint = contentStackView.trailingAnchor.constraint(equalTo: contentCardView.trailingAnchor)
        let contentBottomConstraint = contentStackView.bottomAnchor.constraint(equalTo: contentCardView.bottomAnchor)
        contentStackTopConstraint = contentTopConstraint
        contentStackLeadingConstraint = contentLeadingConstraint
        contentStackTrailingConstraint = contentTrailingConstraint
        contentStackBottomConstraint = contentBottomConstraint
        let avatarWidthConstraint = avatarImageView.widthAnchor.constraint(equalToConstant: Metrics.avatarSize)
        let avatarHeightConstraint = avatarImageView.heightAnchor.constraint(equalToConstant: Metrics.avatarSize)
        let flairWidthConstraint = flairBadgeView.widthAnchor.constraint(equalToConstant: 14)
        let flairHeightConstraint = flairBadgeView.heightAnchor.constraint(equalToConstant: 14)
        let flairImageWidthConstraint = flairImageView.widthAnchor.constraint(equalToConstant: 14)
        let flairImageHeightConstraint = flairImageView.heightAnchor.constraint(equalToConstant: 14)
        self.avatarWidthConstraint = avatarWidthConstraint
        self.avatarHeightConstraint = avatarHeightConstraint
        self.flairWidthConstraint = flairWidthConstraint
        self.flairHeightConstraint = flairHeightConstraint
        self.flairImageWidthConstraint = flairImageWidthConstraint
        self.flairImageHeightConstraint = flairImageHeightConstraint
        let contentCardTopConstraint = contentCardView.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: Metrics.contentTop)
        contentCardTopConstraint.priority = .defaultHigh
        let reactionPillWidthConstraint = reactionPillControl.widthAnchor.constraint(
            equalToConstant: Metrics.reactionSlotWidth
        )
        self.reactionPillWidthConstraint = reactionPillWidthConstraint
        let sharedIssueButtonMinWidthConstraint = sharedIssueButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        sharedIssueButtonMinWidthConstraint.priority = .init(999)
        self.sharedIssueButtonMinWidthConstraint = sharedIssueButtonMinWidthConstraint

        let cardTopConstraint = cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.cardOuterVertical)
        let cardBottomConstraint = cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.cardOuterVertical)
        let cardLeadingConstraint = cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.cardOuterHorizontal)
        let cardTrailingConstraint = cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.cardOuterHorizontal)
        self.cardTopConstraint = cardTopConstraint
        self.cardBottomConstraint = cardBottomConstraint
        self.cardLeadingConstraint = cardLeadingConstraint
        self.cardTrailingConstraint = cardTrailingConstraint

        NSLayoutConstraint.activate([
            cardTopConstraint,
            cardLeadingConstraint,
            cardTrailingConstraint,
            cardBottomConstraint,

            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.headerTop),
            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            avatarWidthConstraint,
            avatarHeightConstraint,

            flairBadgeView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 2),
            flairBadgeView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 4),
            flairWidthConstraint,
            flairHeightConstraint,

            flairImageView.centerXAnchor.constraint(equalTo: flairBadgeView.centerXAnchor),
            flairImageView.centerYAnchor.constraint(equalTo: flairBadgeView.centerYAnchor),
            flairImageWidthConstraint,
            flairImageHeightConstraint,

            topLineStackView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.headerTop),
            topLineStackView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Metrics.avatarToText),
            topLineStackView.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            metaLineStackView.topAnchor.constraint(equalTo: topLineStackView.bottomAnchor),
            metaLineStackView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Metrics.avatarToText),
            metaLineStackView.trailingAnchor.constraint(lessThanOrEqualTo: floorLabel.leadingAnchor, constant: -8),

            replyToLabel.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            replyToLabel.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -8),

            sourceButton.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            sourceButton.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -6),
            sourceButton.widthAnchor.constraint(equalToConstant: 24),
            sourceButton.heightAnchor.constraint(equalToConstant: 24),

            timeLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.headerTop),
            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),

            floorLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 2),
            floorLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),
            whisperBadge.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            whisperBadge.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            editsButton.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            editsButton.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -4),

            contentCardTopConstraint,
            contentCardView.topAnchor.constraint(greaterThanOrEqualTo: avatarImageView.bottomAnchor, constant: Metrics.contentTop),
            contentCardView.topAnchor.constraint(greaterThanOrEqualTo: metaLineStackView.bottomAnchor, constant: Metrics.contentTop),
            contentCardView.topAnchor.constraint(greaterThanOrEqualTo: floorLabel.bottomAnchor, constant: Metrics.contentTop),
            contentCardView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            contentCardView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),
            contentTopConstraint,
            contentLeadingConstraint,
            contentTrailingConstraint,
            contentBottomConstraint,

            sharedIssueButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            sharedIssueButton.topAnchor.constraint(equalTo: contentCardView.bottomAnchor, constant: Metrics.actionTop),
            sharedIssueButton.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -Metrics.cardInner),
            sharedIssueButtonMinWidthConstraint,

            sharedIssueCountLabel.centerYAnchor.constraint(equalTo: sharedIssueButton.centerYAnchor),
            sharedIssueCountLabel.trailingAnchor.constraint(equalTo: sharedIssueButton.trailingAnchor, constant: -7),
            sharedIssueCountLabel.heightAnchor.constraint(equalToConstant: 18),
            sharedIssueCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),

            bottomLeftStack.centerYAnchor.constraint(equalTo: actionStackView.centerYAnchor),
            bottomLeftStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            bottomLeftStack.trailingAnchor.constraint(lessThanOrEqualTo: actionStackView.leadingAnchor, constant: -8),
            bottomLeftStack.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),

            actionStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),
            actionStackView.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            actionStackView.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -8),

            reactButton.centerYAnchor.constraint(equalTo: reactionPillControl.centerYAnchor),
            reactButton.centerXAnchor.constraint(equalTo: reactionPillControl.centerXAnchor),
            reactionPillControl.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            reactionPillWidthConstraint,

            reactButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            reactButton.widthAnchor.constraint(equalToConstant: Metrics.actionButtonWidth),
            boostButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            boostButton.widthAnchor.constraint(equalToConstant: Metrics.actionButtonWidth),
            bookmarkButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            bookmarkButton.widthAnchor.constraint(equalToConstant: Metrics.actionButtonWidth),
            replyButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            replyButton.widthAnchor.constraint(equalToConstant: Metrics.actionButtonWidth),
            moreButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            moreButton.widthAnchor.constraint(equalToConstant: Metrics.actionButtonWidth),

            separatorLine.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            separatorLine.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),
            separatorLine.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])
        cardMinHeightConstraint = cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.minimumReplyCardHeight)
        cardMinHeightConstraint?.isActive = true

        let sharedIssueHeight = sharedIssueButton.heightAnchor.constraint(equalToConstant: 0)
        sharedIssueButtonHeightConstraint = sharedIssueHeight
        sharedIssueHeight.isActive = true

        let actionStackTopToContent = actionStackView.topAnchor.constraint(
            equalTo: contentCardView.bottomAnchor,
            constant: Metrics.actionTop
        )
        let actionStackTopToSharedIssue = actionStackView.topAnchor.constraint(
            equalTo: sharedIssueButton.bottomAnchor,
            constant: 8
        )
        actionStackTopToContentConstraint = actionStackTopToContent
        actionStackTopToSharedIssueConstraint = actionStackTopToSharedIssue
        actionStackTopToContent.isActive = true

        showRepliesButton.addTarget(self, action: #selector(repliesButtonTapped), for: .touchUpInside)
        sharedIssueButton.addTarget(self, action: #selector(sharedIssueButtonTapped), for: .touchUpInside)
        replyButton.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)
        reactButton.addTarget(self, action: #selector(reactButtonTapped), for: .touchUpInside)
        reactionPillControl.addTarget(self, action: #selector(reactButtonTapped), for: .touchUpInside)
        boostButton.addTarget(self, action: #selector(boostButtonTapped), for: .touchUpInside)
        sourceButton.addTarget(self, action: #selector(sourceButtonTapped), for: .touchUpInside)
        bookmarkButton.addTarget(self, action: #selector(bookmarkButtonTapped), for: .touchUpInside)

        let reactionLongPress = UILongPressGestureRecognizer(target: self, action: #selector(reactionPillLongPressed(_:)))
        reactionLongPress.minimumPressDuration = 0.35
        reactionPillControl.addGestureRecognizer(reactionLongPress)

        avatarImageView.isUserInteractionEnabled = true
        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarImageView.addGestureRecognizer(avatarTap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard needsHeightReconciliation, window != nil, bounds.width > 1, bounds.height > 1 else { return }
        // One deferred pass after configure/willDisplay — not every layout tick.
        needsHeightReconciliation = false
        scheduleHeightReconciliation()
    }

    /// Called from the table when the row is about to appear (and after configure).
    /// Nested media (images / web fallback) also call this when intrinsic size changes.
    func requestHeightReconciliation() {
        needsHeightReconciliation = true
        heightReconcileGeneration += 1
        let generation = heightReconcileGeneration
        // Coalesce bursts from multiple images finishing in the same runloop turn.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.heightReconcileGeneration == generation, self.window != nil else { return }
            self.needsHeightReconciliation = false
            self.reconcileTableRowHeightIfNeeded()
        }
        setNeedsLayout()
    }

    func scheduleHeightReconciliation() {
        heightReconcileGeneration += 1
        let generation = heightReconcileGeneration
        // Defer out of the current layout/update pass to avoid feedback loops.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.heightReconcileGeneration == generation, self.window != nil else { return }
            self.reconcileTableRowHeightIfNeeded()
        }
    }

    func reconcileTableRowHeightIfNeeded() {
        guard bounds.width > 1 else { return }
        layoutIfNeeded()
        let fitted = systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        // Ignore tiny float noise; require a real mismatch vs current row height.
        guard abs(fitted - bounds.height) > 2 else {
            lastReconciledHeight = bounds.height
            return
        }
        // Avoid thrashing if we already asked for this height.
        if abs(fitted - lastReconciledHeight) < 1 {
            return
        }
        lastReconciledHeight = fitted
        guard let tableView = enclosingTableView() else { return }
        // Never call beginUpdates directly — races with Diffable snapshot apply /
        // scrollToRow and triggers `_visibleRows` vs `_visibleCells` length traps.
        tableView.dexo_invalidateSelfSizingRows()
    }

    func enclosingTableView() -> UITableView? {
        var view: UIView? = superview
        while let current = view {
            if let tableView = current as? UITableView {
                return tableView
            }
            view = current.superview
        }
        return nil
    }

    func configure(
        with post: DiscourseTopicDetail.Post,
        annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig,
        delegate: PostCellDelegate?,
        floorNumber: Int,
        postLink: String?,
        baseURL: String,
        hasUnsupportedBlocks: Bool,
        cookedHTML: String,
        validReactions: [String],
        sharedIssue: SharedIssueState?,
    ) {
        postId = post.id
        self.postLink = postLink
        currentPost = post
        self.delegate = delegate
        self.cookedHTML = cookedHTML
        self.validReactions = validReactions
        currentSharedIssueTopicId = sharedIssue?.topicId
        isBookmarked = post.bookmarked
        sourceButton.isHidden = !hasUnsupportedBlocks
        applyTypography()
        applyCardStyle(isFirstPost: floorNumber == 1)

        nameLabel.text = post.name
        usernameLabel.text = "@\(post.username)"
        timeLabel.text = Self.formatDate(post.createdAt)
        floorLabel.text = "#\(floorNumber)"
        nameLabel.textColor = (post.moderator || post.groupModerator || post.admin) ? .systemBlue : .label

        if let userTitle = displayUserTitle(for: post) {
            configureUserTitle(userTitle)
            userTitleLabel.isHidden = false
        } else {
            userTitleLabel.text = nil
            userTitleLabel.attributedText = nil
            userTitleLabel.isHidden = true
        }

        configureFlairBadge(for: post, baseURL: baseURL)
        configureHeaderBadges(for: post, baseURL: baseURL)

        if let replyUser = post.replyToUser {
            let replyFont = replyToLabel.font ?? TopicDetailTypography.contentContextFont(
                offsetFromBody: -3,
                weight: .regular,
                relativeTo: .caption1
            )
            let symbolPointSize = max(replyFont.pointSize - 2, 1)
            let attachment = NSTextAttachment()
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
            attachment.image = UIImage(systemName: "arrowshape.turn.up.left.fill", withConfiguration: symbolConfig)?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            let attrStr = NSMutableAttributedString(attachment: attachment)
            attrStr.append(NSAttributedString(
                string: " @\(replyUser.username)",
                attributes: [
                    .font: replyFont,
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            ))
            replyToLabel.attributedText = attrStr
            replyToLabel.isHidden = false
        } else {
            replyToLabel.isHidden = true
        }

        let hasReplies = post.replyCount > 0
        showRepliesButton.isHidden = !hasReplies
        if hasReplies {
            configureRepliesButton(count: post.replyCount)
        }
        configureSharedIssueButton(sharedIssue)

        // Reactions
        configureReactions(post.reactions, count: post.reactionUsersCount, baseURL: baseURL)
        configureReactionButton(for: post)
        configureBoostButton(for: post)
        configureBookmarkButton(isBookmarked: post.bookmarked)
        configureReplyButton()
        configureMoreMenu(isBookmarked: post.bookmarked)
        updateFooterLayout()

        // Render content blocks
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let views = NativeContentRenderer.renderBlocks(annotatedBlocks, config: config, delegate: delegate)
        for view in views {
            setupTextViews(in: view)
            contentStackView.addArrangedSubview(view)
        }
        if let boostStripView = BoostStripView(boosts: post.boosts, baseURL: baseURL) {
            contentStackView.addArrangedSubview(boostStripView)
        }
        if let relatedLinksView = RelatedLinksCardView(linkCounts: post.linkCounts, baseURL: baseURL) {
            relatedLinksView.onTapURL = { [weak self] url in
                self?.delegate?.postCell(didTapLinkURL: url)
            }
            contentStackView.addArrangedSubview(relatedLinksView)
        }
        configureWhisperAndEdits(for: post)
        configureSignature(for: post, config: config)
        adjustNativeContentSpacing()

        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: post.avatarTemplate,
            baseURL: baseURL,
            size: currentAvatarTemplateSize
        )
        // Self-sizing can lock in a short height on first pass (code blocks / wrapped text).
        // Reconcile once after the cell lands in the hierarchy so floors stop overlapping.
        requestHeightReconciliation()
    }

    func adjustNativeContentSpacing() {
        let arrangedSubviews = contentStackView.arrangedSubviews
        guard arrangedSubviews.count > 1 else { return }

        for index in arrangedSubviews.indices.dropLast() {
            let current = arrangedSubviews[index]
            let next = arrangedSubviews[arrangedSubviews.index(after: index)]
            if current is LinkTextView, next is LinkTextView {
                contentStackView.setCustomSpacing(0, after: current)
            } else if current is LinkTextView, Self.needsBreathingRoomBefore(next) {
                contentStackView.setCustomSpacing(10, after: current)
            } else if Self.needsBreathingRoomBefore(current), next is LinkTextView {
                contentStackView.setCustomSpacing(8, after: current)
            }
        }
    }

    static func needsBreathingRoomBefore(_ view: UIView) -> Bool {
        view is TappableImageContainer
            || view is SignatureImageView
            || view is BadgeCardView
            || view is VideoCardView
            || view is OneboxCardView
            || view is FallbackBlockView
            || view is BoostStripView
            || view is RelatedLinksCardView
    }

    func applyCardStyle(isFirstPost: Bool) {
        contentStackView.spacing = isFirstPost ? 5 : 5
        cardMinHeightConstraint?.constant = isFirstPost ? 0 : Metrics.minimumReplyCardHeight
        let verticalGap: CGFloat = isFirstPost ? 0 : 4
        let horizontalGap: CGFloat = isFirstPost ? Metrics.cardOuterHorizontal : Metrics.replyCardOuterHorizontal
        cardTopConstraint?.constant = verticalGap
        cardBottomConstraint?.constant = -verticalGap
        cardLeadingConstraint?.constant = horizontalGap
        cardTrailingConstraint?.constant = -horizontalGap
        let contentInset = isFirstPost ? Metrics.firstPostContentInset : 0
        contentStackTopConstraint?.constant = contentInset
        contentStackLeadingConstraint?.constant = contentInset
        contentStackTrailingConstraint?.constant = -contentInset
        contentStackBottomConstraint?.constant = -contentInset

        if isFirstPost {
            cardView.backgroundColor = .clear
            cardView.layer.cornerRadius = 0
            cardView.layer.borderWidth = 0
            cardView.layer.borderColor = nil
            cardView.layer.shadowOpacity = 0
            cardView.layer.shadowOffset = .zero
            cardView.layer.shadowRadius = 0
            separatorLine.backgroundColor = UIColor.separator.withAlphaComponent(0.25)
        } else {
            cardView.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
            cardView.layer.cornerRadius = 18
            cardView.layer.cornerCurve = .continuous
            cardView.layer.borderWidth = 1.0 / UIScreen.main.scale
            cardView.layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
            cardView.layer.shadowColor = UIColor.black.cgColor
            cardView.layer.shadowOpacity = 0.035
            cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
            cardView.layer.shadowRadius = 8
            separatorLine.backgroundColor = .clear
        }

        contentCardView.backgroundColor = .clear
        contentCardView.layer.borderWidth = 0
        contentCardView.layer.borderColor = nil
        contentCardView.layer.shadowOpacity = 0
        contentCardView.layer.shadowOffset = .zero
        contentCardView.layer.shadowRadius = 0
    }

    func applyTypography() {
        nameLabel.font = TopicDetailTypography.contentContextFont(
            offsetFromBody: 2,
            weight: .semibold,
            relativeTo: .subheadline
        )
        usernameLabel.font = TopicDetailTypography.contentContextFont(
            offsetFromBody: 0,
            weight: .regular,
            relativeTo: .caption1
        )
        userTitleLabel.font = TopicDetailTypography.contentContextFont(
            offsetFromBody: 0,
            weight: .medium,
            relativeTo: .caption1
        )
        floorLabel.font = TopicDetailTypography.contentContextMonospacedFont(
            offsetFromBody: -1,
            weight: .regular,
            relativeTo: .caption1
        )
        timeLabel.font = TopicDetailTypography.contentContextFont(
            offsetFromBody: -1,
            weight: .regular,
            relativeTo: .caption1
        )
        replyToLabel.font = TopicDetailTypography.contentContextFont(
            offsetFromBody: -3,
            weight: .regular,
            relativeTo: .caption1
        )
        showRepliesButton.titleLabel?.font = TopicDetailTypography.interfaceFont(ofSize: 12, weight: .medium)
        sharedIssueButton.titleLabel?.font = TopicDetailTypography.interfaceFont(ofSize: 12.5, weight: .semibold)
        sharedIssueCountLabel.font = TopicDetailTypography.interfaceFont(ofSize: 11, weight: .semibold)
        reactionCountLabel.font = TopicDetailTypography.interfaceFont(ofSize: 12, weight: .semibold)

        let avatarSize = min(
            max(Metrics.avatarSize * TopicDetailTypography.contentVisualScale(), Metrics.avatarSize),
            Metrics.maximumAvatarSize
        )
        avatarWidthConstraint?.constant = avatarSize
        avatarHeightConstraint?.constant = avatarSize
        avatarImageView.layer.cornerRadius = avatarSize / 2

        let flairSize = min(max(avatarSize * 0.42, 14), 17)
        flairWidthConstraint?.constant = flairSize
        flairHeightConstraint?.constant = flairSize
        flairBadgeView.layer.cornerRadius = flairSize / 2
        applyFlairImageScale(1, badgeSize: flairSize)

        currentAvatarTemplateSize = AvatarImageLoader.primaryAvatarPixelSize
    }

    func displayUserTitle(for post: DiscourseTopicDetail.Post) -> String? {
        let trimmed = post.userTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    func configureUserTitle(_ title: String) {
        if title == "种子用户" {
            let colors: [UIColor] = [
                UIColor(red: 0.94, green: 0.58, blue: 0.08, alpha: 1),
                UIColor(red: 0.16, green: 0.67, blue: 0.82, alpha: 1),
                UIColor(red: 0.91, green: 0.34, blue: 0.58, alpha: 1),
                UIColor(red: 0.48, green: 0.39, blue: 0.88, alpha: 1),
            ]
            let attributed = NSMutableAttributedString()
            for (index, character) in title.enumerated() {
                attributed.append(NSAttributedString(
                    string: String(character),
                    attributes: [
                        .font: userTitleLabel.font as Any,
                        .foregroundColor: colors[index % colors.count],
                    ]
                ))
            }
            userTitleLabel.attributedText = attributed
            return
        }
        userTitleLabel.attributedText = nil
        userTitleLabel.text = title
        userTitleLabel.textColor = AppSettings.shared.themeStyle.accentColor.withAlphaComponent(0.82)
    }


    func configureWhisperAndEdits(for post: DiscourseTopicDetail.Post) {
        whisperBadge.isHidden = !post.whisper
        if currentPost?.showEditsIndicator == true {
            editsButton.isHidden = false
            editsButton.setTitle(String(localized: "revision.edits", defaultValue: "已编辑"), for: .normal)
            editsButton.removeTarget(nil, action: nil, for: .allEvents)
            editsButton.addAction(UIAction { [weak self] _ in
                guard let self, let post = self.currentPost else { return }
                self.delegate?.postCell(didTapShowRevisionForPost: post)
            }, for: .touchUpInside)
        } else {
            editsButton.isHidden = true
        }
    }

    func configureSignature(for post: DiscourseTopicDetail.Post, config: NativeRenderConfig) {
        guard AppSettings.shared.showUserSignatures,
              let signature = post.userSignature?.trimmingCharacters(in: .whitespacesAndNewlines),
              !signature.isEmpty
        else { return }

        // discourse-signatures plugin contract (FluxDo parity):
        // advanced mode → cooked HTML; normal mode → the value IS an image URL.
        // ponytail: site-setting gates (first_post_only / show_in_categories /
        // signatures_max_image_height) are not fetched yet; upgrade path is
        // reading site.json like FluxDo's PreloadedDataService.
        let content: UIView
        if signature.contains("<") {
            let blocks = CookedHTMLParser.parseAnnotated(
                html: PostImageLinkPreprocessor.rewrite(signature),
                baseURL: config.baseURL
            )
            let views = NativeContentRenderer.renderBlocks(blocks, config: config, delegate: delegate)
            guard !views.isEmpty else { return }
            let stack = UIStackView(arrangedSubviews: views)
            stack.axis = .vertical
            stack.spacing = 6
            views.forEach { setupTextViews(in: $0) }
            content = stack
        } else if let url = Self.signatureImageURL(from: signature) {
            // FluxDo: image-mode signatures must not reserve a gray 9:16 slot.
            // Load silently; collapse on failure; only allow gallery after real decode.
            let signatureView = SignatureImageView(
                url: url,
                containerWidth: config.contentWidth,
                maxHeight: 150,
                refererBaseURL: config.baseURL
            )
            signatureView.delegate = delegate
            content = signatureView
        } else {
            // Legacy dirty data (arbitrary plain text) — web and FluxDo hide it entirely.
            return
        }

        // Web-style <hr> separator above the signature.
        let divider = UIView()
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.3)
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true

        let wrapper = UIStackView(arrangedSubviews: [divider, content])
        wrapper.axis = .vertical
        wrapper.spacing = 8
        contentStackView.addArrangedSubview(wrapper)
    }

    static func signatureImageURL(from value: String) -> URL? {
        // FluxDo parity: scheme+host is enough for "looks like a URL".
        // Non-image URLs collapse after load failure instead of becoming gray content blocks.
        guard value.hasPrefix("http://") || value.hasPrefix("https://"),
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: value) ?? URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value),
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    /// Stop in-flight media / web fallback work when the row leaves the viewport.
    /// Keeps dual-path (Native + Fallback Web snapshot) from competing with scroll.
    func cancelOffscreenMediaWork() {
        contentStackView.arrangedSubviews.forEach { cancelContentMediaLoads(in: $0) }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        heightReconcileGeneration += 1
        lastReconciledHeight = 0
        needsHeightReconciliation = false
        // Cancel block-level image loads and fallback renders
        for view in contentStackView.arrangedSubviews {
            cancelContentMediaLoads(in: view)
        }
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        delegate = nil
        postId = 0
        postLink = nil
        currentPost = nil
        cookedHTML = ""
        nameLabel.text = nil
        nameLabel.textColor = .label
        usernameLabel.text = nil
        timeLabel.text = nil
        floorLabel.text = nil
        replyToLabel.attributedText = nil
        replyToLabel.text = nil
        replyToLabel.isHidden = true
        showRepliesButton.isHidden = true
        configureSharedIssueButton(nil)
        sourceButton.isHidden = true
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        userTitleLabel.text = nil
        userTitleLabel.isHidden = true
        flairImageView.sd_cancelCurrentImageLoad()
        flairImageView.image = nil
        flairImageView.tintColor = nil
        flairImageView.backgroundColor = nil
        flairBadgeView.backgroundColor = nil
        flairBadgeView.isHidden = true
        resetHeaderBadgeStack(topBadgesStackView)
        resetHeaderBadgeStack(grantedBadgesStackView)
        reactionStackView.isHidden = true
        for iv in reactionImageViews {
            iv.sd_cancelCurrentImageLoad()
            iv.image = nil
            iv.isHidden = true
        }
        reactionCountLabel.isHidden = true
        validReactions = []
        isBookmarked = false
        reactionPillWidthConstraint?.constant = Metrics.reactionSlotWidth
        configureActionButton(
            reactButton,
            symbolName: "heart",
            tintColor: .secondaryLabel,
            backgroundColor: .clear,
            accessibilityLabel: "喜欢"
        )
        reactionPillControl.backgroundColor = Self.actionBackgroundColor
        reactionPillControl.layer.borderWidth = 0
        reactionPillControl.layer.borderColor = nil
        configureActionButton(
            boostButton,
            image: Self.boostIconImage,
            tintColor: .secondaryLabel,
            backgroundColor: .clear,
            accessibilityLabel: String(localized: "post.boost")
        )
        // Hidden until configure() decides based on yours / canBoost.
        boostButton.isHidden = true
        boostButton.alpha = 0
        boostButton.isUserInteractionEnabled = false
        boostButton.isEnabled = false
        boostButton.isAccessibilityElement = false
        boostButton.accessibilityElementsHidden = true
        reactionPillControl.isHidden = false
        reactionPillWidthConstraint?.constant = Metrics.reactionSlotWidth
        configureBookmarkButton(isBookmarked: false)
        configureReplyButton()
        configureMoreMenu(isBookmarked: false)
        updateFooterLayout()
        let sourceConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        sourceButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: sourceConfig), for: .normal)
        sourceButton.tintColor = .tertiaryLabel
    }

    static func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else { return isoString }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
