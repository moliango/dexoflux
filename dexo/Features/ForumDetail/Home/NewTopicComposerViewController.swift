import UIKit

final class NewTopicComposerViewController: UIViewController {
    private let api: DiscourseAPI
    private let categories: [DiscourseCategory]
    private let categoriesById: [Int: DiscourseCategory]
    private var selectedCategoryId: Int?
    var onTopicCreated: ((Int) -> Void)?

    private let titleField: UITextField = {
        let field = UITextField()
        field.placeholder = String(localized: "new_topic.title.placeholder")
        field.font = .systemFont(ofSize: 18, weight: .semibold)
        field.borderStyle = .none
        field.returnKeyType = .next
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let titleSeparator: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let categoryButton: UIButton = {
        let button = UIButton(configuration: .plain())
        button.showsMenuAsPrimaryAction = true
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let textView: UITextView = {
        let view = UITextView()
        view.font = .systemFont(ofSize: 16)
        view.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 12
        view.layer.cornerCurve = .continuous
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.text = String(localized: "new_topic.body.placeholder")
        label.font = .systemFont(ofSize: 16)
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var sendButton = UIBarButtonItem(
        title: String(localized: "reply.send"),
        style: .done,
        target: self,
        action: #selector(sendTapped)
    )

    init(api: DiscourseAPI, categories: [DiscourseCategory], initialCategoryId: Int?) {
        self.api = api
        self.categories = categories
        self.categoriesById = Self.indexCategories(categories)
        self.selectedCategoryId = initialCategoryId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "new_topic.title")
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "action.cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = sendButton

        view.addSubview(titleField)
        view.addSubview(titleSeparator)
        view.addSubview(categoryButton)
        view.addSubview(textView)
        view.addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            titleField.heightAnchor.constraint(equalToConstant: 36),

            titleSeparator.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 8),
            titleSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            titleSeparator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            categoryButton.topAnchor.constraint(equalTo: titleSeparator.bottomAnchor, constant: 10),
            categoryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            categoryButton.heightAnchor.constraint(equalToConstant: 34),

            textView.topAnchor.constraint(equalTo: categoryButton.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 22),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 17),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -17),
        ])

        titleField.delegate = self
        textView.delegate = self
        updateCategoryButton()
        updateSendButton()
        titleField.addTarget(self, action: #selector(textInputsChanged), for: .editingChanged)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        titleField.becomeFirstResponder()
    }

    private func updateCategoryButton() {
        let selected = selectedCategoryId.flatMap { categoriesById[$0] }
        let title = selected.map { $0.displayName(parent: parentCategory(for: $0)) }
            ?? String(localized: "new_topic.category.none")
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        config.imagePlacement = .trailing
        config.imagePadding = 5
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 10)
        config.background.backgroundColor = .secondarySystemGroupedBackground
        config.background.cornerRadius = 9
        config.baseForegroundColor = selectedCategoryId == nil ? .secondaryLabel : .label
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var output = attrs
            output.font = .systemFont(ofSize: 14, weight: .medium)
            return output
        }
        categoryButton.configuration = config
        categoryButton.menu = UIMenu(title: "", children: categoryMenuElements())
    }

    private func categoryMenuElements() -> [UIMenuElement] {
        var elements: [UIMenuElement] = [
            UIAction(
                title: String(localized: "new_topic.category.none"),
                state: selectedCategoryId == nil ? .on : .off
            ) { [weak self] _ in
                self?.selectedCategoryId = nil
                self?.updateCategoryButton()
            },
        ]

        for category in categories {
            elements.append(categoryAction(category))
            if let subs = category.subcategoryList {
                for sub in subs {
                    elements.append(categoryAction(sub, prefix: "  "))
                }
            }
        }
        return elements
    }

    private func categoryAction(_ category: DiscourseCategory, prefix: String = "") -> UIAction {
        UIAction(
            title: prefix + category.displayName(parent: parentCategory(for: category)),
            state: selectedCategoryId == category.id ? .on : .off
        ) { [weak self] _ in
            self?.selectedCategoryId = category.id
            self?.updateCategoryButton()
        }
    }

    private static func indexCategories(_ categories: [DiscourseCategory]) -> [Int: DiscourseCategory] {
        DiscourseCategory.indexedById(from: categories)
    }

    private func parentCategory(for category: DiscourseCategory) -> DiscourseCategory? {
        guard let parentId = category.parentCategoryId else { return nil }
        return categoriesById[parentId]
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    private func updateSendButton() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        sendButton.isEnabled = !title.isEmpty && !body.isEmpty
    }

    @objc private func textInputsChanged() {
        updateSendButton()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func sendTapped() {
        let topicTitle = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !topicTitle.isEmpty, !body.isEmpty else { return }

        sendButton.isEnabled = false
        titleField.isEnabled = false
        textView.isEditable = false
        categoryButton.isEnabled = false

        Task {
            do {
                let response = try await api.createTopic(
                    title: topicTitle,
                    raw: body,
                    categoryId: selectedCategoryId
                )
                guard let topicId = response.topicId else {
                    throw NSError(
                        domain: "NewTopicComposer",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "new_topic.create.missing_topic")]
                    )
                }
                dismiss(animated: true) { [weak self] in
                    self?.onTopicCreated?(topicId)
                }
            } catch {
                sendButton.isEnabled = true
                titleField.isEnabled = true
                textView.isEditable = true
                categoryButton.isEnabled = true
                let alert = UIAlertController(
                    title: String(localized: "new_topic.create.failed"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }
}

extension NewTopicComposerViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textView.becomeFirstResponder()
        return true
    }
}

extension NewTopicComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholder()
        updateSendButton()
    }
}
