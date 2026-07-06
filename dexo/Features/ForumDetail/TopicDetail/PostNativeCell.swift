import CookedHTML
import SDWebImage
import UIKit

final class PostNativeCell: UITableViewCell {
    static let reuseIdentifier = "PostNativeCell"
    static let headerHeight: CGFloat = 44
    static let bottomBarHeight: CGFloat = 36
    fileprivate static let boostIconImage: UIImage = {
        let size = CGSize(width: 24, height: 24)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.black.setFill()

            let leftFin = UIBezierPath()
            leftFin.move(to: CGPoint(x: 8.2, y: 13.8))
            leftFin.addLine(to: CGPoint(x: 4.8, y: 18.8))
            leftFin.addCurve(to: CGPoint(x: 10.1, y: 17.1), controlPoint1: CGPoint(x: 6.7, y: 18.0), controlPoint2: CGPoint(x: 8.5, y: 17.4))
            leftFin.close()
            leftFin.fill()

            let rightFin = UIBezierPath()
            rightFin.move(to: CGPoint(x: 15.8, y: 13.8))
            rightFin.addLine(to: CGPoint(x: 19.2, y: 18.8))
            rightFin.addCurve(to: CGPoint(x: 13.9, y: 17.1), controlPoint1: CGPoint(x: 17.3, y: 18.0), controlPoint2: CGPoint(x: 15.5, y: 17.4))
            rightFin.close()
            rightFin.fill()

            let body = UIBezierPath()
            body.move(to: CGPoint(x: 12, y: 2.4))
            body.addCurve(to: CGPoint(x: 16.7, y: 13.9), controlPoint1: CGPoint(x: 16.0, y: 5.1), controlPoint2: CGPoint(x: 17.4, y: 10.0))
            body.addCurve(to: CGPoint(x: 12, y: 18.5), controlPoint1: CGPoint(x: 15.5, y: 16.5), controlPoint2: CGPoint(x: 13.9, y: 18.0))
            body.addCurve(to: CGPoint(x: 7.3, y: 13.9), controlPoint1: CGPoint(x: 10.1, y: 18.0), controlPoint2: CGPoint(x: 8.5, y: 16.5))
            body.addCurve(to: CGPoint(x: 12, y: 2.4), controlPoint1: CGPoint(x: 6.6, y: 10.0), controlPoint2: CGPoint(x: 8.0, y: 5.1))
            body.close()
            body.fill()

            let flame = UIBezierPath()
            flame.move(to: CGPoint(x: 12, y: 17.5))
            flame.addCurve(to: CGPoint(x: 14.1, y: 21.2), controlPoint1: CGPoint(x: 13.3, y: 18.6), controlPoint2: CGPoint(x: 14.2, y: 19.8))
            flame.addCurve(to: CGPoint(x: 12, y: 23.0), controlPoint1: CGPoint(x: 13.8, y: 22.1), controlPoint2: CGPoint(x: 12.9, y: 22.8))
            flame.addCurve(to: CGPoint(x: 9.9, y: 21.2), controlPoint1: CGPoint(x: 11.1, y: 22.8), controlPoint2: CGPoint(x: 10.2, y: 22.1))
            flame.addCurve(to: CGPoint(x: 12, y: 17.5), controlPoint1: CGPoint(x: 9.8, y: 19.8), controlPoint2: CGPoint(x: 10.7, y: 18.6))
            flame.close()
            flame.fill()

            context.cgContext.setBlendMode(.clear)
            UIBezierPath(ovalIn: CGRect(x: 9.7, y: 7.0, width: 4.6, height: 4.6)).fill()
            context.cgContext.setBlendMode(.normal)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()
    private static let firstPostPaperBackgroundColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.secondarySystemGroupedBackground
            : UIColor(red: 0.992, green: 0.984, blue: 0.961, alpha: 1)
    }
    private static let firstPostPaperBorderColor = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.separator.withAlphaComponent(0.28)
            : UIColor(red: 0.855, green: 0.824, blue: 0.753, alpha: 0.72)
    }

    static func firstPostRenderContentWidth(for tableWidth: CGFloat) -> CGFloat {
        let horizontalInset = (Metrics.cardOuterHorizontal + Metrics.cardInner + Metrics.firstPostContentInset) * 2
        return max(tableWidth - horizontalInset, 0)
    }

    private enum Metrics {
        static let cardOuterVertical: CGFloat = 6
        static let cardOuterHorizontal: CGFloat = 10
        static let cardInner: CGFloat = 16
        static let headerTop: CGFloat = 14
        static let avatarSize: CGFloat = 32
        static let avatarToText: CGFloat = 8
        static let contentTop: CGFloat = 10
        static let firstPostContentInset: CGFloat = 12
        static let actionTop: CGFloat = 10
        static let actionButtonWidth: CGFloat = 36
        static let actionSpacing: CGFloat = 8
        static let minimumReplyCardHeight: CGFloat = 80
    }

    weak var delegate: PostCellDelegate?
    private var postId: Int = 0
    private var postLink: String?
    private var currentPost: DiscourseTopicDetail.Post?
    private var cookedHTML: String = ""
    private var validReactions: [String] = []
    private var isBookmarked = false

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

    // MARK: - Header UI

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 16
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let flairImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 7
        iv.layer.borderWidth = 1
        iv.layer.borderColor = UIColor.systemBackground.cgColor
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        return iv
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
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
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let floorLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
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

    // MARK: - Bottom Bar

    private let showRepliesButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.tintColor = .secondaryLabel
        button.contentHorizontalAlignment = .leading
        button.isHidden = true
        return button
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
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "heart", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let boostButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(PostNativeCell.boostIconImage, for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = String(localized: "post.boost")
        return button
    }()

    private let bookmarkButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "bookmark", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let moreButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let replyButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
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
        cardView.addSubview(flairImageView)
        cardView.addSubview(nameLabel)
        cardView.addSubview(usernameLabel)
        cardView.addSubview(userTitleLabel)
        cardView.addSubview(timeLabel)
        cardView.addSubview(floorLabel)
        cardView.addSubview(sourceButton)
        cardView.addSubview(replyToLabel)
        cardView.addSubview(contentCardView)
        contentCardView.addSubview(contentStackView)
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
        let reactionPillWidthConstraint = reactionPillControl.widthAnchor.constraint(equalToConstant: 48)
        self.reactionPillWidthConstraint = reactionPillWidthConstraint

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Metrics.cardOuterVertical),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Metrics.cardOuterHorizontal),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Metrics.cardOuterHorizontal),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Metrics.cardOuterVertical),

            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.headerTop),
            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            avatarImageView.widthAnchor.constraint(equalToConstant: Metrics.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Metrics.avatarSize),

            flairImageView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 2),
            flairImageView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 2),
            flairImageView.widthAnchor.constraint(equalToConstant: 14),
            flairImageView.heightAnchor.constraint(equalToConstant: 14),

            nameLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.headerTop),
            nameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Metrics.avatarToText),

            usernameLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor),
            usernameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: Metrics.avatarToText),

            userTitleLabel.lastBaselineAnchor.constraint(equalTo: nameLabel.lastBaselineAnchor),
            userTitleLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            userTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: replyToLabel.leadingAnchor, constant: -8),

            replyToLabel.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            replyToLabel.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -8),

            sourceButton.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            sourceButton.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -6),
            sourceButton.widthAnchor.constraint(equalToConstant: 24),
            sourceButton.heightAnchor.constraint(equalToConstant: 24),

            floorLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: Metrics.headerTop),
            floorLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),

            timeLabel.topAnchor.constraint(equalTo: floorLabel.bottomAnchor, constant: 2),
            timeLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),

            contentCardView.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: Metrics.contentTop),
            contentCardView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            contentCardView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),
            contentTopConstraint,
            contentLeadingConstraint,
            contentTrailingConstraint,
            contentBottomConstraint,

            bottomLeftStack.topAnchor.constraint(equalTo: contentCardView.bottomAnchor, constant: Metrics.actionTop),
            bottomLeftStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Metrics.cardInner),
            bottomLeftStack.trailingAnchor.constraint(lessThanOrEqualTo: actionStackView.leadingAnchor, constant: -12),
            bottomLeftStack.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),

            actionStackView.topAnchor.constraint(equalTo: contentCardView.bottomAnchor, constant: Metrics.actionTop),
            actionStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Metrics.cardInner),
            actionStackView.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            { let c = actionStackView.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -8); c.priority = .init(999); return c }(),

            reactionPillStack.centerYAnchor.constraint(equalTo: reactionPillControl.centerYAnchor),
            reactionPillStack.leadingAnchor.constraint(equalTo: reactionPillControl.leadingAnchor, constant: 8),
            reactionPillStack.trailingAnchor.constraint(equalTo: reactionPillControl.trailingAnchor, constant: -4),
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
    ) {
        postId = post.id
        self.postLink = postLink
        currentPost = post
        self.delegate = delegate
        self.cookedHTML = cookedHTML
        self.validReactions = validReactions
        isBookmarked = post.bookmarked
        sourceButton.isHidden = !hasUnsupportedBlocks
        applyCardStyle(isFirstPost: floorNumber == 1)

        nameLabel.text = post.name
        usernameLabel.text = post.username
        timeLabel.text = Self.formatDate(post.createdAt)
        floorLabel.text = "#\(floorNumber)"

        // User title
        if let userTitle = post.userTitle, !userTitle.isEmpty {
            userTitleLabel.text = "\u{00B7} \(userTitle)"
            userTitleLabel.isHidden = false
        } else {
            userTitleLabel.isHidden = true
        }

        // Flair badge
        if let flairUrl = post.flairUrl, !flairUrl.isEmpty {
            let urlString = flairUrl.hasPrefix("http") ? flairUrl : baseURL + flairUrl
            if let url = URL(string: urlString) {
                if let bgColor = post.flairBgColor, !bgColor.isEmpty {
                    flairImageView.backgroundColor = UIColor(hex: bgColor)
                }
                flairImageView.sd_setImage(with: url)
                flairImageView.isHidden = false
            }
        }

        if let replyUser = post.replyToUser {
            let attachment = NSTextAttachment()
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            attachment.image = UIImage(systemName: "arrowshape.turn.up.left.fill", withConfiguration: symbolConfig)?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            let attrStr = NSMutableAttributedString(attachment: attachment)
            attrStr.append(NSAttributedString(string: " @\(replyUser.username)"))
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
            size: 96
        )
    }

    private func applyCardStyle(isFirstPost: Bool) {
        contentStackView.spacing = isFirstPost ? 12 : 10
        cardMinHeightConstraint?.constant = isFirstPost ? 0 : Metrics.minimumReplyCardHeight
        let contentInset = isFirstPost ? Metrics.firstPostContentInset : 0
        contentStackTopConstraint?.constant = contentInset
        contentStackLeadingConstraint?.constant = contentInset
        contentStackTrailingConstraint?.constant = -contentInset
        contentStackBottomConstraint?.constant = -contentInset

        if isFirstPost {
            cardView.backgroundColor = Self.firstPostPaperBackgroundColor
            cardView.layer.cornerRadius = 20
            cardView.layer.borderWidth = 1.0 / UIScreen.main.scale
            cardView.layer.borderColor = Self.firstPostPaperBorderColor.resolvedColor(with: traitCollection).cgColor
            cardView.layer.shadowOpacity = 0
            cardView.layer.shadowOffset = .zero
            cardView.layer.shadowRadius = 0
            separatorLine.backgroundColor = .clear

            contentCardView.backgroundColor = .clear
            contentCardView.layer.borderWidth = 0
            contentCardView.layer.borderColor = nil
            contentCardView.layer.shadowOpacity = 0
            contentCardView.layer.shadowOffset = .zero
            contentCardView.layer.shadowRadius = 0
        } else {
            cardView.backgroundColor = .secondarySystemGroupedBackground
            cardView.layer.cornerRadius = 14
            cardView.layer.borderWidth = 1.0 / UIScreen.main.scale
            cardView.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
            cardView.layer.shadowColor = UIColor.black.cgColor
            cardView.layer.shadowOpacity = 0.035
            cardView.layer.shadowOffset = CGSize(width: 0, height: 2)
            cardView.layer.shadowRadius = 8
            separatorLine.backgroundColor = UIColor.separator.withAlphaComponent(0.6)

            contentCardView.backgroundColor = .clear
            contentCardView.layer.borderWidth = 0
            contentCardView.layer.borderColor = nil
            contentCardView.layer.shadowOpacity = 0
            contentCardView.layer.shadowOffset = .zero
            contentCardView.layer.shadowRadius = 0
        }
    }

    private func configureRepliesButton(count: Int) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "bubble.left.fill", withConfiguration: Self.actionSymbolConfig(pointSize: 13))
        config.title = "\(count)"
        config.imagePadding = 6
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        config.baseForegroundColor = .secondaryLabel
        config.background.backgroundColor = Self.actionBackgroundColor
        config.background.cornerRadius = Self.bottomBarHeight / 2
        showRepliesButton.configuration = config
        showRepliesButton.clipsToBounds = true
    }

    private func configureReactions(_ reactions: [DiscourseTopicDetail.Reaction], count: Int, baseURL: String) {
        guard !reactions.isEmpty else {
            reactionStackView.isHidden = true
            reactionCountLabel.isHidden = true
            reactionPillWidthConstraint?.constant = 48
            return
        }

        let visible = reactions.prefix(3)
        for (i, iv) in reactionImageViews.enumerated() {
            if i < visible.count {
                let reaction = visible[visible.index(visible.startIndex, offsetBy: i)]
                if let url = URL(string: EmojiStore.lookup(for: reaction.id) ?? "") {
                    iv.sd_setImage(with: url)
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
        let countWidth = count > 0 ? reactionCountLabel.intrinsicContentSize.width + 6 : 0
        reactionPillWidthConstraint?.constant = min(max(48, 48 + visibleEmojiWidth + countWidth), 122)
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
            symbolName: "arrowshape.turn.up.left.fill",
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
        config.image = image?.withRenderingMode(.alwaysTemplate)
        config.baseForegroundColor = tintColor
        config.contentInsets = .zero
        config.background.backgroundColor = backgroundColor
        config.background.cornerRadius = Self.bottomBarHeight / 2
        button.configuration = config
        button.tintColor = tintColor
        button.accessibilityLabel = accessibilityLabel
        button.clipsToBounds = true
    }

    private static func actionSymbolConfig(pointSize: CGFloat = 16) -> UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
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
            SDWebImageManager.shared.loadImage(with: entry.url, progress: nil) { [weak textView] image, _, _, _, _, _ in
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
                iv.sd_setImage(with: url)
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
        usernameLabel.text = nil
        timeLabel.text = nil
        floorLabel.text = nil
        replyToLabel.attributedText = nil
        replyToLabel.text = nil
        replyToLabel.isHidden = true
        showRepliesButton.isHidden = true
        sourceButton.isHidden = true
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        userTitleLabel.text = nil
        userTitleLabel.isHidden = true
        flairImageView.sd_cancelCurrentImageLoad()
        flairImageView.image = nil
        flairImageView.backgroundColor = nil
        flairImageView.isHidden = true
        reactionStackView.isHidden = true
        for iv in reactionImageViews {
            iv.sd_cancelCurrentImageLoad()
            iv.image = nil
            iv.isHidden = true
        }
        reactionCountLabel.isHidden = true
        validReactions = []
        isBookmarked = false
        reactionPillWidthConstraint?.constant = 48
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
    private var isExpanded = false
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
        rebuildLinks()
    }

    private func makeHeader() -> UIView {
        let button = UIButton(type: .system)
        button.tintColor = .label
        button.contentHorizontalAlignment = .fill
        button.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)

        let iconView = UIImageView(image: UIImage(systemName: "link"))
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = String(localized: "post.related_links")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .systemBlue

        let countLabel = UILabel()
        countLabel.text = "\(links.count)"
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        countLabel.textColor = .systemBlue
        countLabel.textAlignment = .center
        countLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
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
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .systemBlue
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
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .systemBlue
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
        let container = UIView()
        container.backgroundColor = .tertiarySystemGroupedBackground
        container.layer.cornerRadius = 13
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1.0 / UIScreen.main.scale
        container.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconContainer = UIView()
        iconContainer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.14)
        iconContainer.layer.cornerRadius = 10
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: PostNativeCell.boostIconImage)
        iconView.tintColor = .systemBlue
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

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

        let titleLabel = UILabel()
        titleLabel.text = group.displayText.isEmpty ? String(localized: "post.boost") : group.displayText
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let countLabel = UILabel()
        countLabel.text = "\(group.boosts.count)"
        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        countLabel.backgroundColor = .systemBlue
        countLabel.layer.cornerRadius = 8
        countLabel.clipsToBounds = true
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        container.addSubview(avatarView)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),

            iconContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            iconContainer.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 20),
            iconContainer.heightAnchor.constraint(equalToConstant: 20),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),

            avatarView.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 4),
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

        return container
    }

    private func avatarURL(for template: String?) -> URL? {
        AvatarImageLoader.url(from: template, baseURL: baseURL, size: 48)
    }

    private static func makeGroups(from boosts: [DiscourseTopicDetail.Boost]) -> [BoostGroup] {
        var seenIds = Set<Int>()
        var order: [String] = []
        var grouped: [String: [DiscourseTopicDetail.Boost]] = [:]
        var displayTextByKey: [String: String] = [:]

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
            }
            grouped[key]?.append(boost)
        }

        return order.compactMap { key in
            guard let boosts = grouped[key], !boosts.isEmpty else { return nil }
            return BoostGroup(displayText: displayTextByKey[key] ?? "", boosts: boosts)
        }
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
    let boosts: [DiscourseTopicDetail.Boost]
}
