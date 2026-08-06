import UIKit
import UniformTypeIdentifiers

enum AppearanceFontOption: Hashable {
    case system
    case miSans
    case importedCustom(String)
    case importCustom
}

enum PendingFontImportTarget: Equatable {
    case miSans
    case custom
}

final class AppearanceSettingsViewController: ObservableViewController {
    private let settings = AppSettings.shared
    private var modeCards: [AppSettings.AppearanceMode: AppearanceModeCardView] = [:]
    private var styleCards: [AppSettings.ThemeStyle: ThemeStyleCardView] = [:]
    private var fontRows: [AppearanceFontOption: AppearanceFontOptionRow] = [:]
    private var sectionIconViews: [UIImageView] = []
    private var sectionHeaderViews: [DataManagementSectionHeaderView] = []
    private let interfaceFontSizeCard = FontScaleCardView()
    private let fontScopeRow = ReadingToggleRowView()
    private let incomingTopicsFloatingRow = ReadingToggleRowView()
    private let miniProgramRow = ReadingToggleRowView()
    private let categoryDrawerSwipeRow = ReadingToggleRowView()
    private let xiaohongshuStaggeredCardsRow = ReadingToggleRowView()
    private let themeTaxonomyColorsRow = ReadingToggleRowView()
    private var renderedLanguage: AppSettings.AppLanguage?
    private var renderedThemeStyle: AppSettings.ThemeStyle?
    private var pendingFontImportTarget: PendingFontImportTarget?

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        return scroll
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 24
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 20, leading: 18, bottom: 28, trailing: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let languageRow = AppearanceLanguageRow()

    override func viewDidLoad() {
        super.viewDidLoad()
        observe(settings)
        title = String(localized: "settings.section.appearance")
        view.backgroundColor = DataManagementPalette.screenBackground
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func updateUI() {
        let currentLanguage = settings.appLanguage
        let currentThemeStyle = settings.themeStyle
        if renderedLanguage != currentLanguage || renderedThemeStyle != currentThemeStyle {
            rebuildContent()
            renderedLanguage = currentLanguage
            renderedThemeStyle = currentThemeStyle
        }
        title = String(localized: "settings.section.appearance")

        let themeStyle = currentThemeStyle
        let accentColor = themeStyle.accentColor
        let pageBackground = DataManagementPalette.screenBackground
        let cardBackground = themeStyle.topicCardBackgroundColor

        view.backgroundColor = pageBackground
        scrollView.backgroundColor = pageBackground
        view.tintColor = accentColor
        sectionIconViews.forEach { $0.tintColor = accentColor }
        sectionHeaderViews.forEach { $0.setTintColor(accentColor) }
        languageRow.configure(
            languageTitle: settings.appLanguage.title,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
        modeCards.forEach { mode, card in
            card.setSelected(
                mode == settings.appearanceMode,
                accentColor: accentColor,
                cardBackgroundColor: cardBackground
            )
        }
        styleCards.forEach { style, card in
            card.setSelected(
                style == themeStyle,
                accentColor: accentColor,
                cardBackgroundColor: cardBackground
            )
        }
        configureFontRows(accentColor: accentColor, backgroundColor: cardBackground)
        interfaceFontSizeCard.configure(
            title: String(localized: "settings.interface_font_size"),
            resetTitle: String(localized: "settings.reading.reset"),
            sliderValue: settings.interfaceFontScalePercent,
            minimumValue: AppSettings.minimumFontScalePercent,
            maximumValue: AppSettings.maximumFontScalePercent,
            defaultValue: AppSettings.defaultInterfaceFontScalePercent,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
        fontScopeRow.configure(
            title: String(localized: "settings.font.scope.global"),
            subtitle: String(localized: "settings.font.scope.global.subtitle"),
            symbolName: "textformat.size",
            isOn: settings.contentFontScope == .global,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
        incomingTopicsFloatingRow.configure(
            title: String(localized: "settings.appearance.incoming_topics_floating"),
            subtitle: String(localized: "settings.appearance.incoming_topics_floating.subtitle"),
            symbolName: "rectangle.topthird.inset.filled",
            isOn: settings.homeIncomingTopicsBannerFloatingEnabled,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
        miniProgramRow.configure(
            title: String(localized: "settings.appearance.mini_programs", defaultValue: "小程序"),
            subtitle: String(
                localized: "settings.appearance.mini_programs.subtitle",
                defaultValue: "在首页显示小程序入口，并启用小程序管理"
            ),
            symbolName: "square.grid.2x2.fill",
            isOn: settings.miniProgramsEnabled,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
        categoryDrawerSwipeRow.configure(
            title: String(localized: "settings.appearance.category_drawer", defaultValue: "分类侧栏"),
            subtitle: String(
                localized: "settings.appearance.category_drawer.subtitle",
                defaultValue: "从左缘右滑打开分类/标签侧栏；开启后隐藏顶部分类条与分类筛选"
            ),
            symbolName: "sidebar.left",
            isOn: settings.homeCategoryDrawerSwipeEnabled,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
        xiaohongshuStaggeredCardsRow.configure(
            title: String(localized: "settings.appearance.xiaohongshu_staggered_cards"),
            subtitle: String(localized: "settings.appearance.xiaohongshu_staggered_cards.subtitle"),
            symbolName: "square.grid.2x2",
            isOn: settings.xiaohongshuCardsStaggered,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
        themeTaxonomyColorsRow.configure(
            title: String(
                localized: "settings.appearance.theme_taxonomy_colors",
                defaultValue: "主题分类/标签色"
            ),
            subtitle: String(
                localized: "settings.appearance.theme_taxonomy_colors.subtitle",
                defaultValue: "开启后分类与标签使用当前主题配色；关闭则保留论坛原始颜色"
            ),
            symbolName: "paintbrush.pointed.fill",
            isOn: settings.themeTaxonomyColorsEnabled,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
    }

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        languageRow.addTarget(self, action: #selector(languageTapped), for: .touchUpInside)
        fontScopeRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.contentFontScope = isOn ? .global : .readingOnly
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        }
        incomingTopicsFloatingRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.homeIncomingTopicsBannerFloatingEnabled = isOn
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        }
        miniProgramRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.miniProgramsEnabled = isOn
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        }
        categoryDrawerSwipeRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.homeCategoryDrawerSwipeEnabled = isOn
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        }

        xiaohongshuStaggeredCardsRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.xiaohongshuCardsStaggered = isOn
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        }
        themeTaxonomyColorsRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.themeTaxonomyColorsEnabled = isOn
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        }
        interfaceFontSizeCard.onValueChanged = { [weak self] value in
            guard let self else { return }
            settings.interfaceFontScalePercent = value
            updateUI()
        }
        interfaceFontSizeCard.onReset = { [weak self] in
            guard let self else { return }
            settings.interfaceFontScalePercent = AppSettings.defaultInterfaceFontScalePercent
            updateUI()
        }
        rebuildContent()
        renderedLanguage = settings.appLanguage
        renderedThemeStyle = settings.themeStyle
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        modeCards.removeAll()
        styleCards.removeAll()
        fontRows.removeAll()
        sectionIconViews.removeAll()
        sectionHeaderViews.removeAll()

        // FluxDO order: Language → Theme mode → Theme color → Font → Home chrome
        // App icon section omitted while only the primary icon ships.
        contentStack.addArrangedSubview(verticalSection(
            title: String(localized: "settings.language"),
            symbolName: "globe",
            body: languageRow
        ))
        contentStack.addArrangedSubview(verticalSection(
            title: String(localized: "settings.appearance.theme_mode"),
            symbolName: "circle.lefthalf.filled",
            body: makeModeGrid()
        ))

        let styleBody = UIStackView()
        styleBody.axis = .vertical
        styleBody.spacing = 12
        styleBody.addArrangedSubview(makeStyleGrid())
        styleBody.addArrangedSubview(themeTaxonomyColorsRow)
        if settings.themeStyle == .xiaohongshu {
            styleBody.addArrangedSubview(xiaohongshuStaggeredCardsRow)
        }
        contentStack.addArrangedSubview(verticalSection(
            title: String(localized: "settings.appearance.theme_colors"),
            symbolName: "paintpalette",
            body: styleBody
        ))

        let fontBody = UIStackView()
        fontBody.axis = .vertical
        fontBody.spacing = 12
        fontBody.addArrangedSubview(interfaceFontSizeCard)
        fontBody.addArrangedSubview(makeFontFamilyHeader())
        fontBody.addArrangedSubview(makeFontOptionsCard())
        fontBody.addArrangedSubview(fontScopeRow)
        contentStack.addArrangedSubview(verticalSection(
            title: String(localized: "settings.appearance.font"),
            symbolName: "textformat",
            body: fontBody
        ))

        let homeBody = UIStackView()
        homeBody.axis = .vertical
        homeBody.spacing = 12
        homeBody.addArrangedSubview(incomingTopicsFloatingRow)
        homeBody.addArrangedSubview(miniProgramRow)
        homeBody.addArrangedSubview(categoryDrawerSwipeRow)
        contentStack.addArrangedSubview(verticalSection(
            title: String(localized: "settings.appearance.home_display"),
            symbolName: "house",
            body: homeBody
        ))
    }

    private func verticalSection(title: String, symbolName: String, body: UIView) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        let header = DataManagementSectionHeaderView(
            title: title,
            symbolName: symbolName,
            tintColor: settings.themeStyle.accentColor
        )
        sectionHeaderViews.append(header)
        stack.addArrangedSubview(header)
        stack.addArrangedSubview(body)
        return stack
    }

    private func makeFontFamilyHeader() -> UILabel {
        let label = UILabel()
        label.text = String(localized: "settings.appearance.font_family", defaultValue: "内容字体")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }

    private func makeModeGrid() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fillEqually
        row.spacing = 12

        for mode in AppSettings.AppearanceMode.allCases {
            let card = AppearanceModeCardView(mode: mode)
            card.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)
            card.heightAnchor.constraint(equalToConstant: 126).isActive = true
            row.addArrangedSubview(card)
            modeCards[mode] = card
        }
        return row
    }

    private func makeStyleGrid() -> UIStackView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 14

        let styles = AppSettings.ThemeStyle.allCases
        let columns = 4
        for start in stride(from: 0, to: styles.count, by: columns) {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.distribution = .fillEqually
            row.spacing = 10

            let rowStyles = Array(styles[start..<min(start + columns, styles.count)])
            for style in rowStyles {
                let card = ThemeStyleCardView(style: style)
                card.addTarget(self, action: #selector(styleTapped(_:)), for: .touchUpInside)
                card.heightAnchor.constraint(equalToConstant: 114).isActive = true
                row.addArrangedSubview(card)
                styleCards[style] = card
            }
            for _ in rowStyles.count..<columns {
                let placeholder = UIView()
                placeholder.isUserInteractionEnabled = false
                row.addArrangedSubview(placeholder)
            }
            grid.addArrangedSubview(row)
        }
        return grid
    }


    private func makeFontOptionsCard() -> UIStackView {
        let card = UIStackView()
        card.axis = .vertical
        card.spacing = 0
        card.backgroundColor = settings.themeStyle.topicCardBackgroundColor
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1.0 / UIScreen.main.scale
        card.layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)

        var options: [AppearanceFontOption] = [.system, .miSans]
        options.append(contentsOf: settings.importedCustomContentFonts.map { .importedCustom($0.id) })
        options.append(.importCustom)

        for option in options {
            let row = AppearanceFontOptionRow(option: option)
            row.addTarget(self, action: #selector(fontFamilyTapped(_:)), for: .touchUpInside)
            card.addArrangedSubview(row)
            fontRows[option] = row
        }
        return card
    }

    private func configureFontRows(accentColor: UIColor, backgroundColor: UIColor) {
        var importedFontsById: [String: AppSettings.ImportedContentFont] = [:]
        settings.importedCustomContentFonts.forEach { font in
            importedFontsById[font.id] = font
        }
        for (option, row) in fontRows {
            switch option {
            case .system:
                row.configure(
                    title: AppSettings.ContentFontFamily.system.title,
                    subtitle: settings.contentFontSubtitle(for: .system),
                    selected: settings.contentFontFamily == .system,
                    available: true,
                    showsUploadIcon: false,
                    showsSelectionControl: true,
                    accentColor: accentColor,
                    backgroundColor: backgroundColor
                )
            case .miSans:
                let available = settings.isContentFontFamilyAvailable(.miSans)
                row.configure(
                    title: AppSettings.ContentFontFamily.miSans.title,
                    subtitle: settings.contentFontSubtitle(for: .miSans),
                    selected: settings.contentFontFamily == .miSans,
                    available: available,
                    showsUploadIcon: !available,
                    showsSelectionControl: true,
                    accentColor: accentColor,
                    backgroundColor: backgroundColor
                )
            case .importedCustom(let fontId):
                guard let font = importedFontsById[fontId] else { continue }
                row.configure(
                    title: font.displayName,
                    subtitle: settings.importedCustomContentFontSubtitle(for: font),
                    selected: settings.contentFontFamily == .custom && settings.selectedImportedCustomContentFont?.id == font.id,
                    available: true,
                    showsUploadIcon: false,
                    showsSelectionControl: true,
                    accentColor: accentColor,
                    backgroundColor: backgroundColor
                )
            case .importCustom:
                row.configure(
                    title: String(localized: "settings.font.custom.add"),
                    subtitle: String(localized: "settings.font.custom.add.subtitle"),
                    selected: false,
                    available: true,
                    showsUploadIcon: true,
                    showsSelectionControl: false,
                    accentColor: accentColor,
                    backgroundColor: backgroundColor
                )
            }
        }
    }

    @objc private func languageTapped() {
        showLanguagePicker(sourceView: languageRow)
    }

    @objc private func modeTapped(_ sender: AppearanceModeCardView) {
        settings.appearanceMode = sender.mode
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        updateUI()
    }

    @objc private func styleTapped(_ sender: ThemeStyleCardView) {
        settings.themeStyle = sender.style
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        rebuildContent()
        renderedThemeStyle = settings.themeStyle
        updateUI()
    }


    @objc private func fontFamilyTapped(_ sender: AppearanceFontOptionRow) {
        switch sender.option {
        case .system:
            settings.contentFontFamily = .system
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        case .miSans:
            if settings.isContentFontFamilyAvailable(.miSans) {
                settings.contentFontFamily = .miSans
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                updateUI()
            } else {
                presentFontImporter(for: .miSans)
            }
        case .importedCustom(let fontId):
            settings.selectImportedContentFont(id: fontId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        case .importCustom:
            presentFontImporter(for: .custom)
        }
    }

    private func showLanguagePicker(sourceView: UIView?) {
        let alert = UIAlertController(
            title: String(localized: "settings.language"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for language in AppSettings.AppLanguage.allCases {
            let action = UIAlertAction(title: language.title, style: .default) { [weak self] _ in
                guard let self else { return }
                settings.appLanguage = language
            }
            action.setValue(language == settings.appLanguage, forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true)
    }

    private func presentFontImporter(for target: PendingFontImportTarget) {
        pendingFontImportTarget = target
        let fontTypes = [
            UTType(filenameExtension: "ttf"),
            UTType(filenameExtension: "otf"),
            UTType(filenameExtension: "ttc"),
        ].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: fontTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = target == .custom
        present(picker, animated: true)
    }

    private func showErrorAlert(message: String) {
        let alert = UIAlertController(
            title: String(localized: "settings.operation_failed"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }
}

extension AppearanceSettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let target = pendingFontImportTarget, !urls.isEmpty else { return }
        pendingFontImportTarget = nil
        do {
            switch target {
            case .miSans:
                guard let url = urls.first else { return }
                try settings.importContentFont(from: url, targetFamily: .miSans)
            case .custom:
                try settings.importCustomContentFonts(from: urls)
                rebuildContent()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        } catch {
            showErrorAlert(message: error.localizedDescription)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingFontImportTarget = nil
    }
}

final class AppearanceLanguageRow: UIControl {
    private let iconWell = UIView()
    private let iconView: UIImageView = {
        let view = UIImageView(
            image: UIImage(
                systemName: "character.book.closed",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            )
        )
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = String(localized: "settings.language")
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronView: UIImageView = {
        let view = UIImageView(
            image: UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
            )
        )
        view.tintColor = .tertiaryLabel
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.99, y: 0.99) : .identity
                self.alpha = self.isHighlighted ? 0.86 : 1
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    private func setupUI() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = DataManagementPalette.borderColor.cgColor
        layer.shadowOpacity = 0.07
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 5)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true

        iconWell.translatesAutoresizingMaskIntoConstraints = false
        iconWell.layer.cornerRadius = 13
        iconWell.layer.cornerCurve = .continuous
        iconWell.isUserInteractionEnabled = false
        iconWell.addSubview(iconView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false

        addSubview(iconWell)
        addSubview(textStack)
        addSubview(chevronView)
        NSLayoutConstraint.activate([
            iconWell.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconWell.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWell.widthAnchor.constraint(equalToConstant: 40),
            iconWell.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: iconWell.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            textStack.leadingAnchor.constraint(equalTo: iconWell.trailingAnchor, constant: 12),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -12),
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    func configure(languageTitle: String, accentColor: UIColor, backgroundColor: UIColor) {
        self.backgroundColor = backgroundColor
        layer.shadowColor = accentColor.cgColor
        layer.borderColor = accentColor.withAlphaComponent(0.14).cgColor
        iconWell.backgroundColor = accentColor.withAlphaComponent(0.14)
        iconView.tintColor = accentColor
        valueLabel.text = languageTitle
        accessibilityLabel = "\(String(localized: "settings.language"))，\(languageTitle)"
        accessibilityTraits = [.button]
    }
}

final class AppearanceModeCardView: UIControl {
    let mode: AppSettings.AppearanceMode

    private let previewView: AppearanceModePreviewView
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }()

    private let modeIconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleRow: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            }
        }
    }

    init(mode: AppSettings.AppearanceMode) {
        self.mode = mode
        self.previewView = AppearanceModePreviewView(mode: mode)
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = mode.title
        modeIconView.image = UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.isUserInteractionEnabled = false
        titleRow.isUserInteractionEnabled = false
        titleRow.addArrangedSubview(modeIconView)
        titleRow.addArrangedSubview(titleLabel)
        addSubview(previewView)
        addSubview(titleRow)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            previewView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            previewView.heightAnchor.constraint(equalToConstant: 56),
            modeIconView.widthAnchor.constraint(equalToConstant: 18),
            modeIconView.heightAnchor.constraint(equalToConstant: 18),
            titleRow.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18),
        ])
        accessibilityLabel = mode.title
        accessibilityTraits = [.button]
    }

    func setSelected(_ selected: Bool, accentColor: UIColor, cardBackgroundColor: UIColor) {
        layer.borderWidth = selected ? 2.5 : 1
        layer.borderColor = selected
            ? accentColor.cgColor
            : UIColor.separator.withAlphaComponent(0.35).cgColor
        self.backgroundColor = selected
            ? accentColor.withAlphaComponent(0.08)
            : cardBackgroundColor
        titleLabel.textColor = selected ? accentColor : .secondaryLabel
        modeIconView.tintColor = selected ? accentColor : .secondaryLabel
        previewView.setNeedsDisplay()
        accessibilityTraits = selected ? [.button, .selected] : [.button]
    }

    private var iconName: String {
        switch mode {
        case .system: return "sparkles"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }
}

final class ThemeStyleCardView: UIControl {
    let style: AppSettings.ThemeStyle

    private let previewView: ThemeStylePreviewView
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.78
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let selectedIconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)))
        view.tintColor = .white
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            }
        }
    }

    init(style: AppSettings.ThemeStyle) {
        self.style = style
        self.previewView = ThemeStylePreviewView(style: style)
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = style.title
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.isUserInteractionEnabled = false
        addSubview(previewView)
        addSubview(titleLabel)
        addSubview(selectedIconView)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: topAnchor),
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewView.heightAnchor.constraint(equalToConstant: 72),
            titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            selectedIconView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            selectedIconView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            selectedIconView.widthAnchor.constraint(equalToConstant: 28),
            selectedIconView.heightAnchor.constraint(equalToConstant: 28),
        ])
        accessibilityLabel = style.title
        accessibilityTraits = [.button]
    }

    func setSelected(_ selected: Bool, accentColor: UIColor, cardBackgroundColor: UIColor) {
        layer.borderWidth = selected ? 2.5 : 1
        layer.borderColor = selected
            ? accentColor.cgColor
            : UIColor.separator.withAlphaComponent(0.35).cgColor
        self.backgroundColor = selected ? accentColor.withAlphaComponent(0.07) : cardBackgroundColor
        titleLabel.textColor = selected ? accentColor : .secondaryLabel
        selectedIconView.isHidden = !selected
        selectedIconView.tintColor = .white
        selectedIconView.layer.shadowColor = accentColor.cgColor
        selectedIconView.layer.shadowOpacity = selected ? 0.35 : 0
        selectedIconView.layer.shadowRadius = selected ? 7 : 0
        selectedIconView.layer.shadowOffset = .zero
        accessibilityTraits = selected ? [.button, .selected] : [.button]
    }
}

final class AppearanceFontOptionRow: UIControl {
    let option: AppearanceFontOption

    private let radioView = UIView()
    private let radioDotView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let uploadIconView = UIImageView(image: UIImage(systemName: "square.and.arrow.up"))

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.alpha = self.isHighlighted ? 0.74 : 1
            }
        }
    }

    init(option: AppearanceFontOption) {
        self.option = option
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true

        radioView.translatesAutoresizingMaskIntoConstraints = false
        radioView.layer.borderWidth = 2
        radioView.layer.cornerRadius = 11
        radioView.layer.cornerCurve = .continuous
        radioView.isUserInteractionEnabled = false

        radioDotView.translatesAutoresizingMaskIntoConstraints = false
        radioDotView.layer.cornerRadius = 5
        radioDotView.layer.cornerCurve = .continuous
        radioDotView.isUserInteractionEnabled = false
        radioView.addSubview(radioDotView)

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.isUserInteractionEnabled = false

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isUserInteractionEnabled = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.isUserInteractionEnabled = false
        textStack.translatesAutoresizingMaskIntoConstraints = false

        uploadIconView.translatesAutoresizingMaskIntoConstraints = false
        uploadIconView.contentMode = .scaleAspectFit
        uploadIconView.isUserInteractionEnabled = false

        addSubview(radioView)
        addSubview(textStack)
        addSubview(uploadIconView)

        NSLayoutConstraint.activate([
            radioView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            radioView.centerYAnchor.constraint(equalTo: centerYAnchor),
            radioView.widthAnchor.constraint(equalToConstant: 22),
            radioView.heightAnchor.constraint(equalToConstant: 22),
            radioDotView.centerXAnchor.constraint(equalTo: radioView.centerXAnchor),
            radioDotView.centerYAnchor.constraint(equalTo: radioView.centerYAnchor),
            radioDotView.widthAnchor.constraint(equalToConstant: 10),
            radioDotView.heightAnchor.constraint(equalToConstant: 10),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: radioView.trailingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: uploadIconView.leadingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            uploadIconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            uploadIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            uploadIconView.widthAnchor.constraint(equalToConstant: 20),
            uploadIconView.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    func configure(
        title: String,
        subtitle: String,
        selected: Bool,
        available: Bool,
        showsUploadIcon: Bool,
        showsSelectionControl: Bool,
        accentColor: UIColor,
        backgroundColor: UIColor
    ) {
        self.backgroundColor = backgroundColor
        titleLabel.text = title
        subtitleLabel.text = subtitle
        radioView.isHidden = !showsSelectionControl
        radioView.layer.borderColor = (selected ? accentColor : UIColor.secondaryLabel).withAlphaComponent(selected ? 1 : 0.65).cgColor
        radioDotView.backgroundColor = selected ? accentColor : .clear
        titleLabel.textColor = available ? .label : .secondaryLabel
        uploadIconView.tintColor = accentColor
        uploadIconView.isHidden = !showsUploadIcon
        accessibilityLabel = "\(title)，\(subtitle)"
        accessibilityTraits = selected ? [.button, .selected] : [.button]
    }
}

final class AppearanceModePreviewView: UIView {
    private let mode: AppSettings.AppearanceMode

    init(mode: AppSettings.AppearanceMode) {
        self.mode = mode
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let bounds = rect.insetBy(dx: 2, dy: 2)
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: 12)
        UIColor.systemBackground.setFill()
        path.fill()

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        path.addClip()
        switch mode {
        case .system:
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height)).fill()
            UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(x: bounds.midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height)).fill()
        case .light:
            UIColor.white.setFill()
            UIBezierPath(rect: bounds).fill()
        case .dark:
            UIColor(red: 0.08, green: 0.09, blue: 0.11, alpha: 1).setFill()
            UIBezierPath(rect: bounds).fill()
        }
        context.restoreGState()

        drawBars(in: bounds)
        drawAccentPill(in: bounds)
    }

    private func drawBars(in bounds: CGRect) {
        let darkPreview = mode == .dark
        let barColor = darkPreview
            ? UIColor(white: 1, alpha: 0.18)
            : UIColor(white: 0, alpha: 0.16)
        let widths: [CGFloat] = [0.55, 0.80, 0.48]
        for (index, widthRatio) in widths.enumerated() {
            let barRect = CGRect(
                x: bounds.minX + 10,
                y: bounds.minY + 10 + CGFloat(index * 12),
                width: bounds.width * widthRatio,
                height: index == 0 ? 8 : 6
            )
            barColor.setFill()
            UIBezierPath(roundedRect: barRect, cornerRadius: 3).fill()
        }
    }

    private func drawAccentPill(in bounds: CGRect) {
        AppSettings.shared.themeStyle.accentColor.withAlphaComponent(0.78).setFill()
        let pillRect = CGRect(x: bounds.maxX - 34, y: bounds.midY + 4, width: 22, height: 9)
        UIBezierPath(roundedRect: pillRect, cornerRadius: 4.5).fill()
    }
}

final class ThemeStylePreviewView: UIView {
    private let style: AppSettings.ThemeStyle

    init(style: AppSettings.ThemeStyle) {
        self.style = style
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let bounds = rect.insetBy(dx: 0.5, dy: 0.5)
        let path = UIBezierPath(
            roundedRect: bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: 15, height: 15)
        )
        style.appearancePreviewMainColor.setFill()
        path.fill()

        let bottomRect = CGRect(x: bounds.minX, y: bounds.maxY - 26, width: bounds.width, height: 26)
        style.appearancePreviewSurfaceColor.setFill()
        UIBezierPath(rect: bottomRect).fill()

        let swatches = style.appearancePreviewSwatches
        let dotSize: CGFloat = 8
        let spacing: CGFloat = 8
        let totalWidth = CGFloat(swatches.count) * dotSize + CGFloat(max(swatches.count - 1, 0)) * spacing
        var x = bounds.midX - totalWidth / 2
        for color in swatches {
            color.setFill()
            UIBezierPath(ovalIn: CGRect(x: x, y: bottomRect.midY - dotSize / 2, width: dotSize, height: dotSize)).fill()
            x += dotSize + spacing
        }
    }
}

extension AppSettings.ThemeStyle {
    var appearancePreviewMainColor: UIColor {
        switch self {
        case .systemDefault: return UIColor(red: 0.27, green: 0.44, blue: 0.60, alpha: 1)
        case .eyeCare: return UIColor(red: 0.24, green: 0.52, blue: 0.32, alpha: 1)
        case .xiaohongshu: return UIColor(red: 0.92, green: 0.13, blue: 0.22, alpha: 1)
        case .telegram: return UIColor(red: 0.13, green: 0.55, blue: 0.82, alpha: 1)
        case .weChat: return UIColor(red: 0.027, green: 0.757, blue: 0.376, alpha: 1)
        }
    }

    var appearancePreviewSurfaceColor: UIColor {
        switch self {
        case .systemDefault: return UIColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 1)
        case .eyeCare: return UIColor(red: 0.93, green: 0.98, blue: 0.88, alpha: 1)
        case .xiaohongshu: return UIColor(red: 1.0, green: 0.94, blue: 0.95, alpha: 1)
        case .telegram: return UIColor(red: 0.91, green: 0.97, blue: 1.0, alpha: 1)
        case .weChat: return UIColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1)
        }
    }

    var appearancePreviewSwatches: [UIColor] {
        switch self {
        case .systemDefault:
            return [
                UIColor(red: 0.27, green: 0.44, blue: 0.60, alpha: 1),
                UIColor(red: 0.31, green: 0.34, blue: 0.43, alpha: 1),
                UIColor(red: 0.45, green: 0.34, blue: 0.49, alpha: 1),
            ]
        case .eyeCare:
            return [
                UIColor(red: 0.24, green: 0.52, blue: 0.32, alpha: 1),
                UIColor(red: 0.36, green: 0.43, blue: 0.31, alpha: 1),
                UIColor(red: 0.17, green: 0.47, blue: 0.48, alpha: 1),
            ]
        case .xiaohongshu:
            return [
                UIColor(red: 0.92, green: 0.13, blue: 0.22, alpha: 1),
                UIColor(red: 0.72, green: 0.22, blue: 0.36, alpha: 1),
                UIColor(red: 1.0, green: 0.54, blue: 0.42, alpha: 1),
            ]
        case .telegram:
            return [
                UIColor(red: 0.13, green: 0.55, blue: 0.82, alpha: 1),
                UIColor(red: 0.0, green: 0.64, blue: 0.88, alpha: 1),
                UIColor(red: 0.22, green: 0.44, blue: 0.76, alpha: 1),
            ]
        case .weChat:
            return [
                UIColor(red: 0.027, green: 0.757, blue: 0.376, alpha: 1),
                UIColor(red: 0.10, green: 0.64, blue: 0.62, alpha: 1),
                UIColor(red: 0.98, green: 0.62, blue: 0.15, alpha: 1),
            ]
        }
    }
}
