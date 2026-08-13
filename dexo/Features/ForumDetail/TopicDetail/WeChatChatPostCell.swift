import CookedHTML
import SDWebImage
import UIKit

/// Chat bubble row for Topic Detail (WeChat / Telegram themes).
/// Classic `PostNativeCell` is untouched — this is a parallel surface.
protocol WeChatChatPostCellDelegate: AnyObject {
    func weChatChatPostCell(_ cell: WeChatChatPostCell, didRequestLike post: DiscourseTopicDetail.Post)
    func weChatChatPostCell(_ cell: WeChatChatPostCell, didRequestReply post: DiscourseTopicDetail.Post)
    func weChatChatPostCell(_ cell: WeChatChatPostCell, didRequestBookmark post: DiscourseTopicDetail.Post)
    func weChatChatPostCell(_ cell: WeChatChatPostCell, didRequestBoost post: DiscourseTopicDetail.Post)
    func weChatChatPostCell(_ cell: WeChatChatPostCell, didTapAvatar username: String)
}

final class WeChatChatPostCell: UITableViewCell {
    static let reuseIdentifier = "WeChatChatPostCell"

    private enum Metrics {
        static let horizontalInset: CGFloat = 8
        static let avatarBubbleGap: CGFloat = 6
        /// WeChat default; Telegram uses `ChatTopicStyle.bubblePadding`.
        static let bubblePadding: CGFloat = 10
        static let contentSpacing: CGFloat = 4
        static let actionBarHeight: CGFloat = 30
    }

    private var chatStyle: ChatTopicStyle { ChatTopicStyle.current ?? .weChat }
    private var bubblePadding: CGFloat {
        chatStyle == .telegram ? chatStyle.bubblePadding : Metrics.bubblePadding
    }

    weak var actionDelegate: WeChatChatPostCellDelegate?
    weak var contentDelegate: PostCellDelegate?

    private var currentPost: DiscourseTopicDetail.Post?
    private var imageBaseURL: String?
    private var isMine = false
    private var heightReconcileGeneration = 0
    private var lastReconciledHeight: CGFloat = 0

    private let dateChipLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.85)
        label.layer.cornerRadius = 11
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 4
        iv.layer.cornerCurve = .continuous
        iv.backgroundColor = .secondarySystemFill
        iv.isUserInteractionEnabled = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private var avatarWidthConstraint: NSLayoutConstraint?
    private var avatarHeightConstraint: NSLayoutConstraint?
    private var avatarTopConstraint: NSLayoutConstraint?
    private var avatarBottomConstraint: NSLayoutConstraint?

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let bubbleView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 8
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = Metrics.contentSpacing
        // `.fill` + low vertical hugging lets UITextView eat free height → hollow bubble middle.
        // Arranged subviews pin vertical hugging to required in configure(_:).
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var contentStackTopConstraint: NSLayoutConstraint?
    private var contentStackLeadingConstraint: NSLayoutConstraint?
    private var contentStackTrailingConstraint: NSLayoutConstraint?
    private var contentStackBottomConstraint: NSLayoutConstraint?
    private var contentStackWidthConstraint: NSLayoutConstraint?

    /// Time under the bubble (trailing) — no longer inside the bubble (avoids empty tail row).
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .tertiaryLabel
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    /// Like / bookmark / reply under the bubble (not long-press only).
    private let actionBar: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let likeButton = UIButton(type: .system)
    private let bookmarkButton = UIButton(type: .system)
    private let replyButton = UIButton(type: .system)
    private let boostActionButton = UIButton(type: .system)
    private let voteUpButton = UIButton(type: .system)
    private let voteDownButton = UIButton(type: .system)
    private let voteCountLabel = UILabel()

    private var avatarLeadingConstraint: NSLayoutConstraint?
    private var avatarTrailingConstraint: NSLayoutConstraint?
    private var bubbleLeadingConstraint: NSLayoutConstraint?
    private var bubbleTrailingConstraint: NSLayoutConstraint?
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private var bubbleTopToNameConstraint: NSLayoutConstraint?
    private var bubbleTopToDateConstraint: NSLayoutConstraint?
    private var nameLeadingConstraint: NSLayoutConstraint?
    private var nameTrailingConstraint: NSLayoutConstraint?
    private var nameHeightConstraint: NSLayoutConstraint?
    private var underBubbleLeadingConstraint: NSLayoutConstraint?
    private var underBubbleTrailingConstraint: NSLayoutConstraint?
    private var dateChipTopConstraint: NSLayoutConstraint?
    private var dateChipHeightConstraint: NSLayoutConstraint?

    /// Row under bubble: [actions …… time]
    private let underBubbleRow: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var underBubbleRowHeightConstraint: NSLayoutConstraint?
    private var underBubbleRowTopConstraint: NSLayoutConstraint?

    /// Holds `BoostStripView` **below** the chat bubble (not inside it).
    private let boostHost: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = false
        view.isHidden = true
        return view
    }()

    private var boostHostHeightConstraint: NSLayoutConstraint?
    private var boostHostTopConstraint: NSLayoutConstraint?
    private var boostLeadingConstraint: NSLayoutConstraint?
    private var boostTrailingConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = true
        clipsToBounds = true
        setupUI()
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        bubbleView.addGestureRecognizer(longPress)
        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(handleAvatarTap))
        avatarImageView.addGestureRecognizer(avatarTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(dateChipLabel)
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(bubbleView)
        contentView.addSubview(underBubbleRow)
        contentView.addSubview(boostHost)
        bubbleView.addSubview(contentStack)

        configureActionButtons()
        let actionSpacer = UIView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        underBubbleRow.addArrangedSubview(actionBar)
        underBubbleRow.addArrangedSubview(actionSpacer)
        underBubbleRow.addArrangedSubview(timeLabel)

        let avatarLead = avatarImageView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: Metrics.horizontalInset
        )
        let avatarTrail = avatarImageView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -Metrics.horizontalInset
        )
        let bubbleLead = bubbleView.leadingAnchor.constraint(
            equalTo: avatarImageView.trailingAnchor,
            constant: Metrics.avatarBubbleGap
        )
        let bubbleTrail = bubbleView.trailingAnchor.constraint(
            equalTo: avatarImageView.leadingAnchor,
            constant: -Metrics.avatarBubbleGap
        )
        let bubbleWidth = bubbleView.widthAnchor.constraint(equalToConstant: 240)
        bubbleWidth.priority = .required

        let nameLead = nameLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor)
        let nameTrail = nameLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        let underLead = underBubbleRow.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor)
        let underTrail = underBubbleRow.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)

        avatarLeadingConstraint = avatarLead
        avatarTrailingConstraint = avatarTrail
        bubbleLeadingConstraint = bubbleLead
        bubbleTrailingConstraint = bubbleTrail
        bubbleWidthConstraint = bubbleWidth
        nameLeadingConstraint = nameLead
        nameTrailingConstraint = nameTrail
        underBubbleLeadingConstraint = underLead
        underBubbleTrailingConstraint = underTrail

        let nameHeight = nameLabel.heightAnchor.constraint(equalToConstant: 16)
        nameHeightConstraint = nameHeight

        let avatarW = avatarImageView.widthAnchor.constraint(equalToConstant: 40)
        let avatarH = avatarImageView.heightAnchor.constraint(equalToConstant: 40)
        avatarWidthConstraint = avatarW
        avatarHeightConstraint = avatarH

        let avatarTop = avatarImageView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4)
        let avatarBottom = avatarImageView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)
        avatarTopConstraint = avatarTop
        avatarBottomConstraint = avatarBottom

        let bubbleTopName = bubbleView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4)
        let bubbleTopDate = bubbleView.topAnchor.constraint(equalTo: dateChipLabel.bottomAnchor, constant: 8)
        bubbleTopDate.isActive = false
        bubbleTopToNameConstraint = bubbleTopName
        bubbleTopToDateConstraint = bubbleTopDate

        let stackTop = contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: Metrics.bubblePadding)
        let stackLead = contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: Metrics.bubblePadding)
        let stackTrail = contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -Metrics.bubblePadding)
        let stackBottom = contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -Metrics.bubblePadding)
        let stackWidth = contentStack.widthAnchor.constraint(
            equalTo: bubbleView.widthAnchor,
            constant: -Metrics.bubblePadding * 2
        )
        contentStackTopConstraint = stackTop
        contentStackLeadingConstraint = stackLead
        contentStackTrailingConstraint = stackTrail
        contentStackBottomConstraint = stackBottom
        contentStackWidthConstraint = stackWidth

        // under bubble: actions + time, then boost chips, then bottom pad.
        let underTop = underBubbleRow.topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 4)
        let underHeight = underBubbleRow.heightAnchor.constraint(equalToConstant: Metrics.actionBarHeight)
        underBubbleRowTopConstraint = underTop
        underBubbleRowHeightConstraint = underHeight

        let boostTop = boostHost.topAnchor.constraint(equalTo: underBubbleRow.bottomAnchor, constant: 0)
        let boostHeight = boostHost.heightAnchor.constraint(equalToConstant: 0)
        boostHostTopConstraint = boostTop
        boostHostHeightConstraint = boostHeight
        let boostLead = boostHost.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor)
        let boostTrail = boostHost.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        boostLeadingConstraint = boostLead
        boostTrailingConstraint = boostTrail

        let dateTop = dateChipLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 0)
        let dateHeight = dateChipLabel.heightAnchor.constraint(equalToConstant: 0)
        dateChipTopConstraint = dateTop
        dateChipHeightConstraint = dateHeight

        NSLayoutConstraint.activate([
            dateTop,
            dateChipLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dateHeight,
            dateChipLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),

            avatarW,
            avatarH,
            avatarTop,

            nameLabel.topAnchor.constraint(equalTo: dateChipLabel.bottomAnchor, constant: 2),
            nameHeight,

            bubbleTopName,
            bubbleWidth,

            stackTop, stackLead, stackTrail, stackBottom, stackWidth,

            underTop,
            underHeight,
            underLead,
            underTrail,

            boostTop,
            boostHeight,
            boostLead,
            boostTrail,
            boostHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])

        avatarLead.isActive = true
        bubbleLead.isActive = true
        nameLead.isActive = true
        underLead.isActive = true

        bubbleView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bubbleView.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        bubbleView.setContentHuggingPriority(.required, for: .vertical)
        bubbleView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.setContentHuggingPriority(.required, for: .vertical)
        contentStack.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func configureActionButtons() {
        let buttons: [(UIButton, String, Selector)] = [
            (voteUpButton, "chevron.up", #selector(handleVoteUpTapped)),
            (voteDownButton, "chevron.down", #selector(handleVoteDownTapped)),
            (likeButton, "heart", #selector(handleLikeTapped)),
            (bookmarkButton, "bookmark", #selector(handleBookmarkTapped)),
            (replyButton, "arrowshape.turn.up.left", #selector(handleReplyTapped)),
            (boostActionButton, "bolt.fill", #selector(handleBoostTapped)),
        ]
        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        voteCountLabel.translatesAutoresizingMaskIntoConstraints = false
        voteCountLabel.font = TopicDetailTypography.chromeFont(.action, weight: .semibold)
        voteCountLabel.adjustsFontForContentSizeCategory = true
        voteCountLabel.textColor = .secondaryLabel
        voteCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        for (button, name, sel) in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setImage(UIImage(systemName: name, withConfiguration: symbol), for: .normal)
            button.tintColor = .secondaryLabel
            button.addTarget(self, action: sel, for: .touchUpInside)
            button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
            button.setContentHuggingPriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: Metrics.actionBarHeight),
                button.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            ])
            actionBar.addArrangedSubview(button)
            if button === voteUpButton {
                actionBar.addArrangedSubview(voteCountLabel)
            }
        }
        voteUpButton.isHidden = true
        voteDownButton.isHidden = true
        voteCountLabel.isHidden = true
    }

    func configure(
        with post: DiscourseTopicDetail.Post,
        annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig,
        floorNumber: Int,
        baseURL: String,
        contentDelegate: PostCellDelegate?,
        dateSeparatorText: String? = nil
    ) {
        currentPost = post
        self.contentDelegate = contentDelegate
        imageBaseURL = baseURL
        isMine = post.yours
        let style = chatStyle
        let isTelegram = style == .telegram
        let pad = bubblePadding

        // Keep stack insets in sync with theme padding.
        contentStackTopConstraint?.constant = pad
        contentStackLeadingConstraint?.constant = pad
        contentStackTrailingConstraint?.constant = -pad
        contentStackBottomConstraint?.constant = -pad
        contentStackWidthConstraint?.constant = -(pad * 2)

        // Keep row fully transparent so Telegram/WeChat chat canvas shows through.
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        backgroundView = nil
        selectedBackgroundView = nil

        applyAlignment(isMine: isMine)
        applyChatChrome()
        applyDateSeparator(dateSeparatorText)

        // Explicit bubble width from render config — avoids zero-width ambiguous layout
        // that produced the thin empty white strips in screenshots.
        let innerWidth = max(config.contentWidth, 120)
        let bubbleWidth = innerWidth + pad * 2
        bubbleWidthConstraint?.constant = bubbleWidth

        let displayName = (post.name?.isEmpty == false ? post.name : nil) ?? post.username
        let isDark = traitCollection.userInterfaceStyle == .dark

        if isTelegram {
            // Name lives inside the bubble (group-chat style).
            nameLabel.isHidden = true
            nameHeightConstraint?.constant = 0
        } else {
            nameLabel.text = displayName
            nameLabel.textAlignment = isMine ? .right : .left
            nameLabel.isHidden = isMine
            nameHeightConstraint?.constant = isMine ? 0 : 16
            nameLabel.font = TopicDetailTypography.chromeFont(.authorMeta, weight: .regular)
            nameLabel.adjustsFontForContentSizeCategory = true
            nameLabel.textColor = .secondaryLabel
        }

        // Time is always outside the bubble (trailing under-bubble row).
        // Avoids the empty full-width time row that hollowed long bubbles.
        if isTelegram {
        timeLabel.text = self.formatBubbleTime(post.createdAt)
        } else {
            timeLabel.text = "#\(floorNumber) · \(TopicCell.formatDate(post.createdAt))"
        }
        timeLabel.font = TopicDetailTypography.chromeFont(.time, weight: .regular)
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textColor = style.bubbleTimeColor(isMine: isMine, isDark: isDark)
        timeLabel.textAlignment = .right

        configureActionBar(for: post, style: style)

        bubbleView.backgroundColor = isMine
            ? style.outgoingBubbleColor(isDark: isDark)
            : style.incomingBubbleColor(isDark: isDark)

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.spacing = isTelegram ? 3 : Metrics.contentSpacing

        // Telegram: name + optional admin badge inside bubble top.
        if isTelegram, !isMine {
            pinArrangedSubview(
                makeTelegramNameHeader(displayName: displayName, post: post),
                contentWidth: innerWidth,
                isTextMedia: false
            )
        }

        // Telegram: reply quote strip.
        if isTelegram, let replyUser = post.replyToUser {
            pinArrangedSubview(
                makeTelegramReplyQuote(replyUser: replyUser, post: post, isDark: isDark),
                contentWidth: innerWidth,
                isTextMedia: false
            )
        }

        let views = NativeContentRenderer.renderBlocks(
            annotatedBlocks,
            config: config,
            delegate: contentDelegate
        )
        if views.isEmpty {
            let fallback = makeFallbackLabel(for: post, config: config, baseURL: baseURL)
            if let fallback {
                pinArrangedSubview(fallback, contentWidth: innerWidth)
            }
        } else {
            for view in views {
                if isEmptySpacerView(view) { continue }
                pinArrangedSubview(view, contentWidth: innerWidth)
            }
        }

        // If still empty after render, force plain text.
        let hasBody = contentStack.arrangedSubviews.contains { view in
            view.tag != 88001 && view.tag != 88002
        }
        if !hasBody {
            if let fallback = makeFallbackLabel(for: post, config: config, baseURL: baseURL) {
                contentStack.addArrangedSubview(fallback)
            } else {
                let placeholder = UILabel()
                placeholder.font = config.baseFont
                placeholder.textColor = .tertiaryLabel
                placeholder.text = String(localized: "wechat_chat.empty_post", defaultValue: "（无文本内容）")
                contentStack.addArrangedSubview(placeholder)
            }
        }

        // Boost chips under the action/time row (still outside the bubble).
        installBoostStrip(for: post, baseURL: baseURL)

        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: post.avatarTemplate,
            baseURL: baseURL,
            size: AvatarImageLoader.primaryAvatarPixelSize
        )
        setNeedsLayout()
        layoutIfNeeded()
        requestHeightReconciliation()
    }

    private func configureActionBar(for post: DiscourseTopicDetail.Post, style: ChatTopicStyle) {
        let accent = style.accentColor
        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)

        // Like
        let liked = post.currentUserReaction != nil
        let likeCount = post.reactionUsersCount
        let likeName = liked ? "heart.fill" : "heart"
        likeButton.setImage(UIImage(systemName: likeName, withConfiguration: symbol), for: .normal)
        likeButton.tintColor = liked ? .systemPink : .secondaryLabel
        if likeCount > 0 {
            likeButton.setTitle(" \(likeCount)", for: .normal)
            likeButton.titleLabel?.font = TopicDetailTypography.chromeFont(.action, weight: .medium)
            likeButton.setTitleColor(likeButton.tintColor, for: .normal)
        } else {
            likeButton.setTitle(nil, for: .normal)
        }
        likeButton.isHidden = post.yours
        likeButton.isEnabled = !post.yours

        // Bookmark
        let bookmarked = post.bookmarked
        bookmarkButton.setImage(
            UIImage(systemName: bookmarked ? "bookmark.fill" : "bookmark", withConfiguration: symbol),
            for: .normal
        )
        bookmarkButton.tintColor = bookmarked ? accent : .secondaryLabel
        bookmarkButton.setTitle(nil, for: .normal)

        // Reply
        replyButton.setImage(
            UIImage(systemName: "arrowshape.turn.up.left", withConfiguration: symbol),
            for: .normal
        )
        replyButton.tintColor = .secondaryLabel
        replyButton.setTitle(nil, for: .normal)

        // Post-voting (Q&A)
        let showVoting = post.postVotingHasVotes || post.postVotingVoteCount != 0 || post.postNumber > 1 && post.replyToPostNumber == nil
        // Only surface when plugin data is present (avoid noise on normal topics).
        let votingActive = post.postVotingHasVotes || post.postVotingUserVotedDirection != nil || post.postVotingVoteCount != 0
        voteUpButton.isHidden = !votingActive
        voteDownButton.isHidden = !votingActive
        voteCountLabel.isHidden = !votingActive
        if votingActive {
            let dir = post.postVotingUserVotedDirection?.lowercased()
            voteUpButton.tintColor = dir == "up" ? accent : .secondaryLabel
            voteDownButton.tintColor = dir == "down" ? .systemOrange : .secondaryLabel
            voteCountLabel.text = "\(post.postVotingVoteCount)"
            _ = showVoting
        }

        // Boost
        boostActionButton.setImage(
            UIImage(systemName: "bolt.fill", withConfiguration: symbol),
            for: .normal
        )
        boostActionButton.tintColor = .secondaryLabel
        boostActionButton.isHidden = post.yours || !post.canBoost
        boostActionButton.isEnabled = post.canBoost
        boostActionButton.setTitle(nil, for: .normal)

        underBubbleRowHeightConstraint?.constant = Metrics.actionBarHeight
        underBubbleRowTopConstraint?.constant = 4
        underBubbleRow.isHidden = false
    }

    /// Place boost chips under the bubble, aligned to the same edge as the bubble.
    private func installBoostStrip(for post: DiscourseTopicDetail.Post, baseURL: String) {
        boostHost.subviews.forEach { $0.removeFromSuperview() }

        guard let boostStrip = BoostStripView(
            boosts: post.boosts,
            baseURL: baseURL,
            // Outside the bubble: always use normal chip contrast (not green-bubble high-contrast).
            prefersHighContrast: false
        ) else {
            boostHost.isHidden = true
            boostHostHeightConstraint?.constant = 0
            boostHostTopConstraint?.constant = 0
            return
        }

        boostStrip.onRequestDeleteBoost = { [weak self] boost in
            guard let self, let current = self.currentPost else { return }
            self.contentDelegate?.postCell(didRequestDeleteBoost: boost, forPost: current)
        }
        boostStrip.onOpenUserProfile = { [weak self] username in
            guard let self else { return }
            self.actionDelegate?.weChatChatPostCell(self, didTapAvatar: username)
        }
        boostStrip.translatesAutoresizingMaskIntoConstraints = false
        boostHost.addSubview(boostStrip)
        NSLayoutConstraint.activate([
            boostStrip.topAnchor.constraint(equalTo: boostHost.topAnchor),
            boostStrip.leadingAnchor.constraint(equalTo: boostHost.leadingAnchor),
            boostStrip.trailingAnchor.constraint(equalTo: boostHost.trailingAnchor),
            boostStrip.bottomAnchor.constraint(equalTo: boostHost.bottomAnchor),
        ])
        boostStrip.setContentHuggingPriority(.required, for: .vertical)
        boostStrip.setContentCompressionResistancePriority(.required, for: .vertical)

        boostHost.isHidden = false
        // BoostStripView intrinsic height is 34.
        boostHostHeightConstraint?.constant = 34
        boostHostTopConstraint?.constant = 4
    }

    private func applyDateSeparator(_ text: String?) {
        if let text, !text.isEmpty {
            dateChipLabel.isHidden = false
            dateChipLabel.text = "  \(text)  "
            dateChipLabel.font = TopicDetailTypography.chromeFont(.dateChip, weight: .medium)
            dateChipLabel.adjustsFontForContentSizeCategory = true
            dateChipTopConstraint?.constant = 8
            dateChipHeightConstraint?.constant = 22
            let isDark = traitCollection.userInterfaceStyle == .dark
            dateChipLabel.backgroundColor = isDark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.08)
            dateChipLabel.textColor = isDark
                ? UIColor.white.withAlphaComponent(0.75)
                : UIColor.secondaryLabel
        } else {
            dateChipLabel.isHidden = true
            dateChipLabel.text = nil
            dateChipTopConstraint?.constant = 0
            dateChipHeightConstraint?.constant = 0
        }
    }

    private func makeTelegramNameHeader(
        displayName: String,
        post: DiscourseTopicDetail.Post
    ) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 6
        row.tag = 88001

        let name = UILabel()
        name.font = TopicDetailTypography.chromeFont(.authorName, weight: .semibold)
        name.adjustsFontForContentSizeCategory = true
        name.textColor = chatStyle.nameColor(for: post.username)
        name.text = displayName
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(name)

        if post.admin || post.moderator || post.groupModerator {
            let badge = UILabel()
            badge.font = TopicDetailTypography.chromeFont(.adminBadge, weight: .semibold)
            badge.adjustsFontForContentSizeCategory = true
            badge.textColor = .white
            badge.backgroundColor = UIColor(red: 0.35, green: 0.78, blue: 0.45, alpha: 1)
            badge.text = "  " + String(localized: "telegram_chat.admin_badge", defaultValue: "管理员") + "  "
            badge.layer.cornerRadius = 8
            badge.layer.cornerCurve = .continuous
            badge.clipsToBounds = true
            badge.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(badge)
        }

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }

    private func makeTelegramReplyQuote(
        replyUser: DiscourseTopicDetail.ReplyToUser,
        post: DiscourseTopicDetail.Post,
        isDark: Bool
    ) -> UIView {
        let color = chatStyle.nameColor(for: replyUser.username)
        let container = UIView()
        container.tag = 88002
        container.backgroundColor = isDark
            ? color.withAlphaComponent(0.14)
            : color.withAlphaComponent(0.10)
        container.layer.cornerRadius = 6
        container.layer.cornerCurve = .continuous
        container.clipsToBounds = true

        let bar = UIView()
        bar.backgroundColor = color
        bar.translatesAutoresizingMaskIntoConstraints = false

        let name = UILabel()
        name.font = TopicDetailTypography.chromeFont(.authorMeta, weight: .semibold)
        name.adjustsFontForContentSizeCategory = true
        name.textColor = color
        name.text = replyUser.username
        name.translatesAutoresizingMaskIntoConstraints = false

        let preview = UILabel()
        preview.font = TopicDetailTypography.chromeFont(.replyChip, weight: .regular)
        preview.adjustsFontForContentSizeCategory = true
        preview.textColor = isDark ? UIColor.white.withAlphaComponent(0.7) : .secondaryLabel
        preview.numberOfLines = 2
        // Prefer a short plain preview of this post's reply target if available via cooked quote;
        // fall back to floor marker.
        if let n = post.replyToPostNumber {
            preview.text = String(
                format: String(localized: "telegram_chat.reply_floor_fmt", defaultValue: "回复 #%d"),
                n
            )
        } else {
            preview.text = String(localized: "telegram_chat.reply", defaultValue: "回复")
        }
        preview.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(bar)
        container.addSubview(name)
        container.addSubview(preview)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 3),

            name.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            name.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8),
            name.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            preview.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1),
            preview.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
        ])
        return container
    }

    /// Telegram / chat clock under the bubble: always `HH:mm`.
    private func formatBubbleTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: isoString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: isoString)
        }
        guard let date else { return "" }
        let tf = DateFormatter()
        tf.locale = .current
        tf.dateFormat = "HH:mm"
        return tf.string(from: date)
    }

    private func makeFallbackLabel(
        for post: DiscourseTopicDetail.Post,
        config: NativeRenderConfig,
        baseURL: String
    ) -> UILabel? {
        let plain = CookedTextExporter.plainText(fromHTML: post.cooked, baseURL: baseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        let fallback = UILabel()
        fallback.numberOfLines = 0
        fallback.font = config.baseFont
        fallback.textColor = config.baseColor
        fallback.text = plain
        fallback.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return fallback
    }

    private func applyAlignment(isMine: Bool) {
        avatarLeadingConstraint?.isActive = !isMine
        avatarTrailingConstraint?.isActive = isMine
        bubbleLeadingConstraint?.isActive = !isMine
        bubbleTrailingConstraint?.isActive = isMine
        nameLeadingConstraint?.isActive = !isMine
        nameTrailingConstraint?.isActive = isMine
        // Action/time row always spans the bubble width.
        underBubbleLeadingConstraint?.isActive = true
        underBubbleTrailingConstraint?.isActive = true
    }

    private func applyChatChrome() {
        let style = chatStyle
        // Telegram hides own avatar (group-chat style); keep a zero-size anchor for trailing pin.
        let showAvatar = !isMine || style.showsOutgoingAvatar
        let avatarSize = showAvatar ? style.avatarSize : 0
        avatarWidthConstraint?.constant = avatarSize
        avatarHeightConstraint?.constant = avatarSize
        avatarImageView.isHidden = !showAvatar
        avatarImageView.isUserInteractionEnabled = showAvatar
        avatarImageView.layer.cornerRadius = style.avatarCornerRadius
        avatarImageView.layer.cornerCurve = style == .telegram ? .circular : .continuous
        bubbleView.layer.cornerRadius = style.bubbleCornerRadius
        bubbleView.layer.cornerCurve = .continuous

        // Telegram avatars sit on the bottom corner of the bubble; WeChat keeps top align.
        if style == .telegram {
            avatarTopConstraint?.isActive = false
            avatarBottomConstraint?.isActive = showAvatar
            bubbleView.layer.shadowColor = UIColor.black.cgColor
            bubbleView.layer.shadowOpacity = 0.08
            bubbleView.layer.shadowRadius = 2
            bubbleView.layer.shadowOffset = CGSize(width: 0, height: 1)
            bubbleView.layer.masksToBounds = false
            bubbleView.clipsToBounds = false
            contentStack.clipsToBounds = true
            contentStack.layer.cornerRadius = max(style.bubbleCornerRadius - 6, 8)
        } else {
            avatarBottomConstraint?.isActive = false
            avatarTopConstraint?.isActive = true
            bubbleView.layer.shadowOpacity = 0
            bubbleView.clipsToBounds = true
        }
    }

    private func pinArrangedSubview(_ view: UIView, contentWidth: CGFloat, isTextMedia: Bool = true) {
        if isTextMedia {
            wireTextViews(in: view, contentWidth: contentWidth)
        }
        // Fill bubble width, but never stretch vertically into empty gaps.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.addArrangedSubview(view)
    }

    /// Bare `UIView()` placeholders from failed block renderers have no intrinsic size and
    /// will soak up free height inside a vertical `.fill` stack.
    private func isEmptySpacerView(_ view: UIView) -> Bool {
        if view is LinkTextView || view is UITextView || view is UIImageView || view is UILabel {
            return false
        }
        if view is TappableImageContainer || view is BoostStripView || view is OneboxCardView
            || view is FallbackBlockView || view is BadgeCardView || view is VideoCardView {
            return false
        }
        // Plain UIView with no meaningful subviews / no intrinsic height.
        if type(of: view) == UIView.self, view.subviews.isEmpty {
            return true
        }
        return false
    }

    private func wireTextViews(in root: UIView, contentWidth: CGFloat) {
        if let textView = root as? LinkTextView {
            textView.isEditable = false
            textView.isScrollEnabled = false
            textView.backgroundColor = .clear
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.delegate = self
            textView.preferredMeasurementWidth = contentWidth
            textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            // Critical for chat bubbles: UITextView default vertical hugging is low (250),
            // so a slightly-too-tall row turns into a hollow middle under the last paragraph.
            textView.setContentHuggingPriority(.required, for: .vertical)
            textView.setContentCompressionResistancePriority(.required, for: .vertical)
            textView.configureSpoilerIfNeeded()
            loadInlineImages(in: textView)
            return
        }
        if let textView = root as? UITextView {
            textView.isScrollEnabled = false
            textView.setContentHuggingPriority(.required, for: .vertical)
            textView.setContentCompressionResistancePriority(.required, for: .vertical)
            textView.delegate = self
            loadInlineImages(in: textView)
            return
        }
        for child in root.subviews {
            wireTextViews(in: child, contentWidth: contentWidth)
        }
    }

    /// Same contract as `PostNativeCell.loadInlineImages` — without this, emoji / inline
    /// images stay as empty NSTextAttachment placeholders inside chat bubbles.
    private func loadInlineImages(in textView: UITextView) {
        CookedInlineImageLoader.loadImages(
            in: textView,
            cloudflareBaseURL: imageBaseURL
        ) { [weak self, weak textView] in
            textView?.invalidateIntrinsicContentSize()
            self?.requestHeightReconciliation()
        }
    }

    @objc private func handleAvatarTap() {
        guard let username = currentPost?.username else { return }
        actionDelegate?.weChatChatPostCell(self, didTapAvatar: username)
    }

    @objc private func handleLikeTapped() {
        guard let post = currentPost, !post.yours else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        actionDelegate?.weChatChatPostCell(self, didRequestLike: post)
    }

    @objc private func handleBookmarkTapped() {
        guard let post = currentPost else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        actionDelegate?.weChatChatPostCell(self, didRequestBookmark: post)
    }

    @objc private func handleVoteUpTapped() {
        guard let post = currentPost else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let dir = post.postVotingUserVotedDirection?.lowercased() == "up" ? "none" : "up"
        contentDelegate?.postCell(didCastPostVotingVote: dir, forPost: post)
    }

    @objc private func handleVoteDownTapped() {
        guard let post = currentPost else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let dir = post.postVotingUserVotedDirection?.lowercased() == "down" ? "none" : "down"
        contentDelegate?.postCell(didCastPostVotingVote: dir, forPost: post)
    }

    @objc private func handleReplyTapped() {
        guard let post = currentPost else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        actionDelegate?.weChatChatPostCell(self, didRequestReply: post)
    }

    @objc private func handleBoostTapped() {
        guard let post = currentPost, !post.yours, post.canBoost else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        actionDelegate?.weChatChatPostCell(self, didRequestBoost: post)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let post = currentPost else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        presentActionSheet(actions: makeActionMenu(for: post))
    }

    private struct MenuAction {
        let title: String
        let handler: () -> Void
        let destructive: Bool
        let disabled: Bool
    }

    private func makeActionMenu(for post: DiscourseTopicDetail.Post) -> [MenuAction] {
        var actions: [MenuAction] = []

        if !post.yours {
            let liked = post.currentUserReaction != nil
            actions.append(
                MenuAction(
                    title: liked
                        ? String(localized: "wechat_chat.unlike", defaultValue: "取消点赞")
                        : String(localized: "wechat_chat.like", defaultValue: "点赞"),
                    handler: { [weak self] in
                        guard let self else { return }
                        self.actionDelegate?.weChatChatPostCell(self, didRequestLike: post)
                    },
                    destructive: false,
                    disabled: false
                )
            )
        }

        actions.append(
            MenuAction(
                title: String(localized: "wechat_chat.reply", defaultValue: "回复"),
                handler: { [weak self] in
                    guard let self else { return }
                    self.actionDelegate?.weChatChatPostCell(self, didRequestReply: post)
                },
                destructive: false,
                disabled: false
            )
        )

        actions.append(
            MenuAction(
                title: post.bookmarked
                    ? String(localized: "wechat_chat.unbookmark", defaultValue: "取消收藏")
                    : String(localized: "wechat_chat.bookmark", defaultValue: "收藏"),
                handler: { [weak self] in
                    guard let self else { return }
                    self.actionDelegate?.weChatChatPostCell(self, didRequestBookmark: post)
                },
                destructive: false,
                disabled: false
            )
        )

        if !post.yours {
            actions.append(
                MenuAction(
                    title: String(localized: "post.boost", defaultValue: "Boost"),
                    handler: { [weak self] in
                        guard let self else { return }
                        self.actionDelegate?.weChatChatPostCell(self, didRequestBoost: post)
                    },
                    destructive: false,
                    disabled: !post.canBoost
                )
            )
        }

        return actions
    }

    private func presentActionSheet(actions: [MenuAction]) {
        guard let host = nearestViewController() else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        for action in actions where !action.disabled {
            sheet.addAction(
                UIAlertAction(
                    title: action.title,
                    style: action.destructive ? .destructive : .default,
                    handler: { _ in action.handler() }
                )
            )
        }
        sheet.addAction(
            UIAlertAction(
                title: String(localized: "common.cancel", defaultValue: "取消"),
                style: .cancel
            )
        )
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = bubbleView
            pop.sourceRect = bubbleView.bounds
        }
        host.present(sheet, animated: true)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let vc = current as? UIViewController { return vc }
            responder = current.next
        }
        return nil
    }

    override func systemLayoutSizeFitting(
        _ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority
    ) -> CGSize {
        // Measure against the real row width so LinkTextView wraps once, not at a stale width.
        let width = targetSize.width > 1 ? targetSize.width : bounds.width
        if width > 1 {
            bounds.size.width = width
            contentView.bounds.size.width = width
        }
        contentView.setNeedsLayout()
        contentView.layoutIfNeeded()
        let fitted = contentView.systemLayoutSizeFitting(
            CGSize(width: width > 1 ? width : UIView.layoutFittingExpandedSize.width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return CGSize(width: targetSize.width, height: ceil(fitted.height))
    }

    func requestHeightReconciliation() {
        heightReconcileGeneration += 1
        let generation = heightReconcileGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.heightReconcileGeneration == generation, self.window != nil else { return }
            self.reconcileTableRowHeightIfNeeded()
        }
        setNeedsLayout()
    }

    private func reconcileTableRowHeightIfNeeded() {
        guard bounds.width > 1 else { return }
        contentView.layoutIfNeeded()
        let fitted = contentView.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard abs(fitted - bounds.height) > 2 else {
            lastReconciledHeight = bounds.height
            return
        }
        if abs(fitted - lastReconciledHeight) < 1 { return }
        lastReconciledHeight = fitted
        var view: UIView? = superview
        while let current = view {
            if let tableView = current as? UITableView {
                tableView.dexo_invalidateSelfSizingRows()
                return
            }
            view = current.superview
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentPost = nil
        imageBaseURL = nil
        heightReconcileGeneration += 1
        lastReconciledHeight = 0
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        boostHost.subviews.forEach { $0.removeFromSuperview() }
        boostHost.isHidden = true
        boostHostHeightConstraint?.constant = 0
        boostHostTopConstraint?.constant = 0
        nameLabel.text = nil
        timeLabel.text = nil
        likeButton.setTitle(nil, for: .normal)
        applyDateSeparator(nil)
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
    }
}

extension WeChatChatPostCell: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        contentDelegate?.postCell(didTapLinkURL: URL)
        return false
    }
}
