import CookedHTML
import SDWebImage
import UIKit

enum TopicDetailTypography {
    static func interfaceFont(ofSize pointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        let settings = AppSettings.shared
        let adjustedPointSize = settings.effectiveInterfacePointSize(for: pointSize)
        let baseFont = UIFont.systemFont(ofSize: adjustedPointSize, weight: weight)
        return settings.appInterfaceFont(matching: baseFont)
    }

    static func scaledInterfaceFont(
        ofSize pointSize: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle
    ) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: interfaceFont(ofSize: pointSize, weight: weight)
        )
    }

    static func topicTitleFont(relativeTo textStyle: UIFont.TextStyle = .headline) -> UIFont {
        let settings = AppSettings.shared
        let comfortFontDelta: CGFloat = settings.readingComfortMode ? 1 : 0
        let pointSize = settings.effectiveContentPointSize(
            for: settings.contentFontSize.basePointSize + comfortFontDelta
        )
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: settings.contentFont(ofSize: pointSize, weight: .semibold)
        )
    }

    static func contentContextFont(
        offsetFromBody offset: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle
    ) -> UIFont {
        let settings = AppSettings.shared
        let pointSize = contentContextPointSize(offsetFromBody: offset)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: settings.contentFont(ofSize: pointSize, weight: weight)
        )
    }

    static func contentContextMonospacedFont(
        offsetFromBody offset: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle
    ) -> UIFont {
        let settings = AppSettings.shared
        let pointSize = contentContextPointSize(offsetFromBody: offset)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: settings.contentMonospacedFont(ofSize: pointSize, weight: weight)
        )
    }

    static func contentVisualScale() -> CGFloat {
        let settings = AppSettings.shared
        let comfortFontDelta: CGFloat = settings.readingComfortMode ? 1 : 0
        let bodySourceSize = settings.contentFontSize.basePointSize + comfortFontDelta
        let bodySizeRatio = bodySourceSize / AppSettings.ContentFontSize.standard.basePointSize
        let scaleRatio = CGFloat(settings.contentFontScalePercent) / CGFloat(AppSettings.defaultFontScalePercent)
        return max(bodySizeRatio * scaleRatio, 0.75)
    }

    private static func contentContextPointSize(offsetFromBody offset: CGFloat) -> CGFloat {
        let settings = AppSettings.shared
        let comfortFontDelta: CGFloat = settings.readingComfortMode ? 1 : 0
        let sourcePointSize = max(settings.contentFontSize.basePointSize + comfortFontDelta + offset, 1)
        return settings.effectiveContentPointSize(for: sourcePointSize)
    }
}

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
    private static let actionIconCanvasSize = CGSize(width: 12, height: 12)
    private static let fontAwesomeSolidFontName = "FontAwesome5Free-Solid"
    private static let fontAwesomeSolidGlyphs: [String: String] = [
        "award": "\u{f559}",
        "book": "\u{f02d}",
        "book-open": "\u{f518}",
        "bookmark": "\u{f02e}",
        "bug": "\u{f188}",
        "bullseye": "\u{f140}",
        "certificate": "\u{f0a3}",
        "check": "\u{f00c}",
        "check-circle": "\u{f058}",
        "code": "\u{f121}",
        "comment": "\u{f075}",
        "comments": "\u{f086}",
        "crosshairs": "\u{f05b}",
        "eye": "\u{f06e}",
        "fire": "\u{f06d}",
        "flame": "\u{f06d}",
        "fist-raised": "\u{f6de}",
        "gavel": "\u{f0e3}",
        "gem": "\u{f3a5}",
        "graduation-cap": "\u{f19d}",
        "hammer": "\u{f6e3}",
        "hand": "\u{f256}",
        "hand-fist": "\u{f6de}",
        "hand-paper": "\u{f256}",
        "hand-rock": "\u{f255}",
        "heart": "\u{f004}",
        "laptop-code": "\u{f5fc}",
        "lightbulb": "\u{f0eb}",
        "magnifying-glass": "\u{f002}",
        "medal": "\u{f5a2}",
        "palette": "\u{f53f}",
        "people-group": "\u{f0c0}",
        "rocket": "\u{f135}",
        "search": "\u{f002}",
        "seedling": "\u{f4d8}",
        "shield": "\u{f3ed}",
        "shield-alt": "\u{f3ed}",
        "shield-halved": "\u{f3ed}",
        "star": "\u{f005}",
        "target": "\u{f140}",
        "terminal": "\u{f120}",
        "thumbs-down": "\u{f165}",
        "thumbs-up": "\u{f164}",
        "trophy": "\u{f091}",
        "user": "\u{f007}",
        "user-check": "\u{f4fc}",
        "user-graduate": "\u{f501}",
        "user-shield": "\u{f505}",
        "user-tag": "\u{f507}",
        "users": "\u{f0c0}",
        "wrench": "\u{f0ad}",
    ]
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
        let contentInset = isFirstPost ? Metrics.firstPostContentInset : 0
        let cardOuterHorizontal = isFirstPost ? Metrics.cardOuterHorizontal : Metrics.replyCardOuterHorizontal
        let horizontalInset = (cardOuterHorizontal + Metrics.cardInner + contentInset) * 2
        return max(tableWidth - horizontalInset, 0)
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
        static let actionButtonWidth: CGFloat = 32
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
    private var currentAvatarTemplateSize = 96

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
        button.titleLabel?.lineBreakMode = .byClipping
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
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

    private let reactionPillStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.alignment = .center
        sv.isUserInteractionEnabled = false
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()
    private var reactionPillWidthConstraint: NSLayoutConstraint?

    private let bottomLeftStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = 4
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let actionStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = Metrics.actionSpacing
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.setContentCompressionResistancePriority(.required, for: .horizontal)
        return sv
    }()

    private let reactButton: UIButton = {
        let button = UIButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "heart", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let boostButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(PostNativeCell.boostIconImage, for: .normal)
        button.tintColor = .tertiaryLabel
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = String(localized: "post.boost")
        return button
    }()

    private let bookmarkButton: UIButton = {
        let button = UIButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let moreButton: UIButton = {
        let button = UIButton(type: .system)
        let config = PostNativeCell.actionSymbolConfig()
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let replyButton: UIButton = {
        let button = UIButton(type: .system)
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
        cardView.addSubview(sourceButton)
        cardView.addSubview(replyToLabel)
        cardView.addSubview(contentCardView)
        contentCardView.addSubview(contentStackView)
        sharedIssueButton.addSubview(sharedIssueCountLabel)
        bottomLeftStack.addArrangedSubview(sharedIssueButton)
        bottomLeftStack.addArrangedSubview(showRepliesButton)
        for iv in reactionImageViews {
            reactionStackView.addArrangedSubview(iv)
            iv.isHidden = true
        }
        reactionStackView.addArrangedSubview(reactionCountLabel)
        reactionCountLabel.isHidden = true
        reactionPillStack.addArrangedSubview(reactionStackView)
        reactionPillStack.addArrangedSubview(reactButton)
        reactionPillControl.addSubview(reactionPillStack)
        actionStackView.addArrangedSubview(reactionPillControl)
        actionStackView.addArrangedSubview(boostButton)
        actionStackView.addArrangedSubview(bookmarkButton)
        actionStackView.addArrangedSubview(replyButton)
        actionStackView.addArrangedSubview(moreButton)
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
        let reactionPillWidthConstraint = reactionPillControl.widthAnchor.constraint(equalToConstant: 42)
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

            bottomLeftStack.topAnchor.constraint(equalTo: contentCardView.bottomAnchor, constant: Metrics.actionTop),
            bottomLeftStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            bottomLeftStack.trailingAnchor.constraint(lessThanOrEqualTo: actionStackView.leadingAnchor, constant: -8),
            bottomLeftStack.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            sharedIssueButtonMinWidthConstraint,
            sharedIssueButton.heightAnchor.constraint(equalToConstant: Metrics.sharedIssueButtonHeight),

            sharedIssueCountLabel.centerYAnchor.constraint(equalTo: sharedIssueButton.centerYAnchor),
            sharedIssueCountLabel.trailingAnchor.constraint(equalTo: sharedIssueButton.trailingAnchor, constant: -7),
            sharedIssueCountLabel.heightAnchor.constraint(equalToConstant: 18),
            sharedIssueCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),

            actionStackView.topAnchor.constraint(equalTo: contentCardView.bottomAnchor, constant: Metrics.actionTop),
            actionStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),
            actionStackView.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            { let c = actionStackView.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -8); c.priority = .init(999); return c }(),

            reactionPillStack.centerYAnchor.constraint(equalTo: reactionPillControl.centerYAnchor),
            reactionPillStack.leadingAnchor.constraint(equalTo: reactionPillControl.leadingAnchor, constant: 6),
            reactionPillStack.trailingAnchor.constraint(equalTo: reactionPillControl.trailingAnchor, constant: -3),
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

        // Render content blocks
        contentStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let views = NativeContentRenderer.renderBlocks(annotatedBlocks, config: config, delegate: delegate)
        for view in views {
            setupTextViews(in: view)
            contentStackView.addArrangedSubview(view)
        }
        adjustNativeContentSpacing()
        if let boostStripView = BoostStripView(boosts: post.boosts, baseURL: baseURL) {
            contentStackView.addArrangedSubview(boostStripView)
        }
        if let relatedLinksView = RelatedLinksCardView(linkCounts: post.linkCounts, baseURL: baseURL) {
            relatedLinksView.onTapURL = { [weak self] url in
                self?.delegate?.postCell(didTapLinkURL: url)
            }
            contentStackView.addArrangedSubview(relatedLinksView)
        }

        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: post.avatarTemplate,
            baseURL: baseURL,
            size: currentAvatarTemplateSize
        )
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
            || view is VideoCardView
            || view is OneboxCardView
            || view is FallbackBlockView
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

        currentAvatarTemplateSize = max(96, Int(ceil(avatarSize * UIScreen.main.scale)))
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
        guard let glyph = fontAwesomeGlyph(for: icon),
              let font = UIFont(name: Self.fontAwesomeSolidFontName, size: size)
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

    private func fontAwesomeGlyph(for icon: String?) -> String? {
        guard let rawIcon = icon?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawIcon.isEmpty
        else { return nil }

        let normalizedIcon = rawIcon
            .replacingOccurrences(of: "fa-solid", with: "fas")
            .replacingOccurrences(of: "fa-regular", with: "far")
            .replacingOccurrences(of: "fa-brands", with: "fab")
        let components = normalizedIcon
            .split(whereSeparator: { $0 == " " || $0 == "." })
            .map(String.init)

        let candidates = ([normalizedIcon] + components).map { component in
            component
                .replacingOccurrences(of: "fa-", with: "")
                .replacingOccurrences(of: "fas-", with: "")
                .replacingOccurrences(of: "far-", with: "")
                .replacingOccurrences(of: "fab-", with: "")
                .replacingOccurrences(of: "fas ", with: "")
                .replacingOccurrences(of: "far ", with: "")
                .replacingOccurrences(of: "fab ", with: "")
                .replacingOccurrences(of: "fa ", with: "")
                .replacingOccurrences(of: "_", with: "-")
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        }

        for candidate in candidates where !candidate.isEmpty {
            if let glyph = Self.fontAwesomeSolidGlyphs[fontAwesomeSolidAlias(for: candidate)] {
                return glyph
            }
        }
        return nil
    }

    private func fontAwesomeSolidAlias(for icon: String) -> String {
        let normalized = icon
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        switch normalized {
        case "book-open-reader":
            return "book-open"
        case "eye-low-vision":
            return "eye"
        case "fire-flame-curved", "fire-flame-simple":
            return "fire"
        case "hand-back-fist":
            return "hand-rock"
        case "magnifying-glass", "magnifying-glass-arrow-right", "magnifying-glass-chart",
             "magnifying-glass-dollar", "magnifying-glass-location", "magnifying-glass-minus",
             "magnifying-glass-plus":
            return "search"
        case "people-arrows", "people-carry-box", "people-group", "people-line",
             "people-pulling", "people-roof", "user-group", "users-between-lines",
             "users-gear", "users-line", "users-rays", "users-rectangle", "users-viewfinder":
            return "users"
        case "shield-halved", "shield-heart", "shield-virus":
            return "shield-alt"
        case "solid-bookmark":
            return "bookmark"
        case "solid-comment":
            return "comment"
        case "solid-comments":
            return "comments"
        case "solid-eye":
            return "eye"
        case "solid-gem":
            return "gem"
        case "solid-hand", "hand":
            return "hand-paper"
        case "solid-hand-back-fist", "hand-fist":
            return "fist-raised"
        case "solid-hand-point-down", "solid-hand-point-left", "solid-hand-point-right",
             "solid-hand-point-up", "hand-point-down", "hand-point-left", "hand-point-right",
             "hand-point-up":
            return "hand"
        case "solid-heart":
            return "heart"
        case "solid-lightbulb":
            return "lightbulb"
        case "solid-star":
            return "star"
        case "solid-thumbs-down":
            return "thumbs-down"
        case "solid-thumbs-up":
            return "thumbs-up"
        default:
            return normalized
        }
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
        guard let glyph = fontAwesomeGlyph(for: icon),
              let font = UIFont(name: Self.fontAwesomeSolidFontName, size: size)
        else { return nil }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let textSize = glyph.size(withAttributes: attributes)
            glyph.draw(
                at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2),
                withAttributes: attributes
            )
        }.withRenderingMode(.alwaysOriginal)
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
            reactionPillWidthConstraint?.constant = 42
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
        let visibleEmojiWidth = CGFloat(min(reactions.count, 3)) * 16 + CGFloat(max(0, min(reactions.count, 3) - 1)) * 2
        let countWidth = count > 0 ? reactionCountLabel.intrinsicContentSize.width + 4 : 0
        reactionPillWidthConstraint?.constant = min(max(42, 42 + visibleEmojiWidth + countWidth), 112)
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
        boostButton.isHidden = !post.canBoost
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
        let bookmarkAction = UIAction(
            title: isBookmarked ? "取消收藏" : "收藏",
            image: UIImage(systemName: isBookmarked ? "bookmark.slash" : "bookmark")
        ) { [weak self] _ in
            self?.bookmarkButtonTapped()
        }
        moreButton.menu = UIMenu(title: "", children: [bookmarkAction, copyAction])
    }

    private func configureActionButton(
        _ button: UIButton,
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
        _ button: UIButton,
        image: UIImage?,
        tintColor: UIColor,
        backgroundColor: UIColor,
        accessibilityLabel: String?
    ) {
        var config = UIButton.Configuration.plain()
        config.image = image.map { image in
            Self.normalizedActionIcon(image)
        }
        config.baseForegroundColor = tintColor
        config.contentInsets = .zero
        config.background.backgroundColor = backgroundColor
        config.background.cornerRadius = Self.bottomBarHeight / 2
        button.configuration = config
        button.tintColor = tintColor
        button.imageView?.contentMode = .scaleAspectFit
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
        // Cancel block-level image loads and fallback renders
        for view in contentStackView.arrangedSubviews {
            if let container = view as? TappableImageContainer {
                container.cancelImageLoad()
            } else if let onebox = view as? OneboxCardView {
                onebox.cancelImageLoad()
            } else if let video = view as? VideoCardView {
                video.cancelImageLoad()
            } else if let fallback = view as? FallbackBlockView {
                fallback.cancelRender()
            }
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
        reactionPillWidthConstraint?.constant = 42
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
        configureBookmarkButton(isBookmarked: false)
        configureReplyButton()
        configureMoreMenu(isBookmarked: false)
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

private extension UIColor {
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

// MARK: - Related Links

private final class RelatedLinksCardView: UIView {
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
                tableView.beginUpdates()
                tableView.endUpdates()
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

// MARK: - Boost Strip

private final class BoostStripView: UIView {
    private static let emojiShortcodeRegex = try! NSRegularExpression(pattern: ":([^\\s:]+(?::t\\d)?):")

    private let groups: [BoostGroup]
    private let baseURL: String

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init?(boosts: [DiscourseTopicDetail.Boost], baseURL: String) {
        let groups = Self.makeGroups(from: boosts)
        guard !groups.isEmpty else { return nil }
        self.groups = groups
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
        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        for group in groups {
            stackView.addArrangedSubview(makeBubble(for: group))
        }
    }

    private func makeBubble(for group: BoostGroup) -> UIView {
        let accentColor = AppSettings.shared.themeStyle.accentColor
        let container = UIView()
        container.backgroundColor = .tertiarySystemGroupedBackground
        container.layer.cornerRadius = 13
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1.0 / UIScreen.main.scale
        container.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let avatarView = UIImageView()
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 10
        avatarView.backgroundColor = .secondarySystemFill
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        AvatarImageLoader.setImage(
            on: avatarView,
            url: avatarURL(for: group.boosts.first?.user.avatarTemplate),
            placeholder: UIImage(systemName: "person.crop.circle.fill")
        )

        let titleFont = TopicDetailTypography.interfaceFont(ofSize: 12, weight: .regular)
        let titleText = attributedDisplayText(for: group, font: titleFont)
        let titleLabel = UILabel()
        titleLabel.attributedText = titleText
        titleLabel.font = titleFont
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let countLabel = UILabel()
        countLabel.text = "\(group.boosts.count)"
        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        countLabel.backgroundColor = accentColor
        countLabel.layer.cornerRadius = 8
        countLabel.clipsToBounds = true
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(avatarView)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),

            avatarView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            avatarView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 20),
            avatarView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
        ])

        if group.boosts.count > 1 {
            container.addSubview(countLabel)
            NSLayoutConstraint.activate([
                countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
                countLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -7),
                countLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
                countLabel.heightAnchor.constraint(equalToConstant: 18),
            ])
        } else {
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8).isActive = true
        }

        loadInlineImages(in: titleLabel, attributedString: titleText)
        return container
    }

    private func avatarURL(for template: String?) -> URL? {
        AvatarImageLoader.url(from: template, baseURL: baseURL, size: 48)
    }

    private func attributedDisplayText(for group: BoostGroup, font: UIFont) -> NSMutableAttributedString {
        let fallbackText = group.displayText.isEmpty ? String(localized: "post.boost") : group.displayText
        let inlines = Self.displayInlines(from: group.cookedHTML, baseURL: baseURL)
        let attributed: NSMutableAttributedString
        if inlines.isEmpty {
            attributed = NSMutableAttributedString(string: fallbackText, attributes: [
                .font: font,
                .foregroundColor: UIColor.label,
            ])
        } else {
            attributed = NSMutableAttributedString(attributedString: inlines.attributedString(config: AttributedStringConfig(
                baseFont: font,
                baseColor: .label,
                linkColor: AppSettings.shared.themeStyle.accentColor,
                codeFont: .monospacedSystemFont(ofSize: max(font.pointSize - 1, 1), weight: .regular),
                codeBackgroundColor: .clear
            )))
        }
        return Self.replacingEmojiShortcodes(in: attributed, font: font, textColor: .label)
    }

    private func loadInlineImages(in label: UILabel, attributedString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        guard fullRange.length > 0 else { return }

        var entries: [(attachment: NSTextAttachment, url: URL)] = []
        attributedString.enumerateAttributes(in: fullRange) { attributes, _, _ in
            guard let attachment = attributes[.attachment] as? NSTextAttachment else { return }

            if let emojiAttachment = attachment as? EmojiTextAttachment,
               let url = emojiAttachment.emojiURL {
                entries.append((attachment, url))
                return
            }

            guard let urlString = attributes[.cookedHTMLImageURL] as? String,
                  let url = URL(string: urlString)
            else { return }
            entries.append((attachment, url))
        }

        for entry in entries {
            ForumImageLoader.loadImage(with: entry.url) { [weak label, attributedString] image in
                guard let image else { return }
                DispatchQueue.main.async {
                    entry.attachment.image = image
                    label?.attributedText = attributedString
                    label?.setNeedsDisplay()
                }
            }
        }
    }

    private static func makeGroups(from boosts: [DiscourseTopicDetail.Boost]) -> [BoostGroup] {
        var seenIds = Set<Int>()
        var order: [String] = []
        var grouped: [String: [DiscourseTopicDetail.Boost]] = [:]
        var displayTextByKey: [String: String] = [:]
        var cookedHTMLByKey: [String: String] = [:]

        for boost in boosts {
            guard seenIds.insert(boost.id).inserted else { continue }
            let displayText = plainText(from: boost.cooked)
            let key = displayText.isEmpty
                ? boost.cooked.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                : displayText.lowercased()
            guard !key.isEmpty else { continue }
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
                displayTextByKey[key] = displayText
                cookedHTMLByKey[key] = boost.cooked
            }
            grouped[key]?.append(boost)
        }

        return order.compactMap { key in
            guard let boosts = grouped[key], !boosts.isEmpty else { return nil }
            return BoostGroup(displayText: displayTextByKey[key] ?? "", cookedHTML: cookedHTMLByKey[key] ?? "", boosts: boosts)
        }
    }

    private static func displayInlines(from html: String, baseURL: String) -> [InlineNode] {
        let chunks = CookedHTMLParser.parse(html: html, baseURL: baseURL).map(displayInlines(from:))
        return joinedInlines(chunks).trimmedWhitespace()
    }

    private static func displayInlines(from block: ContentBlock) -> [InlineNode] {
        switch block {
        case .paragraph(let inlines), .heading(_, let inlines):
            return normalizedDisplayInlines(inlines)
        case .blockquote(let blocks), .spoiler(let blocks):
            return joinedInlines(blocks.map(displayInlines(from:)))
        case .discourseQuote(_, _, _, _, _, _, _, let content):
            return joinedInlines(content.map(displayInlines(from:)))
        case .list(_, let items):
            return joinedInlines(items.map { item in
                normalizedDisplayInlines(item.content) + joinedInlines(item.children.map(displayInlines(from:)))
            })
        case .poll(let poll):
            return joinedInlines(poll.options.map { [.text($0.text)] })
        case .details(let summary, let content):
            return normalizedDisplayInlines(summary) + joinedInlines(content.map(displayInlines(from:)))
        case .image(let src, let alt, let width, let height, _):
            if isLikelyEmojiImage(src: src, width: width, height: height) {
                return [.image(src: src, alt: alt, width: width, height: height, isEmoji: true)]
            }
            return alt.flatMap { $0.isEmpty ? nil : [.text($0)] } ?? []
        case .onebox(_, let title, let description, _, _, _, _):
            return [title, description]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { InlineNode.text($0) }
        case .video(_, _, let title, _, _, _, _):
            return title.flatMap { $0.isEmpty ? nil : [.text($0)] } ?? []
        case .codeBlock(_, let code):
            return code.isEmpty ? [] : [.text(code)]
        case .table(let headers, let rows):
            let headerInlines = headers.flatMap { $0.map(displayInlines(from:)) }
            let rowInlines = rows.flatMap { row in row.flatMap { $0.map(displayInlines(from:)) } }
            return joinedInlines(headerInlines + rowInlines)
        case .divider:
            return []
        case .rawHTML(let html):
            let text = plainText(from: html)
            return text.isEmpty ? [] : [.text(text)]
        }
    }

    private static func isLikelyEmojiImage(src: String, width: Int?, height: Int?) -> Bool {
        let lowercasedSource = src.lowercased()
        if lowercasedSource.contains("/emoji") || lowercasedSource.contains("emoji/") {
            return true
        }
        guard let width, let height, width > 0, height > 0 else {
            return false
        }
        return width <= 32 && height <= 32
    }

    private static func normalizedDisplayInlines(_ inlines: [InlineNode]) -> [InlineNode] {
        inlines.map { inline in
            switch inline {
            case .lineBreak:
                return .text(" ")
            case .link(let href, let children):
                return .link(href: href, children: normalizedDisplayInlines(children))
            case .spoiler(let children):
                return .spoiler(children: normalizedDisplayInlines(children))
            default:
                return inline
            }
        }
    }

    private static func joinedInlines(_ chunks: [[InlineNode]]) -> [InlineNode] {
        var result: [InlineNode] = []
        for chunk in chunks where !chunk.isEmpty {
            if !result.isEmpty {
                result.append(.text(" "))
            }
            result.append(contentsOf: chunk)
        }
        return result
    }

    private static func replacingEmojiShortcodes(
        in attributed: NSAttributedString,
        font: UIFont,
        textColor: UIColor
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return result }

        attributed.enumerateAttributes(in: fullRange) { attributes, range, _ in
            if attributes[.attachment] != nil {
                result.append(attributed.attributedSubstring(from: range))
                return
            }

            let text = attributed.attributedSubstring(from: range).string
            guard text.contains(":") else {
                result.append(attributed.attributedSubstring(from: range))
                return
            }

            var textAttributes = attributes
            textAttributes[.font] = textAttributes[.font] ?? font
            textAttributes[.foregroundColor] = textAttributes[.foregroundColor] ?? textColor
            result.append(emojiAttributedString(from: text, attributes: textAttributes, font: font))
        }
        return result
    }

    private static func emojiAttributedString(
        from text: String,
        attributes: [NSAttributedString.Key: Any],
        font: UIFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = emojiShortcodeRegex.matches(in: text, range: fullRange)
        var lastLocation = 0

        for match in matches {
            let plainLength = match.range.location - lastLocation
            if plainLength > 0 {
                result.append(NSAttributedString(
                    string: nsText.substring(with: NSRange(location: lastLocation, length: plainLength)),
                    attributes: attributes
                ))
            }

            let shortcode = nsText.substring(with: match.range)
            let code = nsText.substring(with: match.range(at: 1))
            if let urlString = EmojiStore.url(for: code), let url = URL(string: urlString) {
                let emojiSize = font.pointSize
                let attachment = EmojiTextAttachment()
                attachment.emojiURL = url
                attachment.shortcode = shortcode
                attachment.image = UIImage()
                attachment.bounds = CGRect(
                    x: 0,
                    y: (font.capHeight - emojiSize) / 2,
                    width: emojiSize,
                    height: emojiSize
                )
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(string: shortcode, attributes: attributes))
            }

            lastLocation = match.range.location + match.range.length
        }

        if lastLocation < nsText.length {
            result.append(NSAttributedString(
                string: nsText.substring(from: lastLocation),
                attributes: attributes
            ))
        }
        return result
    }

    private static func plainText(from html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<img[^>]*(?:title|alt)=\"([^\"]+)\"[^>]*>",
            with: " $1 ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</(p|div|li|blockquote)>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let decoded: String
        if let data = text.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ) {
            decoded = attributed.string
        } else {
            decoded = text
        }

        return decoded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct BoostGroup {
    let displayText: String
    let cookedHTML: String
    let boosts: [DiscourseTopicDetail.Boost]
}
