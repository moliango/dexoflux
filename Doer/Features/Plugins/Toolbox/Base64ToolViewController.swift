import UIKit

/// Base64 text encode / decode tool hosted inside the Toolbox mini-program.
@MainActor
final class Base64ToolViewController: UIViewController, UITextViewDelegate {
    private var mode: Base64Codec.Mode = .standard

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        return view
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        return stack
    }()

    private lazy var modeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            String(localized: "toolbox.base64.mode.standard", defaultValue: "标准"),
            String(localized: "toolbox.base64.mode.url_safe", defaultValue: "URL Safe"),
        ])
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        return control
    }()

    private let inputCard = makeCard()
    private let outputCard = makeCard()

    private lazy var inputTextView: UITextView = makeTextView(
        placeholder: String(
            localized: "toolbox.base64.input.placeholder",
            defaultValue: "在此输入要编码或解码的文本…"
        )
    )

    private lazy var outputTextView: UITextView = {
        let view = makeTextView(
            placeholder: String(
                localized: "toolbox.base64.output.placeholder",
                defaultValue: "结果会显示在这里"
            )
        )
        view.isEditable = false
        return view
    }()

    private lazy var inputPlaceholderLabel = makePlaceholderLabel(for: inputTextView)
    private lazy var outputPlaceholderLabel = makePlaceholderLabel(for: outputTextView)

    private lazy var encodeButton = makePrimaryButton(
        title: String(localized: "toolbox.base64.action.encode", defaultValue: "编码"),
        action: #selector(encodeTapped)
    )
    private lazy var decodeButton = makePrimaryButton(
        title: String(localized: "toolbox.base64.action.decode", defaultValue: "解码"),
        action: #selector(decodeTapped)
    )

    private lazy var pasteButton = makeSecondaryButton(
        title: String(localized: "toolbox.base64.action.paste", defaultValue: "粘贴"),
        action: #selector(pasteTapped)
    )
    private lazy var copyButton = makeSecondaryButton(
        title: String(localized: "toolbox.base64.action.copy", defaultValue: "复制结果"),
        action: #selector(copyTapped)
    )
    private lazy var swapButton = makeSecondaryButton(
        title: String(localized: "toolbox.base64.action.swap", defaultValue: "互换"),
        action: #selector(swapTapped)
    )
    private lazy var clearButton = makeSecondaryButton(
        title: String(localized: "toolbox.base64.action.clear", defaultValue: "清空"),
        action: #selector(clearTapped)
    )

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = " "
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "toolbox.tool.base64.title", defaultValue: "Base64")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: self,
            action: #selector(dismissKeyboard)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(
            localized: "toolbox.base64.action.dismiss_keyboard",
            defaultValue: "收起键盘"
        )

        buildLayout()
        refreshPlaceholders()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Layout

    private func buildLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let inputHeader = makeSectionHeader(
            String(localized: "toolbox.base64.section.input", defaultValue: "输入")
        )
        let outputHeader = makeSectionHeader(
            String(localized: "toolbox.base64.section.output", defaultValue: "结果")
        )

        inputCard.addSubview(inputTextView)
        inputCard.addSubview(inputPlaceholderLabel)
        outputCard.addSubview(outputTextView)
        outputCard.addSubview(outputPlaceholderLabel)

        let actionRow = UIStackView(arrangedSubviews: [encodeButton, decodeButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 10
        actionRow.distribution = .fillEqually

        let utilityRow = UIStackView(arrangedSubviews: [pasteButton, copyButton, swapButton, clearButton])
        utilityRow.axis = .horizontal
        utilityRow.spacing = 8
        utilityRow.distribution = .fillEqually

        contentStack.addArrangedSubview(modeControl)
        contentStack.addArrangedSubview(inputHeader)
        contentStack.addArrangedSubview(inputCard)
        contentStack.addArrangedSubview(actionRow)
        contentStack.addArrangedSubview(utilityRow)
        contentStack.addArrangedSubview(outputHeader)
        contentStack.addArrangedSubview(outputCard)
        contentStack.addArrangedSubview(statusLabel)

        contentStack.setCustomSpacing(8, after: inputHeader)
        contentStack.setCustomSpacing(8, after: outputHeader)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            inputTextView.topAnchor.constraint(equalTo: inputCard.topAnchor, constant: 10),
            inputTextView.leadingAnchor.constraint(equalTo: inputCard.leadingAnchor, constant: 12),
            inputTextView.trailingAnchor.constraint(equalTo: inputCard.trailingAnchor, constant: -12),
            inputTextView.bottomAnchor.constraint(equalTo: inputCard.bottomAnchor, constant: -10),
            inputTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),

            inputPlaceholderLabel.topAnchor.constraint(equalTo: inputTextView.topAnchor, constant: 8),
            inputPlaceholderLabel.leadingAnchor.constraint(equalTo: inputTextView.leadingAnchor, constant: 5),
            inputPlaceholderLabel.trailingAnchor.constraint(equalTo: inputTextView.trailingAnchor, constant: -5),

            outputTextView.topAnchor.constraint(equalTo: outputCard.topAnchor, constant: 10),
            outputTextView.leadingAnchor.constraint(equalTo: outputCard.leadingAnchor, constant: 12),
            outputTextView.trailingAnchor.constraint(equalTo: outputCard.trailingAnchor, constant: -12),
            outputTextView.bottomAnchor.constraint(equalTo: outputCard.bottomAnchor, constant: -10),
            outputTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),

            outputPlaceholderLabel.topAnchor.constraint(equalTo: outputTextView.topAnchor, constant: 8),
            outputPlaceholderLabel.leadingAnchor.constraint(equalTo: outputTextView.leadingAnchor, constant: 5),
            outputPlaceholderLabel.trailingAnchor.constraint(equalTo: outputTextView.trailingAnchor, constant: -5),

            encodeButton.heightAnchor.constraint(equalToConstant: 44),
            decodeButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        mode = modeControl.selectedSegmentIndex == 1 ? .urlSafe : .standard
        setStatus(
            String(
                localized: "toolbox.base64.status.mode",
                defaultValue: "已切换模式，请重新编码或解码"
            ),
            isError: false
        )
    }

    @objc private func encodeTapped() {
        dismissKeyboard()
        let input = inputTextView.text ?? ""
        guard !input.isEmpty else {
            setStatus(
                String(localized: "toolbox.base64.error.empty", defaultValue: "请输入内容"),
                isError: true
            )
            return
        }
        let encoded = Base64Codec.encode(input, mode: mode)
        outputTextView.text = encoded
        refreshPlaceholders()
        setStatus(
            String(
                localized: "toolbox.base64.status.encoded",
                defaultValue: "编码完成 · \(encoded.count) 字符"
            ),
            isError: false
        )
    }

    @objc private func decodeTapped() {
        dismissKeyboard()
        switch Base64Codec.decode(inputTextView.text ?? "", mode: mode) {
        case .success(let text):
            outputTextView.text = text
            refreshPlaceholders()
            setStatus(
                String(
                    localized: "toolbox.base64.status.decoded",
                    defaultValue: "解码完成 · \(text.count) 字符"
                ),
                isError: false
            )
        case .failure(let error):
            setStatus(error.localizedDescription, isError: true)
        }
    }

    @objc private func pasteTapped() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            setStatus(
                String(localized: "toolbox.base64.status.clipboard_empty", defaultValue: "剪贴板为空"),
                isError: true
            )
            return
        }
        inputTextView.text = text
        refreshPlaceholders()
        setStatus(
            String(localized: "toolbox.base64.status.pasted", defaultValue: "已从剪贴板粘贴"),
            isError: false
        )
    }

    @objc private func copyTapped() {
        let text = (outputTextView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            setStatus(
                String(localized: "toolbox.base64.status.no_result", defaultValue: "没有可复制的结果"),
                isError: true
            )
            return
        }
        UIPasteboard.general.string = text
        DexoFeedback.presentToast(
            String(localized: "toolbox.base64.status.copied", defaultValue: "已复制结果"),
            on: self
        )
        setStatus(
            String(localized: "toolbox.base64.status.copied", defaultValue: "已复制结果"),
            isError: false
        )
    }

    @objc private func swapTapped() {
        let input = inputTextView.text ?? ""
        let output = outputTextView.text ?? ""
        inputTextView.text = output
        outputTextView.text = input
        refreshPlaceholders()
        setStatus(
            String(localized: "toolbox.base64.status.swapped", defaultValue: "已互换输入与结果"),
            isError: false
        )
    }

    @objc private func clearTapped() {
        inputTextView.text = ""
        outputTextView.text = ""
        refreshPlaceholders()
        setStatus(
            String(localized: "toolbox.base64.status.cleared", defaultValue: "已清空"),
            isError: false
        )
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        refreshPlaceholders()
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
            let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        let converted = view.convert(frame, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        let inset = UIEdgeInsets(top: 0, left: 0, bottom: overlap, right: 0)
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset = inset
            self.scrollView.scrollIndicatorInsets = inset
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset = .zero
            self.scrollView.scrollIndicatorInsets = .zero
        }
    }

    // MARK: - Helpers

    private func setStatus(_ text: String, isError: Bool) {
        statusLabel.text = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabel
    }

    private func refreshPlaceholders() {
        inputPlaceholderLabel.isHidden = !(inputTextView.text ?? "").isEmpty
        outputPlaceholderLabel.isHidden = !(outputTextView.text ?? "").isEmpty
    }

    private static func makeCard() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        return view
    }

    private func makeTextView(placeholder: String) -> UITextView {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        view.textColor = .label
        view.tintColor = .systemIndigo
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.delegate = self
        view.accessibilityLabel = placeholder
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        return view
    }

    private func makePlaceholderLabel(for textView: UITextView) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = textView.accessibilityLabel
        label.font = .systemFont(ofSize: 15)
        label.textColor = .placeholderText
        label.numberOfLines = 0
        label.isUserInteractionEnabled = false
        return label
    }

    private func makeSectionHeader(_ title: String) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title.uppercased()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        return label
    }

    private func makePrimaryButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemIndigo
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeSecondaryButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.setTitleColor(.systemIndigo, for: .normal)
        button.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.12)
        button.layer.cornerRadius = 10
        button.layer.cornerCurve = .continuous
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
}
