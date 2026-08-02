import PhotosUI
import UIKit
import UniformTypeIdentifiers

enum BoostInputResult {
    case boost(String)
    case reply(String)
}

enum ReplyComposerSubmissionMode: Equatable {
    case reply
    case edit(postId: Int)
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
