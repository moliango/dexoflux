import UIKit

/// WeChat-style chat input: type text, keyboard Send/换行 sends; plus opens full composer.
final class WeChatChatInputBar: UIView, UITextViewDelegate {
    var onSend: ((String) -> Void)?
    var onPlus: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var onBeginEditing: (() -> Void)?

    private let minTextHeight: CGFloat = 36
    private let maxTextHeight: CGFloat = 100

    private let replyBanner = UIView()
    private let replyLabel = UILabel()
    private let replyCloseButton = UIButton(type: .system)
    private let textBackground = UIView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let plusButton = UIButton(type: .system)

    private var textHeightConstraint: NSLayoutConstraint?
    private var replyBannerHeightConstraint: NSLayoutConstraint?
    private var isSending = false

    private(set) var replyToPost: DiscourseTopicDetail.Post?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
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
            plusButton.isEnabled = newValue
        }
    }

    func focus() {
        textView.becomeFirstResponder()
    }

    func resign() {
        textView.resignFirstResponder()
    }

    func setReplyTarget(_ post: DiscourseTopicDetail.Post?) {
        replyToPost = post
        if let post {
            let name = (post.name?.isEmpty == false ? post.name! : post.username)
            let preview = CookedContentPipeline.plainTextPreview(fromCooked: post.cooked)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = preview.count > 36 ? String(preview.prefix(36)) + "…" : preview
            replyLabel.text = String(
                format: String(localized: "wechat_chat.reply_to_fmt", defaultValue: "回复 %@：%@"),
                name,
                clipped.isEmpty ? "#\(post.postNumber)" : clipped
            )
            replyBanner.isHidden = false
            replyBannerHeightConstraint?.constant = 32
        } else {
            replyLabel.text = nil
            replyBanner.isHidden = true
            replyBannerHeightConstraint?.constant = 0
        }
        onHeightChange?()
    }

    func clearAfterSend() {
        isSending = false
        textView.text = ""
        textViewDidChange(textView)
        setReplyTarget(nil)
        isComposerEnabled = true
    }

    func setSending(_ sending: Bool) {
        isSending = sending
        isComposerEnabled = !sending
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.11, alpha: 1)
                : UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1)
        }
        translatesAutoresizingMaskIntoConstraints = false

        let topLine = UIView()
        topLine.translatesAutoresizingMaskIntoConstraints = false
        topLine.backgroundColor = UIColor.separator.withAlphaComponent(0.45)
        addSubview(topLine)

        replyBanner.translatesAutoresizingMaskIntoConstraints = false
        replyBanner.backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.55)
        replyBanner.isHidden = true
        addSubview(replyBanner)

        replyLabel.translatesAutoresizingMaskIntoConstraints = false
        replyLabel.font = .systemFont(ofSize: 12)
        replyLabel.textColor = .secondaryLabel
        replyLabel.numberOfLines = 1
        replyLabel.lineBreakMode = .byTruncatingTail
        replyBanner.addSubview(replyLabel)

        replyCloseButton.translatesAutoresizingMaskIntoConstraints = false
        replyCloseButton.setImage(
            UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)),
            for: .normal
        )
        replyCloseButton.tintColor = .tertiaryLabel
        replyCloseButton.addAction(UIAction { [weak self] _ in
            self?.setReplyTarget(nil)
        }, for: .touchUpInside)
        replyBanner.addSubview(replyCloseButton)

        textBackground.translatesAutoresizingMaskIntoConstraints = false
        textBackground.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.18, alpha: 1)
                : UIColor.white
        }
        textBackground.layer.cornerRadius = 6
        textBackground.layer.cornerCurve = .continuous
        addSubview(textBackground)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.tintColor = UIColor(red: 0.03, green: 0.76, blue: 0.38, alpha: 1)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = self
        // Keyboard shows 发送 — tap it (or physical Return) to send, WeChat-like.
        textView.returnKeyType = .send
        textView.enablesReturnKeyAutomatically = true
        textBackground.addSubview(textView)

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.text = String(localized: "wechat_chat.input_placeholder", defaultValue: "回复…")
        placeholderLabel.font = .systemFont(ofSize: 16)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.isUserInteractionEnabled = false
        textBackground.addSubview(placeholderLabel)

        let plusConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        plusButton.setImage(UIImage(systemName: "plus.circle", withConfiguration: plusConfig), for: .normal)
        plusButton.tintColor = .secondaryLabel
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        plusButton.accessibilityLabel = String(localized: "wechat_chat.more", defaultValue: "更多")
        plusButton.addAction(UIAction { [weak self] _ in
            self?.onPlus?()
        }, for: .touchUpInside)
        addSubview(plusButton)

        let textHeight = textView.heightAnchor.constraint(equalToConstant: minTextHeight)
        textHeightConstraint = textHeight
        let bannerHeight = replyBanner.heightAnchor.constraint(equalToConstant: 0)
        replyBannerHeightConstraint = bannerHeight

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

            textBackground.topAnchor.constraint(equalTo: replyBanner.bottomAnchor, constant: 8),
            textBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textBackground.trailingAnchor.constraint(equalTo: plusButton.leadingAnchor, constant: -8),
            textBackground.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),

            textView.topAnchor.constraint(equalTo: textBackground.topAnchor),
            textView.leadingAnchor.constraint(equalTo: textBackground.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textBackground.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: textBackground.bottomAnchor),
            textHeight,

            placeholderLabel.leadingAnchor.constraint(equalTo: textBackground.leadingAnchor, constant: 10),
            placeholderLabel.centerYAnchor.constraint(equalTo: textBackground.centerYAnchor),

            plusButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            plusButton.bottomAnchor.constraint(equalTo: textBackground.bottomAnchor),
            plusButton.widthAnchor.constraint(equalToConstant: 36),
            plusButton.heightAnchor.constraint(equalToConstant: 36),
        ])
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

        let width = max(textView.bounds.width, UIScreen.main.bounds.width - 70)
        let size = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let target = min(max(size.height, minTextHeight), maxTextHeight)
        textView.isScrollEnabled = size.height > maxTextHeight
        if textHeightConstraint?.constant != target {
            textHeightConstraint?.constant = target
            onHeightChange?()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Return / 发送 key → send message (do not insert newline).
        if text == "\n" {
            sendTapped()
            return false
        }
        return true
    }
}
