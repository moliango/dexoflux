import UIKit

/// Chat input bar for WeChat / Telegram themes.
/// - WeChat: [ field …………………… plus ]
/// - Telegram: [ paperclip ][ Message field ][ mic | send ]
final class WeChatChatInputBar: UIView, UITextViewDelegate {
    var onSend: ((String) -> Void)?
    var onPlus: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var onBeginEditing: (() -> Void)?

    private let minTextHeight: CGFloat = 36
    private let maxTextHeight: CGFloat = 100

    private let topLine = UIView()
    private let replyBanner = UIView()
    private let replyLabel = UILabel()
    private let replyCloseButton = UIButton(type: .system)
    private let textBackground = UIView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let attachButton = UIButton(type: .system)
    private let micButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)

    private var textHeightConstraint: NSLayoutConstraint?
    private var replyBannerHeightConstraint: NSLayoutConstraint?

    // Layout mode constraints (activated per theme).
    private var wechatTextLeading: NSLayoutConstraint?
    private var wechatTextTrailing: NSLayoutConstraint?
    private var wechatAttachTrailing: NSLayoutConstraint?

    private var telegramAttachLeading: NSLayoutConstraint?
    private var telegramTextLeading: NSLayoutConstraint?
    private var telegramTextTrailingToMic: NSLayoutConstraint?
    private var telegramTextTrailingToSend: NSLayoutConstraint?

    private var isSending = false
    private var chatStyle: ChatTopicStyle { ChatTopicStyle.current ?? .weChat }

    private(set) var replyToPost: DiscourseTopicDetail.Post?
    /// Chat channel reply target (message id). Independent from topic post reply.
    private(set) var replyToChatMessageId: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        applyChatStyle()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyChatStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            textViewDidChange(textView)
        }
    }

    var isComposerEnabled: Bool {
        get { textView.isEditable }
        set {
            textView.isEditable = newValue
            attachButton.isEnabled = newValue
            micButton.isEnabled = newValue
            sendButton.isEnabled = newValue
        }
    }

    func focus() {
        textView.becomeFirstResponder()
    }

    func resign() {
        textView.resignFirstResponder()
    }

    func setReplyTarget(_ post: DiscourseTopicDetail.Post?) {
        replyToChatMessageId = nil
        replyToPost = post
        if let post {
            let name = (post.name?.isEmpty == false ? post.name! : post.username)
            let preview = CookedContentPipeline.plainTextPreview(fromCooked: post.cooked)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = preview.count > 36 ? String(preview.prefix(36)) + "…" : preview
            showReplyBanner(
                name: name,
                preview: clipped.isEmpty ? "#\(post.postNumber)" : clipped
            )
        } else {
            hideReplyBanner()
        }
        onHeightChange?()
    }

    /// Chat-room reply banner (message id, not topic post).
    func setChatReplyTarget(messageId: Int, name: String, preview: String) {
        replyToPost = nil
        replyToChatMessageId = messageId
        let clipped = preview.count > 36 ? String(preview.prefix(36)) + "…" : preview
        showReplyBanner(name: name, preview: clipped.isEmpty ? "#\(messageId)" : clipped)
        onHeightChange?()
        focus()
    }

    func clearReplyTarget() {
        replyToPost = nil
        replyToChatMessageId = nil
        hideReplyBanner()
        onHeightChange?()
    }

    func insertText(_ string: String) {
        guard !string.isEmpty else { return }
        textView.insertText(string)
        textViewDidChange(textView)
        focus()
    }

    private func showReplyBanner(name: String, preview: String) {
        replyLabel.text = String(
            format: String(localized: "wechat_chat.reply_to_fmt", defaultValue: "回复 %@：%@"),
            name,
            preview
        )
        replyBanner.isHidden = false
        replyBannerHeightConstraint?.constant = 32
    }

    private func hideReplyBanner() {
        replyLabel.text = nil
        replyBanner.isHidden = true
        replyBannerHeightConstraint?.constant = 0
    }

    func clearAfterSend() {
        isSending = false
        textView.text = ""
        textViewDidChange(textView)
        clearReplyTarget()
        isComposerEnabled = true
    }

    func setSending(_ sending: Bool) {
        isSending = sending
        isComposerEnabled = !sending
    }

    // MARK: - Setup

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        topLine.tag = 91001
        topLine.translatesAutoresizingMaskIntoConstraints = false
        topLine.backgroundColor = UIColor.separator.withAlphaComponent(0.45)
        addSubview(topLine)

        replyBanner.translatesAutoresizingMaskIntoConstraints = false
        replyBanner.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.55)
        replyBanner.isHidden = true
        addSubview(replyBanner)

        replyLabel.translatesAutoresizingMaskIntoConstraints = false
        replyLabel.font = TopicDetailTypography.chromeFont(.inputMeta, weight: .regular)
        replyLabel.adjustsFontForContentSizeCategory = true
        replyLabel.textColor = .secondaryLabel
        replyLabel.numberOfLines = 1
        replyLabel.lineBreakMode = .byTruncatingTail
        replyBanner.addSubview(replyLabel)

        replyCloseButton.translatesAutoresizingMaskIntoConstraints = false
        replyCloseButton.setImage(
            UIImage(
                systemName: "xmark.circle.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            ),
            for: .normal
        )
        replyCloseButton.tintColor = .tertiaryLabel
        replyCloseButton.addAction(UIAction { [weak self] _ in
            self?.clearReplyTarget()
        }, for: .touchUpInside)
        replyBanner.addSubview(replyCloseButton)

        attachButton.translatesAutoresizingMaskIntoConstraints = false
        attachButton.accessibilityLabel = String(localized: "wechat_chat.more", defaultValue: "更多")
        attachButton.addAction(UIAction { [weak self] _ in
            self?.onPlus?()
        }, for: .touchUpInside)
        addSubview(attachButton)

        textBackground.translatesAutoresizingMaskIntoConstraints = false
        textBackground.layer.cornerCurve = .continuous
        addSubview(textBackground)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = TopicDetailTypography.chromeFont(.inputBody, weight: .regular)
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.returnKeyType = .send
        textView.enablesReturnKeyAutomatically = true
        textBackground.addSubview(textView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = TopicDetailTypography.chromeFont(.inputBody, weight: .regular)
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.isUserInteractionEnabled = false
        textBackground.addSubview(placeholderLabel)

        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.accessibilityLabel = String(localized: "telegram_chat.voice", defaultValue: "语音")
        micButton.addAction(UIAction { [weak self] _ in
            self?.onPlus?()
        }, for: .touchUpInside)
        addSubview(micButton)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.isHidden = true
        sendButton.accessibilityLabel = String(localized: "action.reply", defaultValue: "发送")
        sendButton.addAction(UIAction { [weak self] _ in
            self?.sendTapped()
        }, for: .touchUpInside)
        addSubview(sendButton)

        let textHeight = textView.heightAnchor.constraint(equalToConstant: minTextHeight)
        textHeightConstraint = textHeight
        let bannerHeight = replyBanner.heightAnchor.constraint(equalToConstant: 0)
        replyBannerHeightConstraint = bannerHeight

        // WeChat layout edges
        wechatTextLeading = textBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        wechatTextTrailing = textBackground.trailingAnchor.constraint(equalTo: attachButton.leadingAnchor, constant: -8)
        wechatAttachTrailing = attachButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)

        // Telegram layout edges
        telegramAttachLeading = attachButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        telegramTextLeading = textBackground.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 4)
        telegramTextTrailingToMic = textBackground.trailingAnchor.constraint(equalTo: micButton.leadingAnchor, constant: -4)
        telegramTextTrailingToSend = textBackground.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -4)

        NSLayoutConstraint.activate([
            topLine.topAnchor.constraint(equalTo: topAnchor),
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            replyBanner.topAnchor.constraint(equalTo: topLine.bottomAnchor),
            replyBanner.leadingAnchor.constraint(equalTo: leadingAnchor),
            replyBanner.trailingAnchor.constraint(equalTo: trailingAnchor),
            bannerHeight,

            replyLabel.leadingAnchor.constraint(equalTo: replyBanner.leadingAnchor, constant: 14),
            replyLabel.centerYAnchor.constraint(equalTo: replyBanner.centerYAnchor),
            replyLabel.trailingAnchor.constraint(equalTo: replyCloseButton.leadingAnchor, constant: -8),

            replyCloseButton.trailingAnchor.constraint(equalTo: replyBanner.trailingAnchor, constant: -10),
            replyCloseButton.centerYAnchor.constraint(equalTo: replyBanner.centerYAnchor),
            replyCloseButton.widthAnchor.constraint(equalToConstant: 28),
            replyCloseButton.heightAnchor.constraint(equalToConstant: 28),

            attachButton.bottomAnchor.constraint(equalTo: textBackground.bottomAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 36),
            attachButton.heightAnchor.constraint(equalToConstant: 36),

            textBackground.topAnchor.constraint(equalTo: replyBanner.bottomAnchor, constant: 6),
            textBackground.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),

            textView.topAnchor.constraint(equalTo: textBackground.topAnchor),
            textView.leadingAnchor.constraint(equalTo: textBackground.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textBackground.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: textBackground.bottomAnchor),
            textHeight,

            placeholderLabel.leadingAnchor.constraint(equalTo: textBackground.leadingAnchor, constant: 12),
            placeholderLabel.centerYAnchor.constraint(equalTo: textBackground.centerYAnchor),

            micButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            micButton.bottomAnchor.constraint(equalTo: textBackground.bottomAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 36),
            micButton.heightAnchor.constraint(equalToConstant: 36),

            sendButton.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            sendButton.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func applyChatStyle() {
        let style = chatStyle
        backgroundColor = style.inputBarBackgroundColor
        textBackground.backgroundColor = style.inputFieldBackgroundColor
        textBackground.layer.cornerRadius = style.inputFieldCornerRadius
        textBackground.layer.shadowOpacity = 0
        textBackground.layer.borderWidth = 0

        textView.tintColor = style.accentColor
        textView.font = TopicDetailTypography.chromeFont(.inputBody, weight: .regular)
        placeholderLabel.font = TopicDetailTypography.chromeFont(.inputBody, weight: .regular)
        replyLabel.font = TopicDetailTypography.chromeFont(.inputMeta, weight: .regular)
        placeholderLabel.text = style.inputPlaceholder

        let iconConfig = UIImage.SymbolConfiguration(pointSize: style == .telegram ? 20 : 22, weight: .regular)
        let sendConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        sendButton.setImage(
            UIImage(systemName: style.sendActionSystemName, withConfiguration: sendConfig),
            for: .normal
        )
        sendButton.tintColor = style.accentColor

        // Reset mode-specific constraints.
        wechatTextLeading?.isActive = false
        wechatTextTrailing?.isActive = false
        wechatAttachTrailing?.isActive = false
        telegramAttachLeading?.isActive = false
        telegramTextLeading?.isActive = false
        telegramTextTrailingToMic?.isActive = false
        telegramTextTrailingToSend?.isActive = false

        if style == .telegram {
            topLine.isHidden = true
            // Input bar sits on the same blue-gray canvas as the chat (not a white strip).
            backgroundColor = style.chatBackgroundColor
            attachButton.setImage(
                UIImage(systemName: style.leadingActionSystemName, withConfiguration: iconConfig),
                for: .normal
            )
            attachButton.tintColor = .secondaryLabel
            micButton.setImage(
                UIImage(systemName: "mic", withConfiguration: iconConfig),
                for: .normal
            )
            micButton.tintColor = .secondaryLabel
            micButton.isHidden = false

            telegramAttachLeading?.isActive = true
            telegramTextLeading?.isActive = true
        } else {
            topLine.isHidden = false
            attachButton.setImage(
                UIImage(systemName: style.trailingActionSystemName, withConfiguration: iconConfig),
                for: .normal
            )
            attachButton.tintColor = .secondaryLabel
            micButton.isHidden = true
            sendButton.isHidden = true

            wechatTextLeading?.isActive = true
            wechatTextTrailing?.isActive = true
            wechatAttachTrailing?.isActive = true
        }

        updateTrailingButtons()
    }

    private func updateTrailingButtons() {
        let hasText = !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard chatStyle == .telegram else { return }

        telegramTextTrailingToMic?.isActive = false
        telegramTextTrailingToSend?.isActive = false

        if hasText {
            micButton.isHidden = true
            sendButton.isHidden = false
            telegramTextTrailingToSend?.isActive = true
        } else {
            micButton.isHidden = false
            sendButton.isHidden = true
            telegramTextTrailingToMic?.isActive = true
        }
    }

    private func sendTapped() {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isSending else { return }
        onSend?(raw)
    }

    // MARK: - UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        onBeginEditing?()
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
        updateTrailingButtons()

        let width = max(textView.bounds.width, UIScreen.main.bounds.width - 90)
        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let target = min(max(size.height, minTextHeight), maxTextHeight)
        textView.isScrollEnabled = size.height > maxTextHeight
        if textHeightConstraint?.constant != target {
            textHeightConstraint?.constant = target
            onHeightChange?()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            sendTapped()
            return false
        }
        return true
    }
}
