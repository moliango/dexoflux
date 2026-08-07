import CookedHTML
import SDWebImage
import UIKit

/// WeChat-style chat bubble row for Topic Detail when `ThemeStyle.weChat` is active.
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
        static let avatarSize: CGFloat = 40
        static let horizontalInset: CGFloat = 12
        static let avatarBubbleGap: CGFloat = 8
        /// Keep chat bubbles tight — large padding + fill-distribution made a hollow middle.
        static let bubblePadding: CGFloat = 10
        static let contentSpacing: CGFloat = 4
        /// Max fraction of row width the bubble may occupy (avatar + gaps reserved separately).
        static let maxBubbleFraction: CGFloat = 0.88
    }

    weak var actionDelegate: WeChatChatPostCellDelegate?
    weak var contentDelegate: PostCellDelegate?

    private var currentPost: DiscourseTopicDetail.Post?
    private var imageBaseURL: String?
    private var isMine = false
    private var heightReconcileGeneration = 0
    private var lastReconciledHeight: CGFloat = 0

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

    private let metaLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let reactionBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    private var avatarLeadingConstraint: NSLayoutConstraint?
    private var avatarTrailingConstraint: NSLayoutConstraint?
    private var bubbleLeadingConstraint: NSLayoutConstraint?
    private var bubbleTrailingConstraint: NSLayoutConstraint?
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private var nameLeadingConstraint: NSLayoutConstraint?
    private var nameTrailingConstraint: NSLayoutConstraint?
    private var metaLeadingConstraint: NSLayoutConstraint?
    private var metaTrailingConstraint: NSLayoutConstraint?
    private var nameHeightConstraint: NSLayoutConstraint?
    private var reactionLeadingConstraint: NSLayoutConstraint?
    private var reactionTrailingConstraint: NSLayoutConstraint?

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
        contentView.addSubview(avatarImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(bubbleView)
        contentView.addSubview(metaLabel)
        contentView.addSubview(reactionBadge)
        bubbleView.addSubview(contentStack)

        let avatarLead = avatarImageView.leadingAnchor.constraint(
            equalTo: contentView.leadingAnchor,
            constant: Metrics.horizontalInset
        )
        let avatarTrail = avatarImageView.trailingAnchor.constraint(
            equalTo: contentView.trailingAnchor,
            constant: -Metrics.horizontalInset
        )
        // Bubble is positioned from avatar; width is set explicitly in configure(_:).
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
        let metaLead = metaLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor)
        let metaTrail = metaLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor)
        let reactionLead = reactionBadge.leadingAnchor.constraint(equalTo: metaLabel.trailingAnchor, constant: 8)
        let reactionTrail = reactionBadge.trailingAnchor.constraint(equalTo: metaLabel.leadingAnchor, constant: -8)

        avatarLeadingConstraint = avatarLead
        avatarTrailingConstraint = avatarTrail
        bubbleLeadingConstraint = bubbleLead
        bubbleTrailingConstraint = bubbleTrail
        bubbleWidthConstraint = bubbleWidth
        nameLeadingConstraint = nameLead
        nameTrailingConstraint = nameTrail
        metaLeadingConstraint = metaLead
        metaTrailingConstraint = metaTrail
        reactionLeadingConstraint = reactionLead
        reactionTrailingConstraint = reactionTrail

        let nameHeight = nameLabel.heightAnchor.constraint(equalToConstant: 16)
        nameHeightConstraint = nameHeight

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            avatarImageView.widthAnchor.constraint(equalToConstant: Metrics.avatarSize),
            avatarImageView.heightAnchor.constraint(equalToConstant: Metrics.avatarSize),

            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            nameHeight,

            bubbleView.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            bubbleWidth,

            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: Metrics.bubblePadding),
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: Metrics.bubblePadding),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -Metrics.bubblePadding),
            contentStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -Metrics.bubblePadding),
            // Give the stack a real width target equal to bubble inner width.
            contentStack.widthAnchor.constraint(
                equalTo: bubbleView.widthAnchor,
                constant: -Metrics.bubblePadding * 2
            ),

            metaLabel.topAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: 4),
            metaLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            reactionBadge.centerYAnchor.constraint(equalTo: metaLabel.centerYAnchor),
        ])

        // Default: other (left)
        avatarLead.isActive = true
        bubbleLead.isActive = true
        nameLead.isActive = true
        metaLead.isActive = true
        reactionLead.isActive = true

        // Horizontal: bubble may grow with content width constraint.
        bubbleView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bubbleView.setContentCompressionResistancePriority(.required, for: .horizontal)
        contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        // Vertical: never let the bubble/stack absorb spare row height into empty gaps.
        bubbleView.setContentHuggingPriority(.required, for: .vertical)
        bubbleView.setContentCompressionResistancePriority(.required, for: .vertical)
        contentStack.setContentHuggingPriority(.required, for: .vertical)
        contentStack.setContentCompressionResistancePriority(.required, for: .vertical)
    }

    func configure(
        with post: DiscourseTopicDetail.Post,
        annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig,
        floorNumber: Int,
        baseURL: String,
        contentDelegate: PostCellDelegate?
    ) {
        currentPost = post
        self.contentDelegate = contentDelegate
        imageBaseURL = baseURL
        isMine = post.yours
        applyAlignment(isMine: isMine)

        // Explicit bubble width from render config — avoids zero-width ambiguous layout
        // that produced the thin empty white strips in screenshots.
        let innerWidth = max(config.contentWidth, 120)
        let bubbleWidth = innerWidth + Metrics.bubblePadding * 2
        bubbleWidthConstraint?.constant = bubbleWidth

        nameLabel.text = (post.name?.isEmpty == false ? post.name : nil) ?? post.username
        nameLabel.textAlignment = isMine ? .right : .left
        nameLabel.isHidden = isMine
        nameHeightConstraint?.constant = isMine ? 0 : 16

        let time = TopicCell.formatDate(post.createdAt)
        metaLabel.text = "#\(floorNumber) · \(time)"
        metaLabel.textAlignment = isMine ? .right : .left

        let count = post.reactionUsersCount
        if count > 0 {
            reactionBadge.isHidden = false
            let liked = post.currentUserReaction != nil
            reactionBadge.text = liked ? "♥ \(count)" : "♡ \(count)"
            reactionBadge.textColor = liked ? .systemPink : .secondaryLabel
        } else {
            reactionBadge.isHidden = true
            reactionBadge.text = nil
        }

        bubbleView.backgroundColor = isMine
            ? UIColor(red: 0.58, green: 0.91, blue: 0.45, alpha: 1)
            : UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0.18, green: 0.18, blue: 0.18, alpha: 1)
                    : UIColor.white
            }

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
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
                // Failed renderers sometimes return a bare UIView() — under `.fill` that
                // becomes a flexible vertical spacer and hollows out the bubble middle.
                if isEmptySpacerView(view) { continue }
                pinArrangedSubview(view, contentWidth: innerWidth)
            }
        }
        if let boostStrip = BoostStripView(boosts: post.boosts, baseURL: baseURL) {
            pinArrangedSubview(boostStrip, contentWidth: innerWidth, isTextMedia: false)
        }

        // If still empty after render (e.g. only whitespace cooked), force plain text.
        if contentStack.arrangedSubviews.isEmpty {
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
        metaLeadingConstraint?.isActive = !isMine
        metaTrailingConstraint?.isActive = isMine
        reactionLeadingConstraint?.isActive = !isMine
        reactionTrailingConstraint?.isActive = isMine
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
        nameLabel.text = nil
        metaLabel.text = nil
        reactionBadge.text = nil
        reactionBadge.isHidden = true
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
