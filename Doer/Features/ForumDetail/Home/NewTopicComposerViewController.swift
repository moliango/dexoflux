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
    // Panel state shared via ComposerPanelKind

    private let api: DiscourseAPI
    private let categories: [DiscourseCategory]
    private let categoriesById: [Int: DiscourseCategory]
    private var selectedCategoryId: Int?
    private var selectedTags: [String]
    private let initialTitle: String
    private let initialRaw: String

    private var currentPanel: ComposerPanelKind = .none
    private var hasLoadedForumEmojis = false
    private var isPreviewingMarkdown = false
    private var isUploading = false
    private var isSubmitting = false
    private var draftSaveTask: Task<Void, Never>?
    private var serverDraftSaveTask: Task<Void, Never>?
    private var panelHeightConstraint: NSLayoutConstraint?
    private let markdownCoordinator = ComposerMarkdownCoordinator()
    
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

    private let emojiToggleButton = ComposerToolbarFactory.makeCircleButton(
        systemName: "face.smiling",
        accessibilityLabel: String(localized: "reply.toolbar.emoji")
    )
    private let previewToggleButton = ComposerToolbarFactory.makePlainButton(
        systemName: "eye",
        accessibilityLabel: String(localized: "reply.toolbar.preview")
    )
    private let toolsToggleButton = ComposerToolbarFactory.makePlainButton(
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

    private lazy var emojiPickerView: EmojiStickerPanelView = {
        let picker = EmojiStickerPanelView()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onEmojiSelected = { [weak self] emoji in
            self?.composerInsertRaw(emoji)
        }
        picker.onStickerMarkdownSelected = { [weak self] markdown in
            self?.composerInsertRaw(markdown + "\n")
        }
        return picker
    }()

    private lazy var toolsPanelView: ComposerToolPanelView = {
        let panel = ComposerToolPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.onToolSelected = { [weak self] tool in
            self?.markdownCoordinator.handleTool(tool)
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
        emojiPickerView.presentingViewController = self

        // Explicit initial (server draft) wins; otherwise restore local autosave.
        let hasExplicitInitial = !initialTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !initialRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasExplicitInitial {
            titleField.text = initialTitle
            textView.text = initialRaw
        } else if let draft = ComposerLocalDraftStore.loadNewTopic(baseURL: api.baseURL) {
            titleField.text = draft.title
            textView.text = draft.raw
            if let categoryId = draft.categoryId {
                selectedCategoryId = categoryId
            }
            if !draft.tags.isEmpty {
                selectedTags = Self.normalizedTags(draft.tags)
            }
        } else {
            titleField.text = initialTitle
            textView.text = initialRaw
        }
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(textInputsChanged), for: .editingChanged)
        textView.delegate = self
        markdownCoordinator.surface = self
        categoryButton.addTarget(self, action: #selector(categoryButtonPressed), for: .touchDown)
        emojiToggleButton.addTarget(self, action: #selector(toggleEmojiPicker), for: .touchUpInside)
        previewToggleButton.addTarget(self, action: #selector(toggleMarkdownPreview), for: .touchUpInside)
        toolsToggleButton.addTarget(self, action: #selector(toggleToolsPanel), for: .touchUpInside)

        updateCategoryButton()
        rebuildTags()
        updateEditorState()

        if !hasExplicitInitial {
            Task { await hydrateServerDraftIfNeeded() }
        }
    }

    /// FluxDo parity: pull `new_topic` server draft when local composer is empty.
    private func hydrateServerDraftIfNeeded() async {
        let localTitle = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let localRaw = (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Local draft already restored — still refresh sequence from server.
        do {
            guard let server = try await api.fetchDraft(key: "new_topic") else { return }
            ComposerLocalDraftStore.saveSequence(
                baseURL: api.baseURL,
                draftKey: "new_topic",
                sequence: server.sequence
            )
            let serverTitle = server.data.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let serverRaw = server.data.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard localTitle.isEmpty, localRaw.isEmpty else { return }
            guard !serverTitle.isEmpty || !serverRaw.isEmpty else { return }
            titleField.text = server.data.title ?? ""
            textView.text = server.data.reply ?? ""
            if let categoryId = server.data.categoryId {
                selectedCategoryId = categoryId
            }
            if !server.data.tags.isEmpty {
                selectedTags = Self.normalizedTags(server.data.tags)
            }
            ComposerLocalDraftStore.saveNewTopic(
                baseURL: api.baseURL,
                title: server.data.title ?? "",
                raw: server.data.reply ?? "",
                categoryId: server.data.categoryId,
                tags: server.data.tags
            )
            updateCategoryButton()
            rebuildTags()
            updateEditorState()
        } catch {
            // Offline / CF — local draft remains.
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if titleField.text?.isEmpty != false {
            titleField.becomeFirstResponder()
        } else {
            textView.becomeFirstResponder()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        draftSaveTask?.cancel()
        serverDraftSaveTask?.cancel()
        // Successful create already cleared drafts — don't re-save the posted body on dismiss.
        guard !isSubmitting else { return }
        persistLocalDraftImmediately()
    }

    private func scheduleLocalDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persistLocalDraftOnly()
        }
        serverDraftSaveTask?.cancel()
        serverDraftSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.persistServerDraft()
        }
    }

    private func persistLocalDraftImmediately() {
        draftSaveTask?.cancel()
        serverDraftSaveTask?.cancel()
        persistLocalDraftOnly()
        persistServerDraft()
    }

    private func persistLocalDraftOnly() {
        ComposerLocalDraftStore.saveNewTopic(
            baseURL: api.baseURL,
            title: titleField.text ?? "",
            raw: textView.text ?? "",
            categoryId: selectedCategoryId,
            tags: selectedTags
        )
    }

    private func persistServerDraft() {
        let title = titleField.text ?? ""
        let raw = textView.text ?? ""
        let categoryId = selectedCategoryId
        let tags = selectedTags
        let api = self.api
        Task {
            await ComposerServerDraftSync.syncNewTopic(
                api: api,
                title: title,
                raw: raw,
                categoryId: categoryId,
                tags: tags
            )
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
        ComposerToolbarFactory.installToolbarLayout(
            in: toolbarContainer,
            emojiButton: emojiToggleButton,
            uploadStatusLabel: uploadStatusLabel,
            rightPill: rightToolbarPill,
            previewButton: previewToggleButton,
            toolsButton: toolsToggleButton
        )
    }

    private func setupCustomPanel() {
        panelHeightConstraint = ComposerToolbarFactory.installPanelLayout(
            in: customPanelContainer,
            emojiPanel: emojiPickerView,
            toolsPanel: toolsPanelView
        )
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
        scheduleLocalDraftSave()
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

    private func setPanel(_ panel: ComposerPanelKind) {
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
            panelHeightConstraint?.constant = ComposerToolbarFactory.customPanelHeight
            loadForumEmojis()
        case .tools:
            textView.resignFirstResponder()
            emojiPickerView.isHidden = true
            toolsPanelView.isHidden = false
            panelHeightConstraint?.constant = ComposerToolbarFactory.customPanelHeight
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
        ComposerToolbarFactory.updateToolbarTints(
            emojiButton: emojiToggleButton,
            previewButton: previewToggleButton,
            toolsButton: toolsToggleButton,
            panel: currentPanel,
            isPreviewing: isPreviewingMarkdown
        )
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
        draftSaveTask?.cancel()
        serverDraftSaveTask?.cancel()
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
                ComposerLocalDraftStore.clearNewTopic(baseURL: api.baseURL)
                let api = self.api
                await ComposerServerDraftSync.clearServerDraft(api: api, draftKey: "new_topic")
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
                alert.addAction(UIAlertAction(
                    title: String(localized: "common.retry", defaultValue: "重试"),
                    style: .default
                ) { [weak self] _ in
                    self?.sendTapped()
                })
                alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .cancel))
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
        scheduleLocalDraftSave()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        if currentPanel != .none { closePanel(returnToKeyboard: false) }
    }
}


// MARK: - ComposerTextSurface

extension NewTopicComposerViewController: ComposerTextSurface {
    var composerHostViewController: UIViewController { self }
    var composerAPI: DiscourseAPI { api }
    var composerTextView: UITextView { textView }
    var composerToolsAnchorView: UIView { toolsToggleButton }
    var composerIsUploading: Bool { isUploading }
    var composerRawText: String { textView.text ?? "" }

    func composerSelectedRawText() -> String {
        ComposerPlainTextEditing.selectedText(in: textView)
    }

    func composerInsertRaw(_ text: String) {
        ComposerPlainTextEditing.replaceSelection(in: textView, with: text)
        updateEditorState()
        scheduleLocalDraftSave()
    }

    func composerWrapSelection(start: String, end: String, placeholder: String) {
        ComposerPlainTextEditing.wrapSelection(in: textView, start: start, end: end, placeholder: placeholder)
        updateEditorState()
        scheduleLocalDraftSave()
    }

    func composerApplyLinePrefix(_ prefix: String) {
        ComposerPlainTextEditing.applyLinePrefix(in: textView, prefix: prefix)
        updateEditorState()
        scheduleLocalDraftSave()
    }

    func composerReplaceFullRaw(_ raw: String) {
        textView.text = raw
        updateEditorState()
        scheduleLocalDraftSave()
    }

    func composerDidEditContent() {
        updateEditorState()
        scheduleLocalDraftSave()
    }

    func composerSetUploading(_ uploading: Bool, statusText: String?) {
        isUploading = uploading
        uploadStatusLabel.text = statusText
        uploadStatusLabel.isHidden = !uploading
        textView.isEditable = !uploading
        titleField.isEnabled = !uploading
        categoryButton.isEnabled = !uploading
        toolsPanelView.isUploading = uploading
        updateEditorState()
    }

    func composerCloseToolPanel(returnToKeyboard: Bool) {
        closePanel(returnToKeyboard: returnToKeyboard)
    }

    func composerExitMarkdownPreviewIfNeeded() {
        guard isPreviewingMarkdown else { return }
        isPreviewingMarkdown = false
        textView.isHidden = false
        previewView.isHidden = true
        updateToolbarState()
        updateEditorState()
    }
}

