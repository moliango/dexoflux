import PhotosUI
import UIKit
import UniformTypeIdentifiers

enum BoostInputResult {
    case boost(String)
    case reply(String)
}

final class BoostInputViewController: UIViewController {
    private static let maxVisibleLength = 16
    private static let emojiShortcodeRegex = try! NSRegularExpression(pattern: ":[\\w\\-+]+:")

    private let api: DiscourseAPI
    var onSubmit: ((BoostInputResult) -> Void)?

    private var isEmojiPickerVisible = true
    private var hasLoadedForumEmojis = false

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

    private lazy var textField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = String(localized: "post.boost.placeholder")
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .send
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        return field
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

        textContainer.addSubview(textField)
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

            textField.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor, constant: 14),
            textField.topAnchor.constraint(equalTo: textContainer.topAnchor, constant: 7),
            textField.bottomAnchor.constraint(equalTo: textContainer.bottomAnchor, constant: -7),
            countLabel.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor, constant: -12),
            countLabel.centerYAnchor.constraint(equalTo: textField.centerYAnchor),
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

    private var rawText: String {
        textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var visibleLength: Int {
        let text = textField.text ?? ""
        let nsText = text as NSString
        let matches = Self.emojiShortcodeRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        let shortcodeSavings = matches.reduce(0) { $0 + max($1.range.length - 1, 0) }
        return max(nsText.length - shortcodeSavings, 0)
    }

    private var isReplyIntent: Bool {
        visibleLength > Self.maxVisibleLength
    }

    @objc private func textChanged() {
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
            textField.resignFirstResponder()
            loadForumEmojisIfNeeded()
        } else {
            textField.becomeFirstResponder()
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
        if let range = textField.selectedTextRange {
            textField.replace(range, withText: emoji)
        } else {
            textField.text = (textField.text ?? "") + emoji
        }
        textChanged()
    }

    private func loadForumEmojisIfNeeded() {
        guard !hasLoadedForumEmojis else { return }
        hasLoadedForumEmojis = true
        let cachedEntries = EmojiStore.cachedEntries(for: api.baseURL) ?? []
        if cachedEntries.isEmpty {
            emojiPickerView.showLoading()
        } else {
            EmojiStore.load(for: api.baseURL)
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

extension BoostInputViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submit()
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard isEmojiPickerVisible else { return }
        isEmojiPickerVisible = false
        emojiPickerView.isHidden = true
        emojiHeightConstraint?.constant = 0
        emojiToggleButton.setImage(UIImage(systemName: "face.smiling"), for: .normal)
        view.layoutIfNeeded()
    }
}

final class ReplyComposerViewController: UIViewController {
    private enum ComposerPanel {
        case none
        case emoji
        case tools
    }

    private static let customPanelHeight: CGFloat = 300
    private static let emojiShortcodeRegex = try! NSRegularExpression(pattern: ":([^\\s:]+(?::t\\d)?):")

    private let api: DiscourseAPI
    private let topicId: Int
    private let replyToPost: DiscourseTopicDetail.Post?
    private let baseURL: String
    private let initialText: String?
    var onPostCreated: (() -> Void)?

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

    private lazy var emojiPickerView: EmojiPickerView = {
        let picker = EmojiPickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onEmojiSelected = { [weak self] emoji in
            self?.insertText(emoji)
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
        initialText: String? = nil
    ) {
        self.api = api
        self.topicId = topicId
        self.replyToPost = replyToPost
        self.baseURL = baseURL
        self.initialText = initialText
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        if let username = replyToPost?.username {
            headerTitleLabel.text = String(format: String(localized: "reply.title.to %@"), username)
        } else {
            headerTitleLabel.text = String(localized: "reply.title.topic")
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
        textView.becomeFirstResponder()
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
        case .note:
            insertBlock("\n> [!note]\n> \(String(localized: "reply.tool.placeholder.note"))\n")
        case .template:
            insertTemplate()
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
        for level in 1 ... 3 {
            alert.addAction(UIAlertAction(title: "H\(level)", style: .default) { [weak self] _ in
                self?.applyLinePrefix(String(repeating: "#", count: level) + " ")
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        present(alert, animated: true)
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
                _ = try await api.createReply(
                    topicId: topicId,
                    replyToPostNumber: replyToPost?.postNumber,
                    raw: raw
                )
                dismiss(animated: true) { [weak self] in
                    self?.onPostCreated?()
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
            await uploadPickedFiles([(url, url.lastPathComponent)])
        }
    }
}

private enum ComposerMarkdownTool: CaseIterable {
    case image
    case attachment
    case heading
    case bold
    case italic
    case strikethrough
    case bulletList
    case numberedList
    case link
    case quote
    case note
    case template

    var title: String {
        switch self {
        case .image: return String(localized: "reply.tool.image")
        case .attachment: return String(localized: "reply.tool.attachment")
        case .heading: return String(localized: "reply.tool.heading")
        case .bold: return String(localized: "reply.tool.bold")
        case .italic: return String(localized: "reply.tool.italic")
        case .strikethrough: return String(localized: "reply.tool.strikethrough")
        case .bulletList: return String(localized: "reply.tool.bullet_list")
        case .numberedList: return String(localized: "reply.tool.numbered_list")
        case .link: return String(localized: "reply.tool.link")
        case .quote: return String(localized: "reply.tool.quote")
        case .note: return String(localized: "reply.tool.note")
        case .template: return String(localized: "reply.tool.template")
        }
    }

    var symbolName: String {
        switch self {
        case .image: return "photo"
        case .attachment: return "paperclip"
        case .heading: return "textformat.size"
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .link: return "link"
        case .quote: return "quote.closing"
        case .note: return "note.text"
        case .template: return "doc.on.clipboard"
        }
    }

    var closesPanelAfterAction: Bool {
        switch self {
        case .image, .attachment:
            return false
        default:
            return true
        }
    }
}

private final class ComposerToolPanelView: UIView {
    var onToolSelected: ((ComposerMarkdownTool) -> Void)?

    var isUploading = false {
        didSet {
            toolButtons.forEach { button in
                guard let tool = toolByButton[button] else { return }
                button.isEnabled = !isUploading || (tool != .image && tool != .attachment)
                button.alpha = button.isEnabled ? 1 : 0.45
            }
        }
    }

    private var isCustomizing = false
    private var toolButtons: [UIButton] = []
    private var toolByButton: [UIButton: ComposerMarkdownTool] = [:]

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = String(localized: "reply.more_tools")
        return label
    }()

    private let customizeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "reply.customize")
        config.baseForegroundColor = UIColor(red: 0.18, green: 0.42, blue: 0.62, alpha: 1)
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let gridStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        addSubview(titleLabel)
        addSubview(customizeButton)
        addSubview(gridStackView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),

            customizeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            customizeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -34),

            gridStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            gridStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 34),
            gridStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -34),
            gridStackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12),
        ])

        customizeButton.addTarget(self, action: #selector(customizeTapped), for: .touchUpInside)
        buildGrid()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildGrid() {
        let tools = ComposerMarkdownTool.allCases
        for rowIndex in 0 ..< 3 {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.distribution = .fillEqually
            row.spacing = 10
            gridStackView.addArrangedSubview(row)

            for column in 0 ..< 4 {
                let index = rowIndex * 4 + column
                guard tools.indices.contains(index) else { continue }
                let button = makeToolButton(tools[index])
                row.addArrangedSubview(button)
            }
        }
    }

    private func makeToolButton(_ tool: ComposerMarkdownTool) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: tool.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        config.imagePlacement = .top
        config.imagePadding = 6
        config.title = tool.title
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var updated = attrs
            updated.font = .systemFont(ofSize: 12, weight: .regular)
            return updated
        }
        config.background.backgroundColor = .clear

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 58).isActive = true
        button.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
        toolButtons.append(button)
        toolByButton[button] = tool
        return button
    }

    @objc private func toolTapped(_ sender: UIButton) {
        guard !isCustomizing, let tool = toolByButton[sender] else { return }
        onToolSelected?(tool)
    }

    @objc private func customizeTapped() {
        isCustomizing.toggle()
        var config = customizeButton.configuration
        config?.title = isCustomizing ? String(localized: "common.done") : String(localized: "reply.customize")
        customizeButton.configuration = config
        toolButtons.forEach { button in
            button.transform = isCustomizing ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            button.alpha = isCustomizing ? 0.7 : 1
        }
    }
}

private final class ComposerMarkdownPreviewView: UIView {
    private let textView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isEditable = false
        tv.isScrollEnabled = true
        tv.backgroundColor = .systemBackground
        tv.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        tv.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 23, weight: .regular))
        tv.adjustsFontForContentSizeCategory = true
        return tv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(markdown: String) {
        textView.attributedText = Self.render(markdown)
    }

    private static func render(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 12

        let bodyFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 23, weight: .regular))
        let headingFont = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 30, weight: .bold))
        let monoFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 20, weight: .regular))

        var inCodeBlock = false
        for rawLine in markdown.components(separatedBy: .newlines) {
            var line = rawLine
            var attributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph,
            ]

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock {
                attributes[.font] = monoFont
                attributes[.foregroundColor] = UIColor.secondaryLabel
                attributes[.backgroundColor] = UIColor.secondarySystemGroupedBackground
            } else if line.hasPrefix("### ") {
                line.removeFirst(4)
                attributes[.font] = headingFont.withSize(24)
            } else if line.hasPrefix("## ") {
                line.removeFirst(3)
                attributes[.font] = headingFont.withSize(27)
            } else if line.hasPrefix("# ") {
                line.removeFirst(2)
                attributes[.font] = headingFont
            } else if line.hasPrefix("> ") {
                line.removeFirst(2)
                attributes[.foregroundColor] = UIColor.secondaryLabel
            } else if line.hasPrefix("- ") {
                line = "• " + String(line.dropFirst(2))
            }

            result.append(renderInline(line, attributes: attributes))
            result.append(NSAttributedString(string: "\n", attributes: attributes))
        }

        if result.length == 0 {
            return NSAttributedString(
                string: String(localized: "reply.preview.empty"),
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: UIColor.placeholderText,
                    .paragraphStyle: paragraph,
                ]
            )
        }
        return result
    }

    private static func renderInline(_ line: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: line, attributes: attributes)
        applyInline(regex: "\\*\\*(.+?)\\*\\*", in: attributed, fontWeight: .bold, markerLength: 2)
        applyInline(regex: "~~(.+?)~~", in: attributed, strikethrough: true, markerLength: 2)
        applyInline(regex: "`(.+?)`", in: attributed, monospace: true, markerLength: 1)
        return attributed
    }

    private static func applyInline(
        regex pattern: String,
        in attributed: NSMutableAttributedString,
        fontWeight: UIFont.Weight? = nil,
        strikethrough: Bool = false,
        monospace: Bool = false,
        markerLength: Int
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: attributed.string, range: NSRange(location: 0, length: attributed.length)).reversed()
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let contentRange = match.range(at: 1)
            let fullRange = match.range(at: 0)
            if let fontWeight {
                let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 23, weight: fontWeight))
                attributed.addAttribute(.font, value: font, range: contentRange)
            }
            if strikethrough {
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }
            if monospace {
                let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 20, weight: .regular))
                attributed.addAttribute(.font, value: font, range: contentRange)
            }
            attributed.deleteCharacters(in: NSRange(location: fullRange.location + fullRange.length - markerLength, length: markerLength))
            attributed.deleteCharacters(in: NSRange(location: fullRange.location, length: markerLength))
        }
    }
}
