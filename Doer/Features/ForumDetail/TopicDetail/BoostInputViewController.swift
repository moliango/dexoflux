import PhotosUI
import UIKit
import UniformTypeIdentifiers

enum BoostInputResult {
    case boost(String)
    case reply(String)
}

enum BoostInputText {
    static let emojiShortcodeRegex = try! NSRegularExpression(pattern: ":[\\w\\-+]+:")

    static func rawText(from attributed: NSAttributedString) -> String {
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            if let attachment = attributes[.attachment] as? EmojiTextAttachment,
               let shortcode = attachment.shortcode {
                result += shortcode
                return
            }
            let text = attributed.attributedSubstring(from: range).string
            result += text.replacingOccurrences(of: "\u{fffc}", with: "")
        }
        return result
    }

    static func visibleLength(of raw: String) -> Int {
        let nsText = raw as NSString
        let matches = emojiShortcodeRegex.matches(in: raw, range: NSRange(location: 0, length: nsText.length))
        let shortcodeSavings = matches.reduce(0) { $0 + max($1.range.length - 1, 0) }
        return max(nsText.length - shortcodeSavings, 0)
    }
}

enum ReplyComposerSubmissionMode: Equatable {
    case reply
    case edit(postId: Int)
}

final class BoostInputViewController: UIViewController {
    private static let maxVisibleLength = 16

    private let api: DiscourseAPI
    var onSubmit: ((BoostInputResult) -> Void)?

    private var isEmojiPickerVisible = true
    private var hasLoadedForumEmojis = false
    private var isApplyingAttributedText = false

    private let grabberView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiaryLabel.withAlphaComponent(0.35)
        view.layer.cornerRadius = 2
        return view
    }()

    private let emojiToggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .secondaryLabel
        button.setImage(UIImage(systemName: "keyboard"), for: .normal)
        return button
    }()

    private let textContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var textView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textColor = .label
        view.returnKeyType = .send
        view.delegate = self
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.typingAttributes = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ]
        return view
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "post.boost.placeholder")
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .placeholderText
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let countLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .tertiaryLabel
        label.textAlignment = .right
        return label
    }()

    private let sendButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .systemBlue
        button.isEnabled = false
        return button
    }()

    private lazy var emojiPickerView: EmojiPickerView = {
        let picker = EmojiPickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onEmojiSelected = { [weak self] emoji in
            self?.insertEmoji(emoji)
        }
        return picker
    }()

    private var emojiHeightConstraint: NSLayoutConstraint?

    init(api: DiscourseAPI) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let inputRow = UIStackView(arrangedSubviews: [emojiToggleButton, textContainer, sendButton])
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputRow.axis = .horizontal
        inputRow.alignment = .center
        inputRow.spacing = 8

        textContainer.addSubview(textView)
        textContainer.addSubview(placeholderLabel)
        textContainer.addSubview(countLabel)
        view.addSubview(grabberView)
        view.addSubview(inputRow)
        view.addSubview(emojiPickerView)

        let emojiHeight = emojiPickerView.heightAnchor.constraint(equalToConstant: 280)
        emojiHeightConstraint = emojiHeight

        NSLayoutConstraint.activate([
            grabberView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            grabberView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 36),
            grabberView.heightAnchor.constraint(equalToConstant: 4),

            inputRow.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 14),
            inputRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            inputRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            emojiToggleButton.widthAnchor.constraint(equalToConstant: 38),
            emojiToggleButton.heightAnchor.constraint(equalToConstant: 38),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40),
            textContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),

            textView.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor, constant: 14),
            textView.topAnchor.constraint(equalTo: textContainer.topAnchor, constant: 7),
            textView.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor, constant: -7),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: countLabel.leadingAnchor, constant: -4),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: textView.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: -12),
            countLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: 46),

            emojiPickerView.topAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: 8),
            emojiPickerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emojiPickerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emojiPickerView.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor),
            emojiHeight,
        ])

        emojiToggleButton.addTarget(self, action: #selector(toggleEmojiPicker), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        textChanged()
        loadForumEmojisIfNeeded()
    }

    private var composerTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: textView.font ?? UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ]
    }

    private var attributedInput: NSAttributedString {
        textView.attributedText ?? NSAttributedString()
    }

    private var rawSourceText: String {
        BoostInputText.rawText(from: attributedInput)
    }

    private var rawText: String {
        rawSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleLength: Int {
        BoostInputText.visibleLength(of: rawSourceText)
    }

    private var isReplyIntent: Bool {
        visibleLength > Self.maxVisibleLength
    }

    @objc private func textChanged() {
        placeholderLabel.isHidden = !rawSourceText.isEmpty
        countLabel.text = "\(visibleLength)/\(Self.maxVisibleLength)"
        countLabel.textColor = isReplyIntent ? .systemRed : .tertiaryLabel
        sendButton.isEnabled = !rawText.isEmpty
        let symbolName = isReplyIntent ? "arrowshape.turn.up.left.fill" : "paperplane.fill"
        sendButton.setImage(UIImage(systemName: symbolName), for: .normal)
        sendButton.tintColor = rawText.isEmpty ? .tertiaryLabel : .systemBlue
    }

    @objc private func toggleEmojiPicker() {
        isEmojiPickerVisible.toggle()
        emojiHeightConstraint?.constant = isEmojiPickerVisible ? 280 : 0
        emojiPickerView.isHidden = !isEmojiPickerVisible
        emojiToggleButton.setImage(UIImage(systemName: isEmojiPickerVisible ? "keyboard" : "face.smiling"), for: .normal)
        if isEmojiPickerVisible {
            textView.resignFirstResponder()
            loadForumEmojisIfNeeded()
        } else {
            textView.becomeFirstResponder()
        }
        UIView.animate(withDuration: 0.18) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func submitTapped() {
        submit()
    }

    private func submit() {
        let raw = rawText
        guard !raw.isEmpty else { return }
        let result: BoostInputResult = isReplyIntent ? .reply(raw) : .boost(raw)
        dismiss(animated: true) { [onSubmit] in
            onSubmit?(result)
        }
    }

    private func insertEmoji(_ emoji: String) {
        replaceDisplayRange(textView.selectedRange, withRawText: emoji)
    }

    private func restylePreservingSelection() {
        guard !isApplyingAttributedText, textView.markedTextRange == nil else { return }
        let attributed = attributedInput
        let selection = textView.selectedRange
        let prefixLength = min(max(selection.location, 0), attributed.length)
        let raw = BoostInputText.rawText(from: attributed)
        let rawPrefix = BoostInputText.rawText(
            from: attributed.attributedSubstring(from: NSRange(location: 0, length: prefixLength))
        )
        let styled = makeDisplayString(raw)
        let caret = makeDisplayString(rawPrefix).length
        applyAttributedText(styled, selectedRange: NSRange(location: min(caret, styled.length), length: 0))
    }

    private func replaceDisplayRange(_ range: NSRange, withRawText raw: String) {
        let current = attributedInput
        let validRange = clampedRange(range, length: current.length)
        let prefix = BoostInputText.rawText(
            from: current.attributedSubstring(from: NSRange(location: 0, length: validRange.location))
        )
        let suffixStart = validRange.location + validRange.length
        let suffix = BoostInputText.rawText(
            from: current.attributedSubstring(
                from: NSRange(location: suffixStart, length: current.length - suffixStart)
            )
        )
        let styled = makeDisplayString(prefix + raw + suffix)
        let caret = makeDisplayString(prefix + raw).length
        applyAttributedText(styled, selectedRange: NSRange(location: min(caret, styled.length), length: 0))
    }

    private func makeDisplayString(_ raw: String) -> NSAttributedString {
        let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        return TitleEmojiRenderer.attributedTitle(
            raw,
            font: font,
            textColor: .label,
            baseURL: api.baseURL
        )
    }

    private func applyAttributedText(_ attributed: NSAttributedString, selectedRange: NSRange) {
        isApplyingAttributedText = true
        textView.attributedText = attributed
        textView.typingAttributes = composerTextAttributes
        textView.selectedRange = clampedRange(selectedRange, length: attributed.length)
        isApplyingAttributedText = false
        loadEmojiImages(in: attributed)
        textChanged()
    }

    private func loadEmojiImages(in attributed: NSAttributedString) {
        TitleEmojiRenderer.loadImages(in: attributed, cloudflareBaseURL: api.baseURL) { [weak self] _ in
            guard let self else { return }
            let length = self.textView.attributedText.length
            self.textView.layoutManager.invalidateDisplay(
                forCharacterRange: NSRange(location: 0, length: length)
            )
            self.textView.setNeedsDisplay()
        }
    }

    private func clampedRange(_ range: NSRange, length: Int) -> NSRange {
        guard range.location != NSNotFound else {
            return NSRange(location: length, length: 0)
        }
        let location = min(max(range.location, 0), length)
        let upperBound = min(max(range.location + range.length, location), length)
        return NSRange(location: location, length: upperBound - location)
    }

    private func loadForumEmojisIfNeeded() {
        guard !hasLoadedForumEmojis else { return }
        hasLoadedForumEmojis = true
        let cachedEntries = EmojiStore.cachedEntries(for: api.baseURL) ?? []
        if cachedEntries.isEmpty {
            emojiPickerView.showLoading()
        } else {
            _ = EmojiStore.load(for: api.baseURL)
            emojiPickerView.setEmojiGroups(
                [DiscourseEmojiGroup(key: "custom", emojis: cachedEntries)],
                baseURL: api.baseURL
            )
        }
        Task {
            do {
                let groups = try await api.fetchEmojiGroups()
                await MainActor.run {
                    self.emojiPickerView.setEmojiGroups(groups, baseURL: self.api.baseURL)
                }
            } catch {
                await MainActor.run {
                    if cachedEntries.isEmpty {
                        self.emojiPickerView.showError()
                    }
                }
            }
        }
    }
}

extension BoostInputViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            submit()
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingAttributedText else { return }
        if TitleEmojiRenderer.containsShortcode(textView.attributedText.string) {
            restylePreservingSelection()
        }
        textChanged()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        guard isEmojiPickerVisible else { return }
        isEmojiPickerVisible = false
        emojiPickerView.isHidden = true
        emojiHeightConstraint?.constant = 0
        emojiToggleButton.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        view.layoutIfNeeded()
    }
}
