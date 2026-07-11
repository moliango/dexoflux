import UIKit

final class PrivateMessageComposerViewController: UIViewController, UITextViewDelegate, UITextFieldDelegate {
    var onMessageSent: ((DiscourseCreatePostResponse) -> Void)?

    private let api: DiscourseAPI
    private let recipient: String

    private let recipientLabel = UILabel()
    private let titleField = UITextField()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private var isSending = false

    init(api: DiscourseAPI, recipient: String, initialTitle: String = "", initialRaw: String = "") {
        self.api = api
        self.recipient = recipient
        super.init(nibName: nil, bundle: nil)
        titleField.text = initialTitle
        textView.text = initialRaw
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "user.profile.private_message")
        view.backgroundColor = AppSettings.shared.themeStyle.contentBackgroundColor
        setupNavigation()
        setupUI()
        updateSendState()
    }

    private func setupNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "action.cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "reply.send"),
            style: .done,
            target: self,
            action: #selector(sendTapped)
        )
    }

    private func setupUI() {
        recipientLabel.translatesAutoresizingMaskIntoConstraints = false
        recipientLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 13,
            weight: .semibold,
            fallback: .systemFont(ofSize: 13, weight: .semibold)
        )
        recipientLabel.textColor = .secondaryLabel
        recipientLabel.text = "@\(recipient)"

        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.borderStyle = .roundedRect
        titleField.placeholder = String(localized: "new_topic.title.placeholder")
        titleField.returnKeyType = .next
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(inputChanged), for: .editingChanged)

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = AppSettings.shared.contentFont(ofSize: 17)
        textView.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        textView.layer.cornerRadius = 14
        textView.layer.cornerCurve = .continuous
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        textView.delegate = self

        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.font = textView.font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.text = String(localized: "reply.placeholder")
        placeholderLabel.isHidden = !textView.text.isEmpty

        view.addSubview(recipientLabel)
        view.addSubview(titleField)
        view.addSubview(textView)
        textView.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            recipientLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            recipientLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            recipientLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            titleField.topAnchor.constraint(equalTo: recipientLabel.bottomAnchor, constant: 10),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            titleField.heightAnchor.constraint(equalToConstant: 40),

            textView.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 14),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -16),
        ])
    }

    private func updateSendState() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        navigationItem.rightBarButtonItem?.isEnabled = !isSending && !title.isEmpty && !raw.isEmpty
        navigationItem.leftBarButtonItem?.isEnabled = !isSending
        titleField.isEnabled = !isSending
        textView.isEditable = !isSending
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func sendTapped() {
        let messageTitle = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageTitle.isEmpty, !raw.isEmpty, !isSending else { return }

        isSending = true
        updateSendState()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await api.sendPrivateMessage(to: recipient, title: messageTitle, raw: raw)
                dismiss(animated: true) { [onMessageSent] in
                    onMessageSent?(response)
                }
            } catch {
                isSending = false
                updateSendState()
                showError(error)
            }
        }
    }

    @objc private func inputChanged() {
        updateSendState()
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSendState()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textView.becomeFirstResponder()
        return false
    }
}
