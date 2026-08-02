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
    private static let actionIconPointSize: CGFloat = 12
    private static let actionIconCanvasSize = CGSize(width: 22, height: 22)
    fileprivate static let boostIconImage: UIImage = {
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

    private enum Metrics {
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
    private var postId: Int = 0
    private var postLink: String?
    private var currentPost: DiscourseTopicDetail.Post?
    private var currentSharedIssueTopicId: Int?
    private var cookedHTML: String = ""
    private var validReactions: [String] = []
    private var isBookmarked = false
    private var cardTopConstraint: NSLayoutConstraint?
    private var cardBottomConstraint: NSLayoutConstraint?
    private var cardLeadingConstraint: NSLayoutConstraint?
    private var cardTrailingConstraint: NSLayoutConstraint?

    private let cardView: UIView = {
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
    private var cardMinHeightConstraint: NSLayoutConstraint?
    private var avatarWidthConstraint: NSLayoutConstraint?
    private var avatarHeightConstraint: NSLayoutConstraint?
    private var flairWidthConstraint: NSLayoutConstraint?
    private var flairHeightConstraint: NSLayoutConstraint?
    private var flairImageWidthConstraint: NSLayoutConstraint?
    private var flairImageHeightConstraint: NSLayoutConstraint?
    private var currentAvatarTemplateSize = AvatarImageLoader.primaryAvatarPixelSize

    // MARK: - Header UI

    private let avatarImageView: UIImageView = {
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

    private let flairBadgeView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        view.layer.borderWidth = 0
        view.layer.borderColor = nil
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let flairImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.layer.borderWidth = 0
        iv.layer.borderColor = nil
        iv.backgroundColor = .clear
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let topLineStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let topBadgesStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.isHidden = true
        return stack
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return label
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let userTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .systemYellow
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private let metaLineStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let grantedBadgesStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.isHidden = true
        return stack
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11.75)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let whisperBadge: UILabel = {
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

    private let editsButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        button.isHidden = true
        return button
    }()

    private let floorLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 11.75, weight: .regular)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let sourceButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let replyToLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // MARK: - Content

    private let contentCardView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let contentStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 8
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    private var contentStackTopConstraint: NSLayoutConstraint?
    private var contentStackLeadingConstraint: NSLayoutConstraint?
    private var contentStackTrailingConstraint: NSLayoutConstraint?
    private var contentStackBottomConstraint: NSLayoutConstraint?
    private var sharedIssueButtonMinWidthConstraint: NSLayoutConstraint?
    private var sharedIssueButtonHeightConstraint: NSLayoutConstraint?
    private var actionStackTopToContentConstraint: NSLayoutConstraint?
    private var actionStackTopToSharedIssueConstraint: NSLayoutConstraint?
    private var heightReconcileGeneration = 0
    private var lastReconciledHeight: CGFloat = 0
    private var needsHeightReconciliation = false

    // MARK: - Bottom Bar

    private let showRepliesButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.tintColor = .secondaryLabel
        button.contentHorizontalAlignment = .leading
        button.isHidden = true
        return button
    }()

    private let sharedIssueButton: UIButton = {
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

    private let sharedIssueCountLabel: UILabel = {
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

    private let reactionStackView: UIStackView = {
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
    private let reactionImageViews: [UIImageView] = (0 ..< 3).map { _ in
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: 16),
            iv.heightAnchor.constraint(equalToConstant: 16),
        ])
        return iv
    }

    private let reactionCountLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }()

    private let reactionPillControl: UIControl = {
        let control = UIControl()
        control.backgroundColor = .clear
        control.layer.cornerRadius = PostNativeCell.bottomBarHeight / 2
        control.layer.cornerCurve = .continuous
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }()

    private var reactionPillWidthConstraint: NSLayoutConstraint?

    private let bottomLeftStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.alignment = .center
        sv.isHidden = true
        sv.accessibilityIdentifier = "post.supplementary.footer"
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let actionStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = Metrics.actionSpacing
        sv.alignment = .center
        sv.accessibilityIdentifier = "post.action.footer"
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return sv
    }()

    private let reactButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "heart", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let boostButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        button.setImage(PostNativeCell.boostIconImage, for: .normal)
        button.tintColor = .tertiaryLabel
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = String(localized: "post.boost")
        return button
    }()

    private let bookmarkButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let moreButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let replyButton: PostActionButton = {
        let button = PostActionButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "arrowshape.turn.up.left", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let separatorLine: UIView = {
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

    private func setupViews() {
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
    func requestHeightReconciliation() {
        needsHeightReconciliation = true
        setNeedsLayout()
    }

    private func scheduleHeightReconciliation() {
        heightReconcileGeneration += 1
        let generation = heightReconcileGeneration
        // Defer out of the current layout/update pass to avoid feedback loops.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.heightReconcileGeneration == generation, self.window != nil else { return }
            self.reconcileTableRowHeightIfNeeded()
        }
    }

    private func reconcileTableRowHeightIfNeeded() {
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
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    private func enclosingTableView() -> UITableView? {
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

    private func adjustNativeContentSpacing() {
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

    private static func needsBreathingRoomBefore(_ view: UIView) -> Bool {
        view is TappableImageContainer
            || view is SignatureImageView
            || view is BadgeCardView
            || view is VideoCardView
            || view is OneboxCardView
            || view is FallbackBlockView
            || view is BoostStripView
            || view is RelatedLinksCardView
    }

    private func applyCardStyle(isFirstPost: Bool) {
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

    private func applyTypography() {
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

    private func displayUserTitle(for post: DiscourseTopicDetail.Post) -> String? {
        let trimmed = post.userTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func configureUserTitle(_ title: String) {
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


    private func configureWhisperAndEdits(for post: DiscourseTopicDetail.Post) {
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

    private func configureSignature(for post: DiscourseTopicDetail.Post, config: NativeRenderConfig) {
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

    private static func signatureImageURL(from value: String) -> URL? {
        // FluxDo parity: scheme+host is enough for "looks like a URL".
        // Non-image URLs collapse after load failure instead of becoming gray content blocks.
        guard value.hasPrefix("http://") || value.hasPrefix("https://"),
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: value) ?? URL(string: value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value),
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    private func configureHeaderBadges(for post: DiscourseTopicDetail.Post, baseURL: String) {
        resetHeaderBadgeStack(topBadgesStackView)
        resetHeaderBadgeStack(grantedBadgesStackView)

        if post.moderator || post.groupModerator || post.admin {
            let shieldView = makeFontAwesomeBadgeView(
                icon: "shield-alt",
                tintColor: .systemBlue,
                size: 13
            ) ?? makeHeaderBadgeImageView(
                image: UIImage(systemName: "shield.fill"),
                tintColor: .systemBlue,
                size: 13
            )
            topBadgesStackView.addArrangedSubview(shieldView)
        }
        topBadgesStackView.isHidden = topBadgesStackView.arrangedSubviews.isEmpty

        if let emoji = post.userStatus?.emoji,
           let urlString = EmojiStore.url(for: emoji) ?? EmojiStore.lookup(for: emoji),
           let url = URL(string: urlString) {
            topBadgesStackView.addArrangedSubview(makeHeaderBadgeImageView(url: url, size: 15))
        }
        topBadgesStackView.isHidden = topBadgesStackView.arrangedSubviews.isEmpty

        for badge in post.badgesGranted {
            guard let badgeView = makeGrantedBadgeView(for: badge, baseURL: baseURL) else {
                continue
            }
            grantedBadgesStackView.addArrangedSubview(badgeView)
        }
        grantedBadgesStackView.isHidden = grantedBadgesStackView.arrangedSubviews.isEmpty
    }

    private func resetHeaderBadgeStack(_ stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            cancelImageLoads(in: view)
            view.removeFromSuperview()
        }
        stackView.isHidden = true
    }

    private func cancelImageLoads(in view: UIView) {
        if let imageView = view as? UIImageView {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = nil
        }
        for subview in view.subviews {
            cancelImageLoads(in: subview)
        }
    }

    private func cancelContentMediaLoads(in view: UIView) {
        if let container = view as? TappableImageContainer {
            container.cancelImageLoad()
        } else if let signature = view as? SignatureImageView {
            signature.cancelImageLoad()
        } else if let onebox = view as? OneboxCardView {
            onebox.cancelImageLoad()
        } else if let video = view as? VideoCardView {
            video.cancelImageLoad()
        } else if let fallback = view as? FallbackBlockView {
            fallback.cancelRender()
        } else if let badge = view as? BadgeCardView {
            // BadgeCardView owns a WKWebView; deinit stops loading.
            _ = badge
        }

        if let stack = view as? UIStackView {
            for arranged in stack.arrangedSubviews {
                cancelContentMediaLoads(in: arranged)
            }
        }
        for subview in view.subviews {
            cancelContentMediaLoads(in: subview)
        }
    }

    private func makeGrantedBadgeView(for badge: DiscourseTopicDetail.GrantedBadge, baseURL: String) -> UIView? {
        let color = grantedBadgeColor(for: badge)
        if let imageUrl = badge.imageUrl,
           let url = resolveHeaderBadgeURL(imageUrl, baseURL: baseURL) {
            let imageView = makeHeaderBadgeImageView(
                url: url,
                placeholder: nil,
                placeholderTintColor: .clear,
                size: 14
            )
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = badge.name
            return imageView
        }

        if let badgeView = makeFontAwesomeBadgeView(icon: badge.icon, tintColor: color, size: 13) {
            badgeView.isAccessibilityElement = true
            badgeView.accessibilityLabel = badge.name
            return badgeView
        }

        return nil
    }

    private func makeFontAwesomeBadgeView(icon: String?, tintColor: UIColor, size: CGFloat) -> UIView? {
        guard let glyph = DiscourseFontAwesomeIcon.glyph(for: icon),
              let font = UIFont(name: DiscourseFontAwesomeIcon.fontName, size: size)
        else { return nil }

        let label = UILabel()
        label.text = glyph
        label.font = font
        label.textColor = tintColor
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: size + 1),
            label.heightAnchor.constraint(equalToConstant: size + 1),
        ])
        return label
    }

    private func makeHeaderBadgeImageView(
        url: URL,
        placeholder: UIImage?,
        placeholderTintColor: UIColor,
        size: CGFloat
    ) -> UIImageView {
        let imageView = makeHeaderBadgeImageView(
            image: placeholder,
            tintColor: placeholderTintColor,
            size: size
        )
        imageView.isAccessibilityElement = false

        if let cacheKey = SDWebImageManager.shared.cacheKey(for: url),
           let cachedImage = SDImageCache.shared.imageFromCache(forKey: cacheKey) {
            imageView.image = cachedImage.withRenderingMode(.alwaysOriginal)
            imageView.tintColor = nil
            return imageView
        }

        ForumImageLoader.setImage(
            on: imageView,
            url: url,
            placeholder: placeholder?.withRenderingMode(.alwaysTemplate)
        ) { [weak imageView] image, _, _, _ in
            guard let image else { return }
            imageView?.image = image.withRenderingMode(.alwaysOriginal)
            imageView?.tintColor = nil
        }
        return imageView
    }

    private func makeHeaderBadgeImageView(url: URL, size: CGFloat) -> UIImageView {
        makeHeaderBadgeImageView(url: url, placeholder: nil, placeholderTintColor: .clear, size: size)
    }

    private func makeHeaderBadgeImageView(image: UIImage?, tintColor: UIColor?, size: CGFloat) -> UIImageView {
        let imageView = UIImageView(image: image?.withRenderingMode(tintColor == nil ? .alwaysOriginal : .alwaysTemplate))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = tintColor
        imageView.isAccessibilityElement = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size),
        ])
        return imageView
    }

    private func resolveHeaderBadgeURL(_ rawURL: String, baseURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        var normalizedBaseURL = baseURL
        if normalizedBaseURL.hasSuffix("/") {
            normalizedBaseURL.removeLast()
        }
        let normalizedPath = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: normalizedBaseURL + normalizedPath)
    }

    private func grantedBadgeColor(for badge: DiscourseTopicDetail.GrantedBadge) -> UIColor {
        switch badge.badgeTypeId {
        case 1:
            return UIColor(red: 0.90, green: 0.63, blue: 0.00, alpha: 1)
        case 2:
            return UIColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1)
        case 3:
            return UIColor(red: 0.80, green: 0.50, blue: 0.20, alpha: 1)
        default:
            return AppSettings.shared.themeStyle.accentColor
        }
    }

    private func configureFlairBadge(for post: DiscourseTopicDetail.Post, baseURL: String) {
        flairImageView.sd_cancelCurrentImageLoad()
        flairImageView.image = nil
        flairImageView.layer.borderWidth = 0
        flairImageView.layer.borderColor = nil
        let explicitBadgeBackgroundColor = post.flairBgColor.flatMap(UIColor.init(hex:))
        let badgeBackgroundColor = explicitBadgeBackgroundColor
        let badgeForegroundColor = post.flairColor.flatMap(UIColor.init(hex:))
            ?? (badgeBackgroundColor == nil ? .label : .white)
        flairImageView.tintColor = badgeForegroundColor

        guard let flairUrl = post.flairUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !flairUrl.isEmpty
        else {
            flairBadgeView.backgroundColor = .clear
            flairBadgeView.isHidden = true
            return
        }

        flairBadgeView.isHidden = false

        if !isImageFlairURL(flairUrl) {
            guard let iconImage = makeFontAwesomeGlyphImage(
                icon: flairUrl,
                color: badgeForegroundColor,
                size: max((flairWidthConstraint?.constant ?? 18) * 0.72, 10)
            ) else {
                flairBadgeView.backgroundColor = .clear
                flairBadgeView.isHidden = true
                return
            }
            flairBadgeView.backgroundColor = badgeBackgroundColor ?? .clear
            flairImageView.tintColor = nil
            flairImageView.image = iconImage
            applyFlairImageScale(badgeBackgroundColor == nil ? 0.8 : 0.62)
            return
        }

        guard let url = resolveFlairURL(flairUrl, baseURL: baseURL) else {
            flairBadgeView.backgroundColor = .clear
            flairBadgeView.isHidden = true
            return
        }

        flairBadgeView.backgroundColor = badgeBackgroundColor ?? .clear
        applyFlairImageScale(badgeBackgroundColor == nil ? 1 : 0.7)
        ForumImageLoader.setImage(on: flairImageView, url: url)
    }

    private func applyFlairImageScale(_ scale: CGFloat, badgeSize: CGFloat? = nil) {
        let resolvedBadgeSize = badgeSize ?? max(flairWidthConstraint?.constant ?? 18, 18)
        let imageSize = max(resolvedBadgeSize * scale, 1)
        flairImageWidthConstraint?.constant = imageSize
        flairImageHeightConstraint?.constant = imageSize
    }

    private func resolveFlairURL(_ flairUrl: String, baseURL: String) -> URL? {
        guard isImageFlairURL(flairUrl) else {
            return nil
        }
        if flairUrl.hasPrefix(":") && flairUrl.hasSuffix(":") {
            let emojiName = String(flairUrl.dropFirst().dropLast())
            guard let emojiURLString = EmojiStore.url(for: emojiName) ?? EmojiStore.lookup(for: emojiName) else {
                return nil
            }
            return resolveHeaderBadgeURL(emojiURLString, baseURL: baseURL)
        }
        if flairUrl.hasPrefix("http") {
            return URL(string: flairUrl)
        }
        var normalizedBaseURL = baseURL
        if normalizedBaseURL.hasSuffix("/") {
            normalizedBaseURL.removeLast()
        }
        let normalizedPath = flairUrl.hasPrefix("/") ? flairUrl : "/\(flairUrl)"
        return URL(string: normalizedBaseURL + normalizedPath)
    }

    private func isImageFlairURL(_ flairUrl: String) -> Bool {
        if flairUrl.hasPrefix("http://") || flairUrl.hasPrefix("https://") || flairUrl.hasPrefix("/") {
            return true
        }
        if flairUrl.hasPrefix(":") && flairUrl.hasSuffix(":") {
            return true
        }
        let lowercased = flairUrl.lowercased()
        return lowercased.contains(".png")
            || lowercased.contains(".jpg")
            || lowercased.contains(".jpeg")
            || lowercased.contains(".webp")
            || lowercased.contains(".gif")
            || lowercased.contains(".svg")
    }

    private func makeFontAwesomeGlyphImage(icon: String?, color: UIColor, size: CGFloat) -> UIImage? {
        DiscourseFontAwesomeIcon.image(for: icon, color: color, size: size)
    }

    private func configureRepliesButton(count: Int) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "bubble.left.fill", withConfiguration: Self.actionSymbolConfig())
        config.title = "\(count)"
        config.imagePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        config.baseForegroundColor = .secondaryLabel
        config.background.backgroundColor = Self.actionBackgroundColor
        config.background.cornerRadius = Self.bottomBarHeight / 2
        showRepliesButton.configuration = config
        showRepliesButton.clipsToBounds = true
    }

    private func configureSharedIssueButton(_ state: SharedIssueState?) {
        guard let state else {
            currentSharedIssueTopicId = nil
            sharedIssueButton.isHidden = true
            sharedIssueButton.isEnabled = false
            sharedIssueButton.alpha = 1
            sharedIssueButton.configuration = nil
            sharedIssueButton.layer.borderWidth = 0
            sharedIssueButton.layer.borderColor = nil
            sharedIssueButton.layer.shadowOpacity = 0
            sharedIssueCountLabel.isHidden = true
            sharedIssueCountLabel.text = nil
            sharedIssueButton.accessibilityLabel = nil
            return
        }

        let theme = AppSettings.shared.themeStyle
        let fluxBlue = UIColor(red: 0.10, green: 0.54, blue: 0.98, alpha: 1)
        let title = state.userCreated
            ? String(localized: "shared_issue.marked_label")
            : String(localized: "shared_issue.compact_label")
        let foregroundColor: UIColor = state.userCreated ? fluxBlue : theme.accentColor
        let backgroundColor: UIColor = state.userCreated
            ? fluxBlue.withAlphaComponent(0.13)
            : theme.accentColor.withAlphaComponent(0.08)
        let borderColor: UIColor = state.userCreated
            ? fluxBlue.withAlphaComponent(0.26)
            : theme.accentColor.withAlphaComponent(0.16)

        let titleFont = TopicDetailTypography.interfaceFont(
            ofSize: 12.5,
            weight: .semibold
        )
        var attributes = AttributeContainer()
        attributes.font = titleFont

        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: state.userCreated ? "hand.raised.fill" : "hand.raised",
            withConfiguration: Self.actionSymbolConfig(weight: .semibold)
        )
        config.titleLineBreakMode = .byClipping
        config.imagePadding = 6
        config.attributedTitle = AttributedString(title, attributes: attributes)
        let trailingInset: CGFloat = state.count > 0 ? 32 : 11
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: 11,
            bottom: 0,
            trailing: trailingInset
        )
        config.baseForegroundColor = foregroundColor
        config.cornerStyle = .capsule
        config.background.backgroundColor = backgroundColor
        config.background.cornerRadius = Metrics.sharedIssueButtonHeight / 2
        sharedIssueButton.configuration = config
        sharedIssueButton.tintColor = foregroundColor
        sharedIssueButton.titleLabel?.font = titleFont
        sharedIssueButton.titleLabel?.numberOfLines = 1
        sharedIssueButton.titleLabel?.lineBreakMode = .byClipping
        sharedIssueButton.layer.cornerRadius = Metrics.sharedIssueButtonHeight / 2
        sharedIssueButton.layer.cornerCurve = .continuous
        sharedIssueButton.layer.borderWidth = 1.0 / UIScreen.main.scale
        sharedIssueButton.layer.borderColor = borderColor.cgColor
        sharedIssueButton.layer.shadowColor = fluxBlue.cgColor
        sharedIssueButton.layer.shadowOpacity = state.userCreated ? 0.10 : 0
        sharedIssueButton.layer.shadowRadius = 8
        sharedIssueButton.layer.shadowOffset = CGSize(width: 0, height: 3)
        sharedIssueButton.clipsToBounds = true
        sharedIssueButton.isEnabled = state.canCreate
        sharedIssueButton.alpha = state.canCreate ? 1 : 0.68
        sharedIssueButton.isHidden = false
        let titleWidth = ceil((title as NSString).size(withAttributes: [.font: titleFont]).width)
        let countWidth: CGFloat = state.count > 0
            ? max(18, ceil(("\(state.count)" as NSString).size(withAttributes: [
                .font: TopicDetailTypography.interfaceFont(ofSize: 11, weight: .semibold),
            ]).width) + 10)
            : 0
        sharedIssueButtonMinWidthConstraint?.constant = 11 + Self.actionIconPointSize + 6 + titleWidth
            + (state.count > 0 ? max(28, countWidth + 7) : 11)
        sharedIssueCountLabel.text = state.count > 0 ? "\(state.count)" : nil
        sharedIssueCountLabel.textColor = state.userCreated ? .white : fluxBlue
        sharedIssueCountLabel.backgroundColor = state.userCreated
            ? fluxBlue.withAlphaComponent(0.92)
            : fluxBlue.withAlphaComponent(0.14)
        sharedIssueCountLabel.layer.borderWidth = state.userCreated ? 1.0 / UIScreen.main.scale : 0
        sharedIssueCountLabel.layer.borderColor = UIColor.white.withAlphaComponent(0.75).cgColor
        sharedIssueCountLabel.isHidden = state.count <= 0
        sharedIssueButton.accessibilityLabel = state.canCreate
            ? String(localized: "shared_issue.title")
            : String(localized: "shared_issue.author_title")
    }

    private func configureReactions(_ reactions: [DiscourseTopicDetail.Reaction], count: Int, baseURL: String) {
        guard !reactions.isEmpty else {
            reactionStackView.isHidden = true
            reactionCountLabel.isHidden = true
            return
        }

        let visible = reactions.prefix(3)
        for (i, iv) in reactionImageViews.enumerated() {
            if i < visible.count {
                let reaction = visible[visible.index(visible.startIndex, offsetBy: i)]
                if let url = URL(string: EmojiStore.lookup(for: reaction.id) ?? "") {
                    ForumImageLoader.setImage(on: iv, url: url)
                } else {
                    iv.sd_cancelCurrentImageLoad()
                    iv.image = nil
                }
                iv.isHidden = false
            } else {
                iv.isHidden = true
                iv.sd_cancelCurrentImageLoad()
                iv.image = nil
            }
        }

        if count > 0 {
            reactionCountLabel.text = "\(count)"
            reactionCountLabel.isHidden = false
        } else {
            reactionCountLabel.isHidden = true
        }

        reactionStackView.isHidden = false
    }

    private func updateFooterLayout() {
        // FluxDo: shared-issue on its own row above actions; replies stay left of action icons.
        bottomLeftStack.isHidden = showRepliesButton.isHidden
        let showsSharedIssue = !sharedIssueButton.isHidden
        sharedIssueButtonHeightConstraint?.constant = showsSharedIssue
            ? Metrics.sharedIssueButtonHeight
            : 0
        if showsSharedIssue {
            actionStackTopToContentConstraint?.isActive = false
            actionStackTopToSharedIssueConstraint?.isActive = true
        } else {
            actionStackTopToSharedIssueConstraint?.isActive = false
            actionStackTopToContentConstraint?.isActive = true
        }
    }

    private func configureReactionButton(for post: DiscourseTopicDetail.Post) {
        let symbol = post.currentUserReaction == nil ? "heart" : "heart.fill"
        let isActive = post.currentUserReaction != nil
        configureActionButton(
            reactButton,
            symbolName: symbol,
            tintColor: isActive ? .systemPink : .secondaryLabel,
            backgroundColor: .clear,
            accessibilityLabel: "喜欢"
        )
        reactionPillControl.backgroundColor = .clear
        reactionPillControl.layer.borderWidth = 0
        reactionPillControl.layer.borderColor = nil
    }

    private func configureBoostButton(for post: DiscourseTopicDetail.Post) {
        configureActionButton(
            boostButton,
            image: Self.boostIconImage,
            tintColor: .secondaryLabel,
            backgroundColor: .clear,
            accessibilityLabel: String(localized: "post.boost")
        )
        boostButton.isHidden = false
        // Pagination responses may omit can_boost; keep the slot so the footer geometry stays stable.
        boostButton.alpha = post.canBoost ? 1 : 0
        boostButton.isUserInteractionEnabled = post.canBoost
        boostButton.isEnabled = post.canBoost
        boostButton.isAccessibilityElement = post.canBoost
        boostButton.accessibilityElementsHidden = !post.canBoost
    }

    private func configureBookmarkButton(isBookmarked: Bool) {
        configureActionButton(
            bookmarkButton,
            symbolName: isBookmarked ? "bookmark.fill" : "bookmark",
            tintColor: isBookmarked ? .systemYellow : .secondaryLabel,
            backgroundColor: .clear,
            accessibilityLabel: isBookmarked ? "取消收藏" : "收藏"
        )
    }

    private func configureReplyButton() {
        configureActionButton(
            replyButton,
            symbolName: "arrowshape.turn.up.left",
            tintColor: .secondaryLabel,
            backgroundColor: .clear,
            accessibilityLabel: "回复"
        )
    }

    private func configureMoreMenu(isBookmarked: Bool) {
        configureActionButton(
            moreButton,
            symbolName: "ellipsis",
            tintColor: .secondaryLabel,
            backgroundColor: .clear,
            accessibilityLabel: "更多"
        )
        let copyAction = UIAction(title: "复制链接", image: UIImage(systemName: "link")) { [weak self] _ in
            self?.copyLinkTapped()
        }
        let copyHTMLAction = UIAction(
            title: String(localized: "post.copy_html", defaultValue: "复制原始HTML"),
            image: UIImage(systemName: "chevron.left.forwardslash.chevron.right")
        ) { [weak self] _ in
            guard let cooked = self?.currentPost?.cooked, !cooked.isEmpty else { return }
            UIPasteboard.general.string = cooked
        }
        let bookmarkAction = UIAction(
            title: isBookmarked ? "取消收藏" : "收藏",
            image: UIImage(systemName: isBookmarked ? "bookmark.slash" : "bookmark")
        ) { [weak self] _ in
            self?.bookmarkButtonTapped()
        }
        var actions: [UIMenuElement] = []
        if let post = currentPost, PostEditingPolicy.canShowEditAction(for: post) {
            actions.append(UIAction(
                title: String(localized: "post.edit.action", defaultValue: "编辑"),
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                guard let self, let post = self.currentPost else { return }
                self.delegate?.postCell(didTapEditPost: post)
            })
        }
        let shareImageAction = UIAction(
            title: String(localized: "topic.share_image", defaultValue: "生成分享图片"),
            image: UIImage(systemName: "photo")
        ) { [weak self] _ in
            guard let self, let post = self.currentPost else { return }
            self.delegate?.postCell(didTapShareImageForPost: post)
        }
        if currentPost?.showEditsIndicator == true {
            actions.append(UIAction(
                title: String(localized: "revision.title", defaultValue: "编辑历史"),
                image: UIImage(systemName: "clock.arrow.circlepath")
            ) { [weak self] _ in
                guard let self, let post = self.currentPost else { return }
                self.delegate?.postCell(didTapShowRevisionForPost: post)
            })
        }
        actions.append(contentsOf: [bookmarkAction, copyAction, copyHTMLAction, shareImageAction])
        moreButton.menu = UIMenu(title: "", children: actions)
    }

    private func configureActionButton(
        _ button: PostActionButton,
        symbolName: String,
        tintColor: UIColor,
        backgroundColor: UIColor,
        accessibilityLabel: String?
    ) {
        configureActionButton(
            button,
            image: UIImage(systemName: symbolName, withConfiguration: Self.actionSymbolConfig()),
            tintColor: tintColor,
            backgroundColor: backgroundColor,
            accessibilityLabel: accessibilityLabel
        )
    }

    private func configureActionButton(
        _ button: PostActionButton,
        image: UIImage?,
        tintColor: UIColor,
        backgroundColor: UIColor,
        accessibilityLabel: String?
    ) {
        button.configuration = nil
        button.setImage(nil, for: .normal)
        button.setFixedIcon(image.map(Self.normalizedActionIcon), tintColor: tintColor)
        button.tintColor = tintColor
        button.backgroundColor = backgroundColor
        button.layer.cornerRadius = Self.bottomBarHeight / 2
        button.layer.cornerCurve = .continuous
        button.accessibilityLabel = accessibilityLabel
        button.clipsToBounds = true
    }

    private static func actionSymbolConfig(
        pointSize: CGFloat = actionIconPointSize,
        weight: UIImage.SymbolWeight = .medium
    ) -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    }

    private static func normalizedActionIcon(_ image: UIImage) -> UIImage {
        guard image.size.width > 0, image.size.height > 0 else {
            return image.withRenderingMode(.alwaysTemplate)
        }

        let scale = min(
            actionIconCanvasSize.width / image.size.width,
            actionIconCanvasSize.height / image.size.height
        )
        let drawSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let drawRect = CGRect(
            x: (actionIconCanvasSize.width - drawSize.width) / 2,
            y: (actionIconCanvasSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        let renderer = UIGraphicsImageRenderer(size: actionIconCanvasSize)
        let rendered = renderer.image { _ in
            image.withRenderingMode(.alwaysOriginal).draw(in: drawRect)
        }
        return rendered.withRenderingMode(.alwaysTemplate)
    }

    private static var actionBackgroundColor: UIColor {
        .clear
    }

    // MARK: - View Setup

    private func setupTextViews(in view: UIView) {
        if let textView = view as? LinkTextView {
            textView.delegate = self
            textView.configureSpoilerIfNeeded()
            loadInlineImages(in: textView)
            return
        }
        if let textView = view as? UITextView {
            textView.delegate = self
            loadInlineImages(in: textView)
            return
        }
        for subview in view.subviews {
            setupTextViews(in: subview)
        }
    }

    // MARK: - Inline Image Loading

    private func loadInlineImages(in textView: UITextView) {
        guard let attrText = textView.attributedText else { return }
        let full = NSRange(location: 0, length: attrText.length)

        // Collect all (attachment, location, url, isEmoji) first — enumerateAttribute merges
        // adjacent characters that share the same URL into one range, so we must
        // iterate character-by-character inside each range.
        var entries: [(attachment: NSTextAttachment, location: Int, url: URL, isEmoji: Bool)] = []
        attrText.enumerateAttribute(.cookedHTMLImageURL, in: full) { value, range, _ in
            guard let urlString = value as? String,
                  let url = URL(string: urlString) else { return }
            for i in 0 ..< range.length {
                let loc = range.location + i
                if let attachment = attrText.attribute(.attachment, at: loc, effectiveRange: nil) as? NSTextAttachment {
                    // Emoji attachments have small bounds (≤ lineHeight); non-emoji have larger bounds
                    let isEmoji = attachment.bounds.width <= 24 && attachment.bounds.height <= 24
                    entries.append((attachment, loc, url, isEmoji))
                }
            }
        }

        for entry in entries {
            ForumImageLoader.loadImage(with: entry.url) { [weak textView] image in
                guard let textView, let image else { return }
                entry.attachment.image = image
                // Keep the bounds already set by the attributed string builder
                let charRange = NSRange(location: entry.location, length: 1)
                textView.textStorage.edited(.editedAttributes, range: charRange, changeInLength: 0)
            }
        }
    }

    // MARK: - Actions

    @objc private func repliesButtonTapped() {
        delegate?.postCell(didTapShowRepliesForPostId: postId)
    }

    @objc private func sharedIssueButtonTapped() {
        guard let topicId = currentSharedIssueTopicId else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.postCell(didTapToggleSharedIssueForTopicId: topicId)
    }

    @objc private func replyButtonTapped() {
        guard let post = currentPost else { return }
        delegate?.postCell(didTapReplyToPost: post)
    }

    @objc private func avatarTapped() {
        guard let username = currentPost?.username else { return }
        delegate?.postCell(didTapAvatarForUsername: username)
    }

    @objc private func copyLinkTapped() {
        guard let link = postLink else { return }
        UIPasteboard.general.string = link
        configureActionButton(
            moreButton,
            symbolName: "checkmark",
            tintColor: .systemGreen,
            backgroundColor: UIColor.systemGreen.withAlphaComponent(0.14),
            accessibilityLabel: "已复制"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.configureMoreMenu(isBookmarked: self.isBookmarked)
        }
    }

    @objc private func sourceButtonTapped() {
        UIPasteboard.general.string = cookedHTML
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        sourceButton.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
        sourceButton.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sourceButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
            self?.sourceButton.tintColor = .tertiaryLabel
        }
    }

    @objc private func reactButtonTapped() {
        guard let post = currentPost else { return }
        let reactionId = post.currentUserReaction?.id ?? "heart"
        delegate?.postCell(didTapReaction: reactionId, forPost: post)
    }

    @objc private func reactionPillLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let post = currentPost,
              !validReactions.isEmpty
        else { return }
        presentReactionPicker(for: post)
    }

    private func presentReactionPicker(for post: DiscourseTopicDetail.Post) {
        let pickerVC = UIViewController()
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pickerVC.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pickerVC.view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: pickerVC.view.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: pickerVC.view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: pickerVC.view.trailingAnchor, constant: -12),
        ])

        let emojiSize: CGFloat = 28
        for reactionId in validReactions {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: emojiSize),
                button.heightAnchor.constraint(equalToConstant: emojiSize),
            ])
            button.accessibilityLabel = reactionId

            if let urlString = EmojiStore.url(for: reactionId) ?? EmojiStore.lookup(for: reactionId),
               let url = URL(string: urlString)
            {
                let iv = UIImageView()
                iv.contentMode = .scaleAspectFit
                iv.translatesAutoresizingMaskIntoConstraints = false
                ForumImageLoader.setImage(on: iv, url: url)
                iv.isUserInteractionEnabled = false
                button.addSubview(iv)
                NSLayoutConstraint.activate([
                    iv.topAnchor.constraint(equalTo: button.topAnchor),
                    iv.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                    iv.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                ])
            } else {
                button.setTitle(":\(reactionId):", for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 12)
                button.setTitleColor(.label, for: .normal)
            }

            button.addAction(UIAction { [weak self] _ in
                guard let self, let post = self.currentPost else { return }
                pickerVC.dismiss(animated: true)
                self.delegate?.postCell(didTapReaction: reactionId, forPost: post)
            }, for: .touchUpInside)

            stack.addArrangedSubview(button)
        }

        let pickerSize = CGSize(
            width: CGFloat(validReactions.count) * (emojiSize + 8) + 16,
            height: emojiSize + 16
        )
        pickerVC.preferredContentSize = pickerSize
        pickerVC.modalPresentationStyle = .popover
        if let popover = pickerVC.popoverPresentationController {
            popover.sourceView = reactionPillControl
            popover.sourceRect = reactionPillControl.bounds
            popover.permittedArrowDirections = [.down, .up]
            popover.delegate = self
        }

        // Find presenting view controller
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                vc.present(pickerVC, animated: true)
                break
            }
            responder = next
        }
    }

    @objc private func boostButtonTapped() {
        guard let post = currentPost else { return }
        delegate?.postCell(didTapBoostForPost: post)
    }

    @objc private func bookmarkButtonTapped() {
        guard let post = currentPost else { return }
        let targetState = !isBookmarked
        isBookmarked = targetState
        configureBookmarkButton(isBookmarked: targetState)
        configureMoreMenu(isBookmarked: targetState)
        delegate?.postCell(didToggleBookmarkForPost: post, isBookmarked: targetState)
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
        boostButton.isHidden = false
        boostButton.alpha = 1
        boostButton.isUserInteractionEnabled = true
        boostButton.isEnabled = true
        boostButton.isAccessibilityElement = true
        boostButton.accessibilityElementsHidden = false
        configureBookmarkButton(isBookmarked: false)
        configureReplyButton()
        configureMoreMenu(isBookmarked: false)
        updateFooterLayout()
        let sourceConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        sourceButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: sourceConfig), for: .normal)
        sourceButton.tintColor = .tertiaryLabel
    }

    private static func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else { return isoString }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - UIColor hex helper

extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - UITextViewDelegate

extension PostNativeCell: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard interaction == .invokeDefaultAction else {
            return true
        }
        delegate?.postCell(didTapLinkURL: URL)
        return false
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension PostNativeCell: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}
