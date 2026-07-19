import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct NewTopicSubmission: Equatable {
    let title: String
    let raw: String
    let categoryId: Int?
    let tags: [String]

    static func make(title: String, raw: String, categoryId: Int?, tags: [String]) -> NewTopicSubmission? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !raw.isEmpty else { return nil }

        var seen = Set<String>()
        let tags = tags.compactMap { value -> String? in
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty else { return nil }
            let key = tag.lowercased()
            return seen.insert(key).inserted ? tag : nil
        }
        return NewTopicSubmission(title: title, raw: raw, categoryId: categoryId, tags: tags)
    }
}

final class NewTopicComposerViewController: UIViewController {
    private enum ComposerPanel {
        case none
        case emoji
        case tools
    }

    private static let customPanelHeight: CGFloat = 300

    private let api: DiscourseAPI
    private let categories: [DiscourseCategory]
    private let categoriesById: [Int: DiscourseCategory]
    private var selectedCategoryId: Int?
    private var selectedTags: [String]
    private let initialTitle: String
    private let initialRaw: String

    private var currentPanel: ComposerPanel = .none
    private var hasLoadedForumEmojis = false
    private var isPreviewingMarkdown = false
    private var isUploading = false
    private var isSubmitting = false
    private var panelHeightConstraint: NSLayoutConstraint?

    var onTopicCreated: ((Int) -> Void)?

    private let titleField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = String(localized: "new_topic.title.placeholder")
        field.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 25, weight: .bold))
        field.adjustsFontForContentSizeCategory = true
        field.borderStyle = .none
        field.returnKeyType = .next
        field.clearButtonMode = .whileEditing
        return field
    }()

    private let metadataStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        return stack
    }()

    private let categoryButton: UIButton = {
        let button = UIButton(configuration: .plain())
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true
        return button
    }()

    private let tagsScrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.showsHorizontalScrollIndicator = false
        return view
    }()

    private let tagsStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        return stack
    }()

    private let metadataSeparator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator.withAlphaComponent(0.55)
        return view
    }()

    private let characterCountLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        return label
    }()

    private let textView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 18, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 14, left: 20, bottom: 18, right: 20)
        view.backgroundColor = .systemBackground
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        return view
    }()

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "new_topic.body.placeholder")
        label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 18, weight: .regular))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .placeholderText
        label.numberOfLines = 0
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

    private let emojiToggleButton = NewTopicComposerViewController.makeCircleToolbarButton(
        systemName: "face.smiling",
        accessibilityLabel: String(localized: "reply.toolbar.emoji")
    )
    private let previewToggleButton = NewTopicComposerViewController.makePlainToolbarButton(
        systemName: "eye",
        accessibilityLabel: String(localized: "reply.toolbar.preview")
    )
    private let toolsToggleButton = NewTopicComposerViewController.makePlainToolbarButton(
        systemName: "plus.circle.fill",
        accessibilityLabel: String(localized: "reply.toolbar.more_tools")
    )

    private let rightToolbarPill: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.layer.cornerRadius = 22
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let uploadStatusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var emojiPickerView: EmojiPickerView = {
        let picker = EmojiPickerView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onEmojiSelected = { [weak self] emoji in
            self?.replaceSelection(with: emoji)
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

    private lazy var discardButton = UIBarButtonItem(
        title: String(localized: "reply.discard"),
        style: .plain,
        target: self,
        action: #selector(discardTapped)
    )

    private lazy var publishButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "new_topic.publish", defaultValue: "发布")
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = AppSettings.shared.themeStyle.accentColor
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 15, weight: .semibold)
            return attributes
        }
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        return button
    }()

    init(
        api: DiscourseAPI,
        categories: [DiscourseCategory],
        initialCategoryId: Int?,
        initialTitle: String = "",
        initialRaw: String = "",
        initialTags: [String] = []
    ) {
        self.api = api
        self.categories = categories
        self.categoriesById = DiscourseCategory.indexedById(from: categories)
        self.selectedCategoryId = initialCategoryId
        self.selectedTags = Self.normalizedTags(initialTags)
        self.initialTitle = initialTitle
        self.initialRaw = initialRaw
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "new_topic.title")
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.left"),
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: publishButton), discardButton]

        setupHierarchy()
        setupConstraints()
        setupToolbar()
        setupCustomPanel()

        titleField.text = initialTitle
        textView.text = initialRaw
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(textInputsChanged), for: .editingChanged)
        textView.delegate = self
        categoryButton.addTarget(self, action: #selector(categoryButtonPressed), for: .touchDown)
        emojiToggleButton.addTarget(self, action: #selector(toggleEmojiPicker), for: .touchUpInside)
        previewToggleButton.addTarget(self, action: #selector(toggleMarkdownPreview), for: .touchUpInside)
        toolsToggleButton.addTarget(self, action: #selector(toggleToolsPanel), for: .touchUpInside)

        updateCategoryButton()
        rebuildTags()
        updateEditorState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if titleField.text?.isEmpty != false {
            titleField.becomeFirstResponder()
        } else {
            textView.becomeFirstResponder()
        }
    }

    private func setupHierarchy() {
        view.addSubview(titleField)
        view.addSubview(metadataStack)
        metadataStack.addArrangedSubview(categoryButton)
        metadataStack.addArrangedSubview(tagsScrollView)
        tagsScrollView.addSubview(tagsStack)
        view.addSubview(metadataSeparator)
        view.addSubview(characterCountLabel)
        view.addSubview(textView)
        view.addSubview(previewView)
        view.addSubview(placeholderLabel)
        view.addSubview(bottomStackView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            titleField.heightAnchor.constraint(greaterThanOrEqualToConstant: 42),

            metadataStack.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 14),
            metadataStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            metadataStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tagsScrollView.widthAnchor.constraint(equalTo: metadataStack.widthAnchor),
            tagsScrollView.heightAnchor.constraint(equalToConstant: 42),
            tagsStack.topAnchor.constraint(equalTo: tagsScrollView.contentLayoutGuide.topAnchor),
            tagsStack.leadingAnchor.constraint(equalTo: tagsScrollView.contentLayoutGuide.leadingAnchor),
            tagsStack.trailingAnchor.constraint(equalTo: tagsScrollView.contentLayoutGuide.trailingAnchor),
            tagsStack.bottomAnchor.constraint(equalTo: tagsScrollView.contentLayoutGuide.bottomAnchor),
            tagsStack.heightAnchor.constraint(equalTo: tagsScrollView.frameLayoutGuide.heightAnchor),

            metadataSeparator.topAnchor.constraint(equalTo: metadataStack.bottomAnchor, constant: 16),
            metadataSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            metadataSeparator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            metadataSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            characterCountLabel.topAnchor.constraint(equalTo: metadataSeparator.bottomAnchor, constant: 8),
            characterCountLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            textView.topAnchor.constraint(equalTo: characterCountLabel.bottomAnchor, constant: 2),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor),

            previewView.topAnchor.constraint(equalTo: textView.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            previewView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 14),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 24),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -20),

            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStackView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
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

            uploadStatusLabel.leadingAnchor.constraint(equalTo: emojiToggleButton.trailingAnchor, constant: 12),
            uploadStatusLabel.trailingAnchor.constraint(equalTo: rightToolbarPill.leadingAnchor, constant: -12),
            uploadStatusLabel.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),

            rightToolbarPill.trailingAnchor.constraint(equalTo: toolbarContainer.trailingAnchor, constant: -24),
            rightToolbarPill.centerYAnchor.constraint(equalTo: toolbarContainer.centerYAnchor),
            rightToolbarPill.heightAnchor.constraint(equalToConstant: 44),

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
        let height = customPanelContainer.heightAnchor.constraint(equalToConstant: 0)
        panelHeightConstraint = height
        NSLayoutConstraint.activate([
            height,
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

    private static func makeCircleToolbarButton(systemName: String, accessibilityLabel: String) -> UIButton {
        let button = makePlainToolbarButton(systemName: systemName, accessibilityLabel: accessibilityLabel)
        button.backgroundColor = .secondarySystemGroupedBackground
        button.layer.cornerRadius = 22
        button.layer.cornerCurve = .continuous
        return button
    }

    private static func makePlainToolbarButton(systemName: String, accessibilityLabel: String) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(
            UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)),
            for: .normal
        )
        button.tintColor = .label
        button.accessibilityLabel = accessibilityLabel
        return button
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { value in
            let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tag.isEmpty, seen.insert(tag.lowercased()).inserted else { return nil }
            return tag
        }
    }

    private func parentCategory(for category: DiscourseCategory) -> DiscourseCategory? {
        category.parentCategoryId.flatMap { categoriesById[$0] }
    }

    private func updateCategoryButton() {
        let selected = selectedCategoryId.flatMap { categoriesById[$0] }
        var configuration = UIButton.Configuration.plain()
        configuration.title = selected.map { $0.displayName(parent: parentCategory(for: $0)) }
            ?? String(localized: "new_topic.category.none")
        configuration.image = UIImage(systemName: "square.grid.2x2")
        configuration.imagePadding = 8
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13)
        configuration.background.backgroundColor = .secondarySystemGroupedBackground
        configuration.background.cornerRadius = 11
        configuration.baseForegroundColor = selected == nil ? .secondaryLabel : .label
        categoryButton.configuration = configuration
        categoryButton.menu = UIMenu(children: categoryMenuElements())
    }

    private func categoryMenuElements() -> [UIMenuElement] {
        var items: [UIMenuElement] = [
            UIAction(
                title: String(localized: "new_topic.category.none"),
                state: selectedCategoryId == nil ? .on : .off
            ) { [weak self] _ in
                self?.selectedCategoryId = nil
                self?.updateCategoryButton()
            },
        ]
        for category in categories {
            items.append(categoryAction(category))
            category.subcategoryList?.forEach { items.append(categoryAction($0, prefix: "  ")) }
        }
        return items
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

    private func rebuildTags() {
        tagsStack.arrangedSubviews.forEach { view in
            tagsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        selectedTags.forEach { tag in
            var configuration = UIButton.Configuration.tinted()
            configuration.title = "#(tag)"
            configuration.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold))
            configuration.imagePlacement = .trailing
            configuration.imagePadding = 6
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = AppSettings.shared.themeStyle.accentColor
            let button = UIButton(configuration: configuration)
            button.accessibilityLabel = String(format: String(localized: "new_topic.tags.remove_format", defaultValue: "移除标签 %@"), tag)
            button.addAction(UIAction { [weak self] _ in
                self?.selectedTags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                self?.rebuildTags()
            }, for: .touchUpInside)
            tagsStack.addArrangedSubview(button)
        }

        var addConfiguration = UIButton.Configuration.plain()
        addConfiguration.title = String(localized: "new_topic.tags.add", defaultValue: "添加标签")
        addConfiguration.image = UIImage(systemName: "plus")
        addConfiguration.imagePadding = 6
        addConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        addConfiguration.background.strokeColor = .separator
        addConfiguration.background.strokeWidth = 1
        addConfiguration.background.cornerRadius = 10
        let addButton = UIButton(configuration: addConfiguration)
        addButton.addTarget(self, action: #selector(addTagTapped), for: .touchUpInside)
        tagsStack.addArrangedSubview(addButton)
    }

    @objc private func categoryButtonPressed() {
        closePanel(returnToKeyboard: false)
    }

    @objc private func addTagTapped() {
        closePanel(returnToKeyboard: false)
        let picker = TagPickerViewController(api: api, categoryId: selectedCategoryId, selectedTag: nil)
        picker.onTagSelected = { [weak self] tag in
            guard let self, let tag else { return }
            guard !selectedTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) else { return }
            selectedTags.append(tag)
            rebuildTags()
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    @objc private func textInputsChanged() {
        updateEditorState()
    }

    private func updateEditorState() {
        placeholderLabel.isHidden = isPreviewingMarkdown || !textView.text.isEmpty
        characterCountLabel.text = String(
            format: String(localized: "new_topic.character_count_format", defaultValue: "%lld 字符"),
            Int64(textView.text.count)
        )
        let submission = NewTopicSubmission.make(
            title: titleField.text ?? "",
            raw: textView.text,
            categoryId: selectedCategoryId,
            tags: selectedTags
        )
        publishButton.isEnabled = submission != nil && !isUploading && !isSubmitting
        publishButton.alpha = publishButton.isEnabled ? 1 : 0.55
        discardButton.isEnabled = !isUploading && !isSubmitting
        if isPreviewingMarkdown {
            previewView.update(markdown: textView.text)
        }
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
            previewView.update(markdown: textView.text)
        } else {
            textView.becomeFirstResponder()
        }
        textView.isHidden = isPreviewingMarkdown
        previewView.isHidden = !isPreviewingMarkdown
        updateToolbarState()
        updateEditorState()
    }

    private func setPanel(_ panel: ComposerPanel) {
        if isPreviewingMarkdown {
            isPreviewingMarkdown = false
            textView.isHidden = false
            previewView.isHidden = true
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
        DexoMotion.animate(duration: DexoMotion.short) { self.view.layoutIfNeeded() }
    }

    private func closePanel(returnToKeyboard: Bool) {
        guard currentPanel != .none else { return }
        currentPanel = .none
        emojiPickerView.isHidden = true
        toolsPanelView.isHidden = true
        panelHeightConstraint?.constant = 0
        updateToolbarState()
        if returnToKeyboard { textView.becomeFirstResponder() }
        DexoMotion.animate(duration: DexoMotion.quick) { self.view.layoutIfNeeded() }
    }

    private func updateToolbarState() {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        previewToggleButton.setImage(UIImage(systemName: isPreviewingMarkdown ? "eye.slash.fill" : "eye", withConfiguration: config), for: .normal)
        previewToggleButton.tintColor = isPreviewingMarkdown ? .systemBlue : .label
        toolsToggleButton.tintColor = currentPanel == .tools ? .systemBlue : .label
        emojiToggleButton.tintColor = currentPanel == .emoji ? .systemBlue : .label
    }

    private func loadForumEmojis() {
        guard !hasLoadedForumEmojis else { return }
        hasLoadedForumEmojis = true
        emojiPickerView.showLoading()
        Task {
            do {
                let groups = try await api.fetchEmojiGroups()
                emojiPickerView.setEmojiGroups(groups, baseURL: api.baseURL)
            } catch {
                emojiPickerView.showError()
            }
        }
    }

    private func handleTool(_ tool: ComposerMarkdownTool) {
        guard !isUploading else { return }
        switch tool {
        case .image: pickImages()
        case .attachment: pickAttachment()
        case .heading: chooseHeading()
        case .bold: wrapSelection(start: "**", end: "**", placeholder: String(localized: "reply.tool.placeholder.bold"))
        case .italic: wrapSelection(start: "*", end: "*", placeholder: String(localized: "reply.tool.placeholder.italic"))
        case .strikethrough: wrapSelection(start: "~~", end: "~~", placeholder: String(localized: "reply.tool.placeholder.strikethrough"))
        case .bulletList: applyLinePrefix("- ")
        case .numberedList: applyLinePrefix("1. ")
        case .link: insertLink()
        case .quote: applyLinePrefix("> ")
        case .note: replaceSelection(with: "\n> [!note]\n> \(String(localized: "reply.tool.placeholder.note"))\n")
        case .template: insertTemplate()
        }
        if tool.closesPanelAfterAction { closePanel(returnToKeyboard: true) }
    }

    private func replaceSelection(with text: String) {
        guard let range = Range(textView.selectedRange, in: textView.text) else { return }
        textView.text.replaceSubrange(range, with: text)
        if let end = textView.position(from: textView.beginningOfDocument, offset: textView.selectedRange.location + text.utf16.count) {
            textView.selectedTextRange = textView.textRange(from: end, to: end)
        }
        updateEditorState()
    }

    private func wrapSelection(start: String, end: String, placeholder: String) {
        let selected = textView.selectedTextRange.flatMap { textView.text(in: $0) }
        replaceSelection(with: "\(start)\((selected?.isEmpty == false ? selected : placeholder) ?? placeholder)\(end)")
    }

    private func applyLinePrefix(_ prefix: String) {
        let nsText = textView.text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: min(textView.selectedRange.location, nsText.length), length: 0))
        if nsText.substring(with: lineRange).hasPrefix(prefix) {
            textView.text = nsText.replacingCharacters(in: NSRange(location: lineRange.location, length: prefix.count), with: "")
        } else {
            textView.text = nsText.replacingCharacters(in: NSRange(location: lineRange.location, length: 0), with: prefix)
        }
        updateEditorState()
    }

    private func chooseHeading() {
        let alert = UIAlertController(title: String(localized: "reply.tool.heading"), message: nil, preferredStyle: .actionSheet)
        for level in 1 ... 3 {
            alert.addAction(UIAlertAction(title: "H\(level)", style: .default) { [weak self] _ in
                self?.applyLinePrefix(String(repeating: "#", count: level) + " ")
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func insertLink() {
        let alert = UIAlertController(title: String(localized: "reply.tool.link"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = String(localized: "reply.tool.link_text") }
        alert.addTextField { field in
            field.placeholder = "https://"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "reply.tool.insert"), style: .default) { [weak self, weak alert] _ in
            let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = alert?.textFields?.dropFirst().first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let self, let url, !url.isEmpty else { return }
            replaceSelection(with: "[\((title?.isEmpty == false ? title : url) ?? url)](\(url))")
        })
        present(alert, animated: true)
    }

    private func insertTemplate() {
        let alert = UIAlertController(title: String(localized: "reply.tool.template"), message: nil, preferredStyle: .actionSheet)
        let templates = [
            (String(localized: "reply.template.summary"), "## \(String(localized: "reply.template.summary"))\n\n- \n"),
            (String(localized: "reply.template.steps"), "## \(String(localized: "reply.template.steps"))\n\n1. \n2. \n3. \n"),
            (String(localized: "reply.template.code"), "```\n\(String(localized: "reply.tool.placeholder.code"))\n```\n"),
        ]
        templates.forEach { template in
            alert.addAction(UIAlertAction(title: template.0, style: .default) { [weak self] _ in self?.replaceSelection(with: template.1) })
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func pickImages() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0
        let picker = PHPickerViewController(configuration: configuration)
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
            if files.count > 1 { uploadStatusLabel.text = "\(index + 1)/\(files.count)" }
            do {
                let upload = try await api.uploadComposerFile(fileURL: file.url, filename: file.filename)
                let prefix = textView.text.isEmpty || textView.text.hasSuffix("\n") ? "" : "\n"
                replaceSelection(with: "\(prefix)\(upload.markdown)\n")
            } catch {
                showUploadError(error)
                return
            }
        }
    }

    private func setUploading(_ uploading: Bool, text: String?) {
        isUploading = uploading
        uploadStatusLabel.text = text
        uploadStatusLabel.isHidden = !uploading
        textView.isEditable = !uploading
        titleField.isEnabled = !uploading
        categoryButton.isEnabled = !uploading
        toolsPanelView.isUploading = uploading
        updateEditorState()
    }

    private func showUploadError(_ error: Error) {
        let alert = UIAlertController(title: String(localized: "reply.upload.failed"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }

    @objc private func cancelTapped() {
        discardTapped()
    }

    @objc private func discardTapped() {
        let hasContent = !(titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedTags.isEmpty
        guard hasContent else {
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
        guard !isSubmitting,
              let submission = NewTopicSubmission.make(
                  title: titleField.text ?? "",
                  raw: textView.text,
                  categoryId: selectedCategoryId,
                  tags: selectedTags
              )
        else { return }

        isSubmitting = true
        closePanel(returnToKeyboard: false)
        setSubmissionControlsEnabled(false)
        Task {
            do {
                let response = try await api.createTopic(
                    title: submission.title,
                    raw: submission.raw,
                    categoryId: submission.categoryId,
                    tags: submission.tags
                )
                if response.isEnqueued {
                    presentQueuedAlert()
                    return
                }
                guard let topicId = response.topicId else {
                    throw NSError(
                        domain: "NewTopicComposer",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: String(localized: "new_topic.create.missing_topic")]
                    )
                }
                dismiss(animated: true) { [weak self] in self?.onTopicCreated?(topicId) }
            } catch {
                isSubmitting = false
                setSubmissionControlsEnabled(true)
                let alert = UIAlertController(
                    title: String(localized: "new_topic.create.failed"),
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func setSubmissionControlsEnabled(_ enabled: Bool) {
        titleField.isEnabled = enabled
        textView.isEditable = enabled
        categoryButton.isEnabled = enabled
        tagsStack.isUserInteractionEnabled = enabled
        publishButton.configuration?.showsActivityIndicator = !enabled
        updateEditorState()
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

extension NewTopicComposerViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textView.becomeFirstResponder()
        return true
    }
}

extension NewTopicComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        updateEditorState()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if currentPanel != .none { closePanel(returnToKeyboard: false) }
    }
}

extension NewTopicComposerViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        Task {
            var files: [(url: URL, filename: String)] = []
            for result in results {
                if let file = try? await temporaryImageFile(from: result) { files.append(file) }
            }
            await uploadPickedFiles(files)
        }
    }

    private func temporaryImageFile(from result: PHPickerResult) async throws -> (url: URL, filename: String) {
        let provider = result.itemProvider
        let identifier = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true }
            ?? UTType.image.identifier
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let url else {
                    continuation.resume(throwing: DiscourseAPIError(
                        messages: [String(localized: "reply.upload.failed")],
                        errorType: "upload_failed"
                    ))
                    return
                }
                do {
                    let ext = UTType(identifier)?.preferredFilenameExtension ?? url.pathExtension
                    let cleanExt = ext.isEmpty ? "jpg" : ext
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(cleanExt)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: (destination, "\(provider.suggestedName ?? "image").\(cleanExt)"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension NewTopicComposerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            await uploadPickedFiles([(url, url.lastPathComponent)])
        }
    }
}
