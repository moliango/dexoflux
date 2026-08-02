import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class ReplyComposerViewController: UIViewController {
    private enum ComposerPanel {
        case none
        case emoji
        case tools
    }

    private static let customPanelHeight: CGFloat = 420
    private static let emojiShortcodeRegex = try! NSRegularExpression(pattern: ":([^\\s:]+(?::t\\d)?):")

    private let api: DiscourseAPI
    private let topicId: Int
    private let replyToPost: DiscourseTopicDetail.Post?
    private let baseURL: String
    private let initialText: String?
    private let submissionMode: ReplyComposerSubmissionMode
    var onPostCreated: (() -> Void)?
    var onPostUpdated: ((Int) -> Void)?

    private var currentPanel: ComposerPanel = .none
    private var hasLoadedForumEmojis = false
    private var isPreviewingMarkdown = false
    private var isUploading = false
    private var isApplyingAttributedText = false
    private var panelHeightConstraint: NSLayoutConstraint?

    private let grabberView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiaryLabel.withAlphaComponent(0.35)
        view.layer.cornerRadius = 2
        return view
    }()

    private let headerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()

    private let headerTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 1
        return label
    }()

    private let discardButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "reply.discard")
        config.baseForegroundColor = .systemBlue
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var updated = attrs
            updated.font = .systemFont(ofSize: 15, weight: .medium)
            return updated
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let sendButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "reply.send")
        config.baseBackgroundColor = UIColor(red: 0.18, green: 0.42, blue: 0.62, alpha: 1)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var updated = attrs
            updated.font = .systemFont(ofSize: 15, weight: .semibold)
            return updated
        }
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        return button
    }()

    private let separatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    private let textView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 25, weight: .regular))
        tv.adjustsFontForContentSizeCategory = true
        tv.textContainerInset = UIEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        tv.backgroundColor = .systemBackground
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.returnKeyType = .default
        return tv
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "reply.markdown_placeholder")
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 25, weight: .regular))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let previewView: ComposerMarkdownPreviewView = {
        let view = ComposerMarkdownPreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()

    private let bottomStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        return stack
    }()

    private let toolbarContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()

    private let customPanelContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        return view
    }()

    private let emojiToggleButton = ReplyComposerViewController.makeCircleToolbarButton(
        systemName: "face.smiling",
        accessibilityLabel: String(localized: "reply.toolbar.emoji")
    )

    private let previewToggleButton = ReplyComposerViewController.makePlainIconButton(
        systemName: "eye",
        accessibilityLabel: String(localized: "reply.toolbar.preview")
    )

    private let toolsToggleButton = ReplyComposerViewController.makePlainIconButton(
        systemName: "plus.circle.fill",
        accessibilityLabel: String(localized: "reply.toolbar.more_tools")
    )

    private let rightToolbarPill: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 28
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let uploadStatusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var emojiPickerView: EmojiStickerPanelView = {
        let picker = EmojiStickerPanelView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onEmojiSelected = { [weak self] emoji in
            self?.insertText(emoji)
        }
        picker.onStickerMarkdownSelected = { [weak self] markdown in
            self?.insertText(markdown + "\n")
        }
        return picker
    }()

    private lazy var toolsPanelView: ComposerToolPanelView = {
        let panel = ComposerToolPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.onToolSelected = { [weak self] tool in
            self?.handleTool(tool)
        }
        return panel
    }()

    init(
        api: DiscourseAPI,
        topicId: Int,
        replyToPost: DiscourseTopicDetail.Post?,
        baseURL: String,
        initialText: String? = nil,
        submissionMode: ReplyComposerSubmissionMode = .reply
    ) {
        self.api = api
        self.topicId = topicId
        self.replyToPost = replyToPost
        self.baseURL = baseURL
        self.initialText = initialText
        self.submissionMode = submissionMode
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        switch submissionMode {
        case .reply:
            if let username = replyToPost?.username {
                headerTitleLabel.text = String(format: String(localized: "reply.title.to %@"), username)
            } else {
                headerTitleLabel.text = String(localized: "reply.title.topic")
            }
        case .edit:
            headerTitleLabel.text = String(localized: "post.edit.title", defaultValue: "编辑评论")
            var configuration = sendButton.configuration
            configuration?.title = String(localized: "common.save")
            sendButton.configuration = configuration
        }

        view.addSubview(grabberView)
        view.addSubview(headerContainer)
        headerContainer.addSubview(headerTitleLabel)
        headerContainer.addSubview(discardButton)
        headerContainer.addSubview(sendButton)
        headerContainer.addSubview(separatorView)
        view.addSubview(textView)
        view.addSubview(previewView)
        view.addSubview(placeholderLabel)
        view.addSubview(bottomStackView)

        setupToolbar()
        setupCustomPanel()
        emojiPickerView.presentingViewController = self
        PresenceService.shared.attach(api: api)

        NSLayoutConstraint.activate([
            grabberView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            grabberView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 42),
            grabberView.heightAnchor.constraint(equalToConstant: 5),

            headerContainer.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 12),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerContainer.heightAnchor.constraint(equalToConstant: 68),

            headerTitleLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 22),
            headerTitleLabel.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            headerTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: discardButton.leadingAnchor, constant: -12),

            sendButton.topAnchor.constraint(equalTo: headerContainer.topAnchor, constant: 4),
            sendButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -24),
            sendButton.heightAnchor.constraint(equalToConstant: 44),

            discardButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
            discardButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -12),

            separatorView.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5),

            textView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor),

            previewView.topAnchor.constraint(equalTo: textView.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 22),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 27),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -22),

            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStackView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        discardButton.addTarget(self, action: #selector(discardTapped), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        emojiToggleButton.addTarget(self, action: #selector(toggleEmojiPicker), for: .touchUpInside)
        previewToggleButton.addTarget(self, action: #selector(toggleMarkdownPreview), for: .touchUpInside)
        toolsToggleButton.addTarget(self, action: #selector(toggleToolsPanel), for: .touchUpInside)

        textView.delegate = self

        if let initialText, !initialText.isEmpty {
            setRawComposerText(initialText)
        }
        updatePlaceholder()
        updateSendButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        PresenceService.shared.enter(topicId: topicId)
        textView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        PresenceService.shared.leave()
    }

    private static func makeCircleToolbarButton(systemName: String, accessibilityLabel: String) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        button.accessibilityLabel = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private static func makePlainIconButton(systemName: String, accessibilityLabel: String) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = accessibilityLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func setupToolbar() {
        bottomStackView.addArrangedSubview(toolbarContainer)
        bottomStackView.addArrangedSubview(customPanelContainer)
        toolbarContainer.heightAnchor.constraint(equalToConstant: 62).isActive = true

        toolbarContainer.addSubview(emojiToggleButton)
        toolbarContainer.addSubview(uploadStatusLabel)
        toolbarContainer.addSubview(rightToolbarPill)
        rightToolbarPill.addSubview(previewToggleButton)
        rightToolbarPill.addSubview(toolsToggleButton)

        NSLayoutConstraint.activate([
            emojiToggleButton.leadingAnchor.constraint(equalTo: toolbarContainer.leadingAnchor, constant: 24),
            emojiToggleButton.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            emojiToggleButton.widthAnchor.constraint(equalToConstant: 44),
            emojiToggleButton.heightAnchor.constraint(equalToConstant: 44),

            rightToolbarPill.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -24),
            rightToolbarPill.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            rightToolbarPill.heightAnchor.constraint(equalToConstant: 44),

            uploadStatusLabel.leadingAnchor.constraint(equalTo: emojiToggleButton.trailingAnchor, constant: 14),
            uploadStatusLabel.trailingAnchor.constraint(equalTo: rightToolbarPill.leadingAnchor, constant: -14),
            uploadStatusLabel.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),

            previewToggleButton.leadingAnchor.constraint(equalTo: rightToolbarPill.leadingAnchor, constant: 10),
            previewToggleButton.topAnchor.constraint(equalTo: rightToolbarPill.topAnchor),
            previewToggleButton.bottomAnchor.constraint(equalTo: rightToolbarPill.bottomAnchor),
            previewToggleButton.widthAnchor.constraint(equalToConstant: 44),

            toolsToggleButton.leadingAnchor.constraint(equalTo: previewToggleButton.trailingAnchor, constant: 4),
            toolsToggleButton.trailingAnchor.constraint(equalTo: rightToolbarPill.trailingAnchor, constant: -10),
            toolsToggleButton.topAnchor.constraint(equalTo: rightToolbarPill.topAnchor),
            toolsToggleButton.bottomAnchor.constraint(equalTo: rightToolbarPill.bottomAnchor),
            toolsToggleButton.widthAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func setupCustomPanel() {
        customPanelContainer.addSubview(emojiPickerView)
        customPanelContainer.addSubview(toolsPanelView)

        let panelHeight = customPanelContainer.heightAnchor.constraint(equalToConstant: 0)
        panelHeightConstraint = panelHeight

        NSLayoutConstraint.activate([
            panelHeight,

            emojiPickerView.topAnchor.constraint(equalTo: customPanelContainer.topAnchor),
            emojiPickerView.leadingAnchor.constraint(equalTo: customPanelContainer.leadingAnchor),
            emojiPickerView.trailingAnchor.constraint(equalTo: customPanelContainer.trailingAnchor),
            emojiPickerView.bottomAnchor.constraint(equalTo: customPanelContainer.bottomAnchor),

            toolsPanelView.topAnchor.constraint(equalTo: customPanelContainer.topAnchor),
            toolsPanelView.leadingAnchor.constraint(equalTo: customPanelContainer.leadingAnchor),
            toolsPanelView.trailingAnchor.constraint(equalTo: customPanelContainer.trailingAnchor),
            toolsPanelView.bottomAnchor.constraint(equalTo: customPanelContainer.bottomAnchor),
        ])

        emojiPickerView.isHidden = true
        toolsPanelView.isHidden = true
    }

    @objc private func toggleEmojiPicker() {
        setPanel(currentPanel == .emoji ? .none : .emoji)
    }

    @objc private func toggleToolsPanel() {
        setPanel(currentPanel == .tools ? .none : .tools)
    }

    @objc private func toggleMarkdownPreview() {
        isPreviewingMarkdown.toggle()
        if isPreviewingMarkdown {
            closePanel(returnToKeyboard: false)
            textView.resignFirstResponder()
            previewView.update(markdown: composerRawText)
        } else {
            textView.becomeFirstResponder()
        }
        updatePreviewState()
    }

    private func setPanel(_ panel: ComposerPanel) {
        if isPreviewingMarkdown {
            isPreviewingMarkdown = false
            updatePreviewState()
        }

        currentPanel = panel
        switch panel {
        case .none:
            emojiPickerView.isHidden = true
            toolsPanelView.isHidden = true
            panelHeightConstraint?.constant = 0
            textView.becomeFirstResponder()
        case .emoji:
            textView.resignFirstResponder()
            emojiPickerView.isHidden = false
            toolsPanelView.isHidden = true
            panelHeightConstraint?.constant = Self.customPanelHeight
            loadForumEmojis()
        case .tools:
            textView.resignFirstResponder()
            emojiPickerView.isHidden = true
            toolsPanelView.isHidden = false
            panelHeightConstraint?.constant = Self.customPanelHeight
        }
        updateToolbarState()
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.view.layoutIfNeeded()
        }
    }

    private func closePanel(returnToKeyboard: Bool) {
        guard currentPanel != .none else { return }
        currentPanel = .none
        emojiPickerView.isHidden = true
        toolsPanelView.isHidden = true
        panelHeightConstraint?.constant = 0
        updateToolbarState()
        if returnToKeyboard {
            textView.becomeFirstResponder()
        }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.view.layoutIfNeeded()
        }
    }

    private func loadForumEmojis() {
        guard !hasLoadedForumEmojis else { return }
        hasLoadedForumEmojis = true
        emojiPickerView.showLoading()
        Task {
            do {
                let groups = try await api.fetchEmojiGroups()
                await MainActor.run {
                    self.emojiPickerView.setEmojiGroups(groups, baseURL: self.baseURL)
                }
            } catch {
                await MainActor.run {
                    self.emojiPickerView.showError()
                }
            }
        }
    }

    private var composerRawText: String {
        rawText(from: textView.attributedText ?? NSAttributedString(string: textView.text ?? ""))
    }

    private var composerDisplayText: String {
        textView.attributedText?.string ?? textView.text ?? ""
    }

    private var composerTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: textView.font ?? UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 25)),
            .foregroundColor: UIColor.label,
        ]
    }

    private func setRawComposerText(_ raw: String) {
        let attributed = makeComposerAttributedString(raw)
        applyComposerAttributedText(attributed, selectedRange: NSRange(location: attributed.length, length: 0))
    }

    private func rawText(inDisplayRange range: NSRange) -> String {
        let attributed = textView.attributedText ?? NSAttributedString(string: textView.text ?? "", attributes: composerTextAttributes)
        let validRange = clampedRange(range, length: attributed.length)
        guard validRange.length > 0 else { return "" }
        return rawText(from: attributed.attributedSubstring(from: validRange))
    }

    private func rawText(from attributed: NSAttributedString) -> String {
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

    private func makeComposerAttributedString(_ raw: String) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let font = textView.font ?? UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 25))
        let attrs = composerTextAttributes
        let matches = Self.emojiShortcodeRegex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
        var lastEnd = raw.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: raw),
                  let codeRange = Range(match.range(at: 1), in: raw)
            else { continue }

            if lastEnd < fullRange.lowerBound {
                result.append(NSAttributedString(string: String(raw[lastEnd..<fullRange.lowerBound]), attributes: attrs))
            }

            let code = String(raw[codeRange])
            let shortcode = String(raw[fullRange])
            if let urlString = EmojiStore.url(for: code), let url = URL(string: urlString) {
                let attachment = EmojiTextAttachment()
                attachment.emojiURL = url
                attachment.shortcode = shortcode
                attachment.bounds = CGRect(
                    x: 0,
                    y: font.descender,
                    width: font.lineHeight,
                    height: font.lineHeight
                )
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(string: shortcode, attributes: attrs))
            }

            lastEnd = fullRange.upperBound
        }

        if lastEnd < raw.endIndex {
            result.append(NSAttributedString(string: String(raw[lastEnd...]), attributes: attrs))
        }
        return result
    }

    private func replaceDisplayRange(
        _ range: NSRange,
        withRawText raw: String,
        selectedRangeInInsertedText: NSRange? = nil
    ) {
        let current = NSMutableAttributedString(attributedString: textView.attributedText ?? NSAttributedString(string: textView.text ?? "", attributes: composerTextAttributes))
        let validRange = clampedRange(range, length: current.length)
        let inserted = makeComposerAttributedString(raw)
        current.replaceCharacters(in: validRange, with: inserted)

        let relativeSelection = selectedRangeInInsertedText ?? NSRange(location: inserted.length, length: 0)
        let selectedLocation = min(max(relativeSelection.location, 0), inserted.length)
        let selectedLength = min(max(relativeSelection.length, 0), inserted.length - selectedLocation)
        let selectedRange = NSRange(location: validRange.location + selectedLocation, length: selectedLength)
        applyComposerAttributedText(current, selectedRange: selectedRange)
    }

    private func replaceSelection(withRawText raw: String, selectedRangeInInsertedText: NSRange? = nil) {
        replaceDisplayRange(textView.selectedRange, withRawText: raw, selectedRangeInInsertedText: selectedRangeInInsertedText)
    }

    private func applyComposerAttributedText(_ attributed: NSMutableAttributedString, selectedRange: NSRange) {
        isApplyingAttributedText = true
        textView.attributedText = attributed
        textView.typingAttributes = composerTextAttributes
        textView.selectedRange = clampedRange(selectedRange, length: attributed.length)
        isApplyingAttributedText = false
        loadComposerEmojiImages(in: attributed)
        updatePlaceholder()
        updateSendButton()
        if isPreviewingMarkdown {
            previewView.update(markdown: composerRawText)
        }
    }

    private func loadComposerEmojiImages(in attributed: NSAttributedString) {
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            guard let attachment = value as? EmojiTextAttachment,
                  attachment.image == nil,
                  let url = attachment.emojiURL
            else { return }

            ForumImageLoader.loadImage(with: url) { [weak self, weak attachment] image in
                guard let self, let attachment, let image else { return }
                DispatchQueue.main.async {
                    attachment.image = image
                    self.textView.layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: self.textView.attributedText.length))
                    self.textView.setNeedsDisplay()
                }
            }
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

    private func insertText(_ text: String) {
        replaceSelection(withRawText: text)
    }

    private func handleTool(_ tool: ComposerMarkdownTool) {
        if isUploading { return }
        if isPreviewingMarkdown {
            isPreviewingMarkdown = false
            updatePreviewState()
        }

        switch tool {
        case .image:
            pickImages()
        case .attachment:
            pickAttachment()
        case .media:
            chooseMedia()
        case .heading:
            chooseHeading()
        case .bold:
            wrapSelection(start: "**", end: "**", placeholder: String(localized: "reply.tool.placeholder.bold"))
        case .italic:
            wrapSelection(start: "*", end: "*", placeholder: String(localized: "reply.tool.placeholder.italic"))
        case .strikethrough:
            wrapSelection(start: "~~", end: "~~", placeholder: String(localized: "reply.tool.placeholder.strikethrough"))
        case .bulletList:
            applyLinePrefix("- ")
        case .numberedList:
            applyLinePrefix("1. ")
        case .link:
            insertLink()
        case .quote:
            applyLinePrefix("> ")
        case .callout:
            chooseCallout()
        case .template:
            insertTemplate()
        case .aiReview:
            runAIPostReview()
        case .inlineCode:
            wrapSelection(start: "`", end: "`", placeholder: String(localized: "reply.tool.placeholder.code"))
        case .codeBlock:
            insertCodeBlock()
        case .spoiler:
            wrapSelection(
                start: "[spoiler]",
                end: "[/spoiler]",
                placeholder: String(localized: "reply.tool.placeholder.spoiler", defaultValue: "剧透内容")
            )
        case .imageGrid:
            wrapImagesInGrid()
        case .insertBlock:
            chooseInsertBlock()
        }

        if tool.closesPanelAfterAction {
            closePanel(returnToKeyboard: true)
        }
    }

    private func wrapSelection(start: String, end: String, placeholder: String) {
        let selection = textView.selectedRange
        let selected = selection.length > 0 ? rawText(inDisplayRange: selection) : placeholder
        let replacement = "\(start)\(selected)\(end)"
        let selectedDisplayLength = makeComposerAttributedString(selected).length
        replaceDisplayRange(
            selection,
            withRawText: replacement,
            selectedRangeInInsertedText: NSRange(location: start.count, length: selectedDisplayLength)
        )
    }

    private func applyLinePrefix(_ prefix: String) {
        let text = composerDisplayText
        let nsText = text as NSString
        let selection = textView.selectedRange
        let lineRange = nsText.lineRange(for: NSRange(location: min(selection.location, nsText.length), length: 0))
        let lineText = nsText.substring(with: lineRange)
        if lineText.hasPrefix(prefix) {
            let removalRange = NSRange(location: lineRange.location, length: prefix.count)
            replaceDisplayRange(removalRange, withRawText: "")
            textView.selectedRange = clampedRange(
                NSRange(location: max(selection.location - prefix.count, lineRange.location), length: selection.length),
                length: textView.attributedText.length
            )
        } else {
            replaceDisplayRange(NSRange(location: lineRange.location, length: 0), withRawText: prefix)
            textView.selectedRange = clampedRange(
                NSRange(location: selection.location + prefix.count, length: selection.length),
                length: textView.attributedText.length
            )
        }
        updatePlaceholder()
        updateSendButton()
    }

    private func insertBlock(_ block: String) {
        let text = composerDisplayText
        let selection = textView.selectedRange
        let nsText = text as NSString
        let needsLeadingNewline = selection.location > 0 && nsText.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n"
        let insertion = needsLeadingNewline ? "\n\(block)" : block
        replaceDisplayRange(selection, withRawText: insertion)
    }

    private func chooseHeading() {
        let alert = UIAlertController(
            title: String(localized: "reply.tool.heading"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for level in 1 ... 5 {
            alert.addAction(UIAlertAction(title: "H\(level)", style: .default) { [weak self] _ in
                self?.applyLinePrefix(String(repeating: "#", count: level) + " ")
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = toolsToggleButton
            pop.sourceRect = toolsToggleButton.bounds
        }
        present(alert, animated: true)
    }

    /// FluxDo callout 类型菜单：note / tip / info / warning …
    private func chooseCallout() {
        let types = [
            "note", "tip", "info", "warning", "danger", "bug",
            "example", "quote", "abstract", "todo", "success", "question", "failure",
        ]
        let alert = UIAlertController(
            title: String(localized: "reply.tool.note"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for type in types {
            alert.addAction(UIAlertAction(title: type.capitalized, style: .default) { [weak self] _ in
                self?.insertCallout(type)
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = toolsToggleButton
            pop.sourceRect = toolsToggleButton.bounds
        }
        present(alert, animated: true)
    }

    private func insertCallout(_ type: String) {
        let placeholder = String(localized: "reply.tool.placeholder.note")
        let selection = textView.selectedRange
        if selection.length > 0 {
            let selected = rawText(inDisplayRange: selection)
            let quoted = selected
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }
                .joined(separator: "\n")
            replaceDisplayRange(selection, withRawText: "> [!\(type)]\n\(quoted)")
        } else {
            insertBlock("> [!\(type)]\n> \(placeholder)\n")
        }
    }

    private func insertCodeBlock() {
        let selection = textView.selectedRange
        let placeholder = String(localized: "reply.tool.placeholder.code")
        if selection.length > 0 {
            let selected = rawText(inDisplayRange: selection)
            let block = "```\n\(selected)\n```"
            replaceDisplayRange(selection, withRawText: block)
        } else {
            insertBlock("```\n\(placeholder)\n```\n")
        }
    }

    /// 插入块：表格 / 公式 / 分隔线 / 折叠详情
    private func chooseInsertBlock() {
        let items: [(String, String)] = [
            ("表格", "| 列 1 | 列 2 |\n|---|---|\n| 内容 | 内容 |\n"),
            ("公式块", "$$\nE=mc^2\n$$\n"),
            ("分隔线", "---\n"),
            ("折叠详情", "[details=\"点开看\"]\n折叠内容\n[/details]\n"),
        ]
        let alert = UIAlertController(
            title: "插入块",
            message: nil,
            preferredStyle: .actionSheet
        )
        for item in items {
            alert.addAction(UIAlertAction(title: item.0, style: .default) { [weak self] _ in
                self?.insertBlock(item.1)
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = toolsToggleButton
            pop.sourceRect = toolsToggleButton.bounds
        }
        present(alert, animated: true)
    }

    /// 将连续图片 markdown 包进 `[grid]…[/grid]`（对齐 FluxDo）
    private func wrapImagesInGrid() {
        let raw = composerRawText
        let imagePattern = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\([^)]+\)"#)
        let nsRaw = raw as NSString
        let fullRange = NSRange(location: 0, length: nsRaw.length)
        let matches = imagePattern.matches(in: raw, range: fullRange)
        guard matches.count >= 2 else {
            let alert = UIAlertController(
                title: nil,
                message: String(localized: "reply.tool.grid.min_images", defaultValue: "至少需要 2 张图片才能组成网格"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
            present(alert, animated: true)
            return
        }

        // 优先用选区；否则取光标附近连续图片块
        let displaySelection = textView.selectedRange
        let rawSelectionStart: Int
        let rawSelectionEnd: Int
        if displaySelection.length > 0 {
            let selectedRaw = rawText(inDisplayRange: displaySelection)
            let selectedMatches = imagePattern.matches(in: selectedRaw, range: NSRange(location: 0, length: (selectedRaw as NSString).length))
            if selectedMatches.count >= 2 {
                let wrapped = "[grid]\n\(selectedRaw)\n[/grid]"
                replaceDisplayRange(displaySelection, withRawText: wrapped)
                return
            }
            rawSelectionStart = 0
            rawSelectionEnd = 0
            _ = rawSelectionStart
            _ = rawSelectionEnd
        }

        // 找最大连续图片组（之间仅空白）
        var bestStart = matches[0].range.location
        var bestEnd = NSMaxRange(matches[0].range)
        var runStart = bestStart
        var runEnd = bestEnd
        var runCount = 1
        var bestCount = 1

        for i in 1 ..< matches.count {
            let prevEnd = NSMaxRange(matches[i - 1].range)
            let curStart = matches[i].range.location
            let between = nsRaw.substring(with: NSRange(location: prevEnd, length: curStart - prevEnd))
            if between.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                runEnd = NSMaxRange(matches[i].range)
                runCount += 1
            } else {
                if runCount > bestCount {
                    bestCount = runCount
                    bestStart = runStart
                    bestEnd = runEnd
                }
                runStart = matches[i].range.location
                runEnd = NSMaxRange(matches[i].range)
                runCount = 1
            }
        }
        if runCount > bestCount {
            bestCount = runCount
            bestStart = runStart
            bestEnd = runEnd
        }
        guard bestCount >= 2 else {
            let alert = UIAlertController(
                title: nil,
                message: String(localized: "reply.tool.grid.min_images", defaultValue: "至少需要 2 张图片才能组成网格"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
            present(alert, animated: true)
            return
        }

        let chunk = nsRaw.substring(with: NSRange(location: bestStart, length: bestEnd - bestStart))
        let wrapped = "[grid]\n\(chunk)\n[/grid]"
        // 用 raw 全文替换后重刷（composer 以 raw 为源）
        let newRaw = nsRaw.replacingCharacters(in: NSRange(location: bestStart, length: bestEnd - bestStart), with: wrapped)
        applyFullRawText(newRaw)
    }

    private func applyFullRawText(_ raw: String) {
        isApplyingAttributedText = true
        textView.attributedText = makeComposerAttributedString(raw)
        isApplyingAttributedText = false
        updatePlaceholder()
        updateSendButton()
        if isPreviewingMarkdown {
            previewView.update(markdown: raw)
        }
    }

    private var pendingMediaKind: MediaPickKind?

    private enum MediaPickKind {
        case audio
        case video
        case voice
    }

    /// 音视频：上传音频 / 上传视频 / 语音消息
    private func chooseMedia() {
        let alert = UIAlertController(title: "音视频", message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "上传音频", style: .default) { [weak self] _ in
            self?.pickMedia(kind: .audio)
        })
        alert.addAction(UIAlertAction(title: "上传视频", style: .default) { [weak self] _ in
            self?.pickMedia(kind: .video)
        })
        alert.addAction(UIAlertAction(title: "语音消息", style: .default) { [weak self] _ in
            self?.pickMedia(kind: .voice)
        })
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = toolsToggleButton
            pop.sourceRect = toolsToggleButton.bounds
        }
        present(alert, animated: true)
    }

    private func pickMedia(kind: MediaPickKind) {
        pendingMediaKind = kind
        let types: [UTType]
        switch kind {
        case .audio, .voice:
            types = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        case .video:
            types = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @MainActor
    private func uploadMediaFile(url: URL, kind: MediaPickKind) async {
        setUploading(true, text: String(localized: "reply.uploading"))
        defer {
            setUploading(false, text: nil)
            pendingMediaKind = nil
        }
        do {
            // FluxDo：改名为 .xz 绕站点扩展名白名单
            let xzURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("xz")
            if FileManager.default.fileExists(atPath: xzURL.path) {
                try FileManager.default.removeItem(at: xzURL)
            }
            try FileManager.default.copyItem(at: url, to: xzURL)
            let upload = try await api.uploadComposerFile(fileURL: xzURL, filename: xzURL.lastPathComponent)
            try? FileManager.default.removeItem(at: xzURL)

            let originalExt = url.pathExtension.lowercased()
            let mime: String
            let isAudio: Bool
            switch kind {
            case .audio, .voice:
                isAudio = true
                mime = UTType(filenameExtension: originalExt)?.preferredMIMEType ?? "audio/mpeg"
            case .video:
                isAudio = false
                mime = UTType(filenameExtension: originalExt)?.preferredMIMEType ?? "video/mp4"
            }
            let src = Self.mediaPlaybackPath(from: upload.shortURL)
            let tag: String
            if isAudio {
                let audio = "<audio controls>\n  <source src=\"\(src)\" type=\"\(mime)\">\n</audio>"
                tag = kind == .voice ? "[wrap=voice]\n\(audio)\n[/wrap]" : audio
            } else {
                tag = "<video width=\"640\" height=\"360\" controls>\n  <source src=\"\(src)\" type=\"\(mime)\">\n</video>"
            }
            insertUploadMarkdown(tag)
        } catch {
            showUploadError(error)
        }
    }

    /// `upload://token.ext` → `/uploads/short-url/token.xz`
    private static func mediaPlaybackPath(from shortURL: String) -> String {
        if shortURL.hasPrefix("upload://") {
            var token = String(shortURL.dropFirst("upload://".count))
            if let dot = token.lastIndex(of: ".") {
                token = String(token[..<dot])
            }
            return "/uploads/short-url/\(token).xz"
        }
        if let dot = shortURL.lastIndex(of: ".") {
            return String(shortURL[..<dot]) + ".xz"
        }
        return shortURL
    }

    private func insertLink() {
        let selected = textView.selectedRange.length > 0 ? rawText(inDisplayRange: textView.selectedRange) : ""
        let alert = UIAlertController(
            title: String(localized: "reply.tool.link"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(localized: "reply.tool.link_text")
            field.text = selected
        }
        alert.addTextField { field in
            field.placeholder = "https://"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "reply.tool.insert"), style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = alert?.textFields?.dropFirst().first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url, !url.isEmpty else { return }
            let linkTitle = (title?.isEmpty == false ? title : url) ?? url
            self.replaceSelection(withRawText: "[\(linkTitle)](\(url))")
        })
        present(alert, animated: true)
    }

    
    private func runAIPostReview() {
        let content = composerRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        let hud = UIAlertController(title: String(localized: "ai.review.running", defaultValue: "AI 预审中…"), message: nil, preferredStyle: .alert)
        present(hud, animated: true)
        Task {
            do {
                let result = try await AIPostReviewService.reviewDraft(title: nil, content: content, categoryName: nil)
                await MainActor.run {
                    hud.dismiss(animated: true) {
                        let alert = UIAlertController(title: String(localized: "ai.review.result", defaultValue: "预审结果"), message: result, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "好"), style: .default))
                        self.present(alert, animated: true)
                    }
                }
            } catch {
                await MainActor.run {
                    hud.dismiss(animated: true) {
                        let alert = UIAlertController(title: String(localized: "common.error", defaultValue: "错误"), message: error.localizedDescription, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "好"), style: .default))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }

private func insertTemplate() {
        let alert = UIAlertController(
            title: String(localized: "reply.tool.template"),
            message: nil,
            preferredStyle: .actionSheet
        )
        let templates: [(String, String)] = [
            (String(localized: "reply.template.summary"), "## \(String(localized: "reply.template.summary"))\n\n- \n"),
            (String(localized: "reply.template.steps"), "## \(String(localized: "reply.template.steps"))\n\n1. \n2. \n3. \n"),
            (String(localized: "reply.template.code"), "```\n\(String(localized: "reply.tool.placeholder.code"))\n```\n"),
        ]
        for template in templates {
            alert.addAction(UIAlertAction(title: template.0, style: .default) { [weak self] _ in
                self?.insertBlock(template.1)
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func replaceSelection(with text: String) {
        replaceSelection(withRawText: text)
    }

    private func pickImages() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 0
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func pickAttachment() {
        pendingMediaKind = nil
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @MainActor
    private func uploadPickedFiles(_ files: [(url: URL, filename: String)]) async {
        guard !files.isEmpty else { return }
        setUploading(true, text: String(localized: "reply.uploading"))
        defer { setUploading(false, text: nil) }

        for (index, file) in files.enumerated() {
            if files.count > 1 {
                setUploading(true, text: "\(index + 1)/\(files.count)")
            }
            do {
                let upload = try await api.uploadComposerFile(fileURL: file.url, filename: file.filename)
                insertUploadMarkdown(upload.markdown)
            } catch {
                showUploadError(error)
                return
            }
        }
    }

    private func insertUploadMarkdown(_ markdown: String) {
        let text = composerDisplayText
        let selection = textView.selectedRange
        let nsText = text as NSString
        let needsLeadingNewline = selection.location > 0 && nsText.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n"
        let insertion = "\(needsLeadingNewline ? "\n" : "")\(markdown)\n"
        replaceSelection(withRawText: insertion)
    }

    @MainActor
    private func setUploading(_ uploading: Bool, text: String?) {
        isUploading = uploading
        uploadStatusLabel.text = text
        uploadStatusLabel.isHidden = !uploading
        textView.isEditable = !uploading
        updateSendButton()
        toolsPanelView.isUploading = uploading
    }

    private func showUploadError(_ error: Error) {
        let alert = UIAlertController(
            title: String(localized: "reply.upload.failed"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = isPreviewingMarkdown || !composerRawText.isEmpty
    }

    private func updateSendButton() {
        let enabled = !(composerRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        sendButton.isEnabled = enabled && !isUploading
        sendButton.alpha = sendButton.isEnabled ? 1 : 0.55
    }

    private func updatePreviewState() {
        textView.isHidden = isPreviewingMarkdown
        previewView.isHidden = !isPreviewingMarkdown
        placeholderLabel.isHidden = isPreviewingMarkdown || !composerRawText.isEmpty
        updateToolbarState()
    }

    private func updateToolbarState() {
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let previewSymbol = isPreviewingMarkdown ? "eye.slash.fill" : "eye"
        previewToggleButton.setImage(UIImage(systemName: previewSymbol, withConfiguration: symbolConfig), for: .normal)
        previewToggleButton.tintColor = isPreviewingMarkdown ? .systemBlue : .label
        toolsToggleButton.tintColor = currentPanel == .tools ? .systemBlue : .label
        emojiToggleButton.tintColor = currentPanel == .emoji ? .systemBlue : .label
    }

    @objc private func discardTapped() {
        guard !composerRawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            dismiss(animated: true)
            return
        }
        let alert = UIAlertController(
            title: String(localized: "reply.discard.confirm.title"),
            message: String(localized: "reply.discard.confirm.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "reply.discard"), style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func sendTapped() {
        let raw = composerRawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        sendButton.isEnabled = false
        textView.isEditable = false
        closePanel(returnToKeyboard: false)

        Task {
            do {
                switch submissionMode {
                case .reply:
                    let response = try await api.createReply(
                        topicId: topicId,
                        replyToPostNumber: replyToPost?.postNumber,
                        raw: raw
                    )
                    if response.isEnqueued {
                        presentQueuedAlert()
                        return
                    }
                    dismiss(animated: true) { [weak self] in
                        self?.onPostCreated?()
                    }
                case .edit(let postId):
                    try await api.updatePost(id: postId, raw: raw)
                    dismiss(animated: true) { [weak self] in
                        self?.onPostUpdated?(postId)
                    }
                }
            } catch {
                sendButton.isEnabled = true
                textView.isEditable = true
                let alert = UIAlertController(
                    title: String(localized: "reply.send.failed"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func presentQueuedAlert() {
        let alert = UIAlertController(
            title: String(localized: "post.submit.queued.title"),
            message: String(localized: "post.submit.queued.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}

extension ReplyComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        guard !isApplyingAttributedText else { return }
        updatePlaceholder()
        updateSendButton()
        if isPreviewingMarkdown {
            previewView.update(markdown: composerRawText)
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if currentPanel != .none {
            closePanel(returnToKeyboard: false)
        }
    }
}

extension ReplyComposerViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        Task {
            var files: [(url: URL, filename: String)] = []
            for result in results {
                if let file = try? await temporaryImageFile(from: result) {
                    files.append(file)
                }
            }
            await uploadPickedFiles(files)
        }
    }

    private func temporaryImageFile(from result: PHPickerResult) async throws -> (url: URL, filename: String) {
        let provider = result.itemProvider
        let typeIdentifier = provider.registeredTypeIdentifiers.first { identifier in
            UTType(identifier)?.conforms(to: .image) == true
        } ?? UTType.image.identifier

        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: DiscourseAPIError(messages: [String(localized: "reply.upload.failed")], errorType: "upload_failed"))
                    return
                }
                do {
                    let type = UTType(typeIdentifier)
                    let ext = type?.preferredFilenameExtension ?? url.pathExtension
                    let cleanExt = ext.isEmpty ? "jpg" : ext
                    let baseName = provider.suggestedName ?? "image"
                    let filename = "\(baseName).\(cleanExt)"
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(cleanExt)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: (destination, filename))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension ReplyComposerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if let kind = pendingMediaKind {
                await uploadMediaFile(url: url, kind: kind)
            } else {
                await uploadPickedFiles([(url, url.lastPathComponent)])
            }
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingMediaKind = nil
    }
}
