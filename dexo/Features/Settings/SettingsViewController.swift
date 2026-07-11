import SDWebImage
import UIKit
import UniformTypeIdentifiers
import WebKit

final class SettingsViewController: ObservableViewController {
    fileprivate enum Category: CaseIterable {
        case appearance
        case reading
        case network
        case bottomBar
        case dataManagement

        var title: String {
            switch self {
            case .appearance: return String(localized: "settings.appearance_design")
            case .reading: return String(localized: "settings.reading_design")
            case .network: return String(localized: "settings.network")
            case .bottomBar: return String(localized: "settings.bottom_bar")
            case .dataManagement: return String(localized: "settings.data_management")
            }
        }

        var subtitle: String {
            switch self {
            case .appearance: return String(localized: "settings.appearance.subtitle")
            case .reading: return String(localized: "settings.reading.subtitle")
            case .network: return String(localized: "settings.network.subtitle")
            case .bottomBar: return String(localized: "settings.bottom_bar.subtitle")
            case .dataManagement: return String(localized: "settings.data_management.subtitle")
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "paintpalette.fill"
            case .reading: return "book.closed.fill"
            case .network: return "network"
            case .bottomBar: return "rectangle.bottomthird.inset.filled"
            case .dataManagement: return "externaldrive.fill"
            }
        }

        var tintColor: UIColor {
            switch self {
            case .appearance: return .systemTeal
            case .reading: return .systemOrange
            case .network: return .systemBlue
            case .bottomBar: return .systemPurple
            case .dataManagement: return .systemBrown
            }
        }
    }

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "tab.settings")
        view.backgroundColor = .systemGroupedBackground

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func updateUI() {
        title = String(localized: "tab.settings")
        tableView.reloadData()
    }
}

extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Category.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let category = Category.allCases[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: category.symbolName)
        content.imageProperties.tintColor = category.tintColor
        content.text = category.title
        content.secondaryText = category.subtitle
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let category = Category.allCases[indexPath.row]
        if category == .appearance {
            navigationController?.pushViewController(AppearanceSettingsViewController(), animated: true)
            return
        }
        if category == .reading {
            navigationController?.pushViewController(ReadingSettingsViewController(), animated: true)
            return
        }
        if category == .bottomBar {
            navigationController?.pushViewController(BottomBarLayoutViewController(), animated: true)
            return
        }
        if category == .dataManagement {
            navigationController?.pushViewController(DataManagementSettingsViewController(), animated: true)
            return
        }
        let vc = SettingsCategoryViewController(category: category)
        navigationController?.pushViewController(vc, animated: true)
    }
}

private enum AppearanceFontOption: Hashable {
    case system
    case miSans
    case importedCustom(String)
    case importCustom
}

private enum PendingFontImportTarget: Equatable {
    case miSans
    case custom
}

private final class AppearanceSettingsViewController: ObservableViewController {
    private let settings = AppSettings.shared
    private var modeCards: [AppSettings.AppearanceMode: AppearanceModeCardView] = [:]
    private var styleCards: [AppSettings.ThemeStyle: ThemeStyleCardView] = [:]
    private var iconCards: [AppSettings.AppIconStyle: AppIconCardView] = [:]
    private var fontRows: [AppearanceFontOption: AppearanceFontOptionRow] = [:]
    private var sectionIconViews: [UIImageView] = []
    private var sectionHeaderViews: [DataManagementSectionHeaderView] = []
    private let interfaceFontSizeCard = FontScaleCardView()
    private let fontScopeRow = ReadingToggleRowView()
    private let incomingTopicsFloatingRow = ReadingToggleRowView()
    private let xiaohongshuStaggeredCardsRow = ReadingToggleRowView()
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
        title = String(localized: "settings.section.appearance")
        view.backgroundColor = .systemGroupedBackground
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
        let pageBackground = themeStyle == .systemDefault ? UIColor.systemGroupedBackground : themeStyle.mutedContentBackgroundColor
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
        iconCards.forEach { iconStyle, card in
            card.setSelected(
                iconStyle == settings.appIconStyle,
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
        xiaohongshuStaggeredCardsRow.configure(
            title: String(localized: "settings.appearance.xiaohongshu_staggered_cards"),
            subtitle: String(localized: "settings.appearance.xiaohongshu_staggered_cards.subtitle"),
            symbolName: "square.grid.2x2",
            isOn: settings.xiaohongshuCardsStaggered,
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
        xiaohongshuStaggeredCardsRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.xiaohongshuCardsStaggered = isOn
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
        iconCards.removeAll()
        fontRows.removeAll()
        sectionIconViews.removeAll()
        sectionHeaderViews.removeAll()

        let languageSection = verticalSection(
            title: String(localized: "settings.language"),
            symbolName: "globe"
        )
        languageSection.addArrangedSubview(languageRow)
        contentStack.addArrangedSubview(languageSection)

        let modeSection = verticalSection(
            title: String(localized: "settings.appearance.theme_mode"),
            symbolName: "gearshape"
        )
        modeSection.addArrangedSubview(makeModeGrid())
        contentStack.addArrangedSubview(modeSection)

        let styleSection = verticalSection(
            title: String(localized: "settings.appearance.theme_colors"),
            symbolName: "paintpalette"
        )
        let subtitle = UILabel()
        subtitle.text = String(localized: "settings.appearance.palette_style")
        subtitle.font = .systemFont(ofSize: 16, weight: .semibold)
        subtitle.textColor = .secondaryLabel
        styleSection.addArrangedSubview(subtitle)
        styleSection.setCustomSpacing(12, after: subtitle)
        styleSection.addArrangedSubview(makeStyleGrid())
        if settings.themeStyle == .xiaohongshu {
            styleSection.addArrangedSubview(xiaohongshuStaggeredCardsRow)
        }
        contentStack.addArrangedSubview(styleSection)

        let homeSection = verticalSection(
            title: String(localized: "settings.appearance.home_display"),
            symbolName: "house"
        )
        homeSection.addArrangedSubview(incomingTopicsFloatingRow)
        contentStack.addArrangedSubview(homeSection)

        let iconSection = verticalSection(
            title: String(localized: "settings.app_icon"),
            symbolName: "app.badge"
        )
        iconSection.addArrangedSubview(makeIconGrid())
        contentStack.addArrangedSubview(iconSection)

        let fontSection = verticalSection(
            title: String(localized: "settings.appearance.font"),
            symbolName: "textformat"
        )
        fontSection.addArrangedSubview(interfaceFontSizeCard)
        fontSection.addArrangedSubview(makeFontOptionsCard())
        fontSection.addArrangedSubview(fontScopeRow)
        contentStack.addArrangedSubview(fontSection)
    }

    private func verticalSection(title: String, symbolName: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        let header = DataManagementSectionHeaderView(title: title, symbolName: symbolName, tintColor: settings.themeStyle.accentColor)
        sectionHeaderViews.append(header)
        stack.addArrangedSubview(header)
        return stack
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

    private func makeIconGrid() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .fill
        row.distribution = .fillEqually
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        for iconStyle in AppSettings.AppIconStyle.allCases {
            let card = AppIconCardView(iconStyle: iconStyle)
            card.addTarget(self, action: #selector(appIconTapped(_:)), for: .touchUpInside)
            card.heightAnchor.constraint(equalToConstant: 132).isActive = true
            row.addArrangedSubview(card)
            iconCards[iconStyle] = card
        }
        return row
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

    @objc private func appIconTapped(_ sender: AppIconCardView) {
        settings.setAppIconStyle(sender.iconStyle) { [weak self] error in
            guard let self else { return }
            if let error {
                showErrorAlert(message: error.localizedDescription)
                return
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateUI()
        }
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

private final class AppearanceLanguageRow: UIControl {
    private let iconView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "character.book.closed", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)))
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let chevronView: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
        view.tintColor = .secondaryLabel
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

    private func setupUI() {
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 52).isActive = true

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(chevronView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: chevronView.leadingAnchor, constant: -12),
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    func configure(languageTitle: String, accentColor: UIColor, backgroundColor: UIColor) {
        self.backgroundColor = backgroundColor
        titleLabel.text = languageTitle
        iconView.tintColor = accentColor
        accessibilityLabel = "\(String(localized: "settings.language"))，\(languageTitle)"
        accessibilityTraits = [.button]
    }
}

private final class AppearanceModeCardView: UIControl {
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

private final class ThemeStyleCardView: UIControl {
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

private final class AppIconCardView: UIControl {
    let iconStyle: AppSettings.AppIconStyle

    private let previewView: DexoFluxIconPreviewView
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    init(iconStyle: AppSettings.AppIconStyle) {
        self.iconStyle = iconStyle
        self.previewView = DexoFluxIconPreviewView(iconStyle: iconStyle)
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.isUserInteractionEnabled = false
        titleLabel.text = iconStyle.title
        titleLabel.isUserInteractionEnabled = false
        addSubview(previewView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            previewView.centerXAnchor.constraint(equalTo: centerXAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 76),
            previewView.heightAnchor.constraint(equalToConstant: 76),
            titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 9),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),
        ])
        accessibilityLabel = iconStyle.title
        accessibilityTraits = [.button]
    }

    func setSelected(_ selected: Bool, accentColor: UIColor, cardBackgroundColor: UIColor) {
        previewView.setSelected(selected, accentColor: accentColor, cardBackgroundColor: cardBackgroundColor)
        titleLabel.textColor = selected ? accentColor : .secondaryLabel
        accessibilityTraits = selected ? [.button, .selected] : [.button]
    }
}

private final class DexoFluxIconPreviewView: UIView {
    private let iconStyle: AppSettings.AppIconStyle
    private var selected = false
    private var accentColor = UIColor.systemBlue
    private var cardBackgroundColor = UIColor.secondarySystemGroupedBackground

    init(iconStyle: AppSettings.AppIconStyle) {
        self.iconStyle = iconStyle
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool, accentColor: UIColor, cardBackgroundColor: UIColor) {
        self.selected = selected
        self.accentColor = accentColor
        self.cardBackgroundColor = cardBackgroundColor
        layer.shadowColor = accentColor.cgColor
        layer.shadowOpacity = selected ? 0.24 : 0.10
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let iconRect = rect.insetBy(dx: selected ? 5 : 8, dy: selected ? 5 : 8)
        let iconPath = UIBezierPath(roundedRect: iconRect, cornerRadius: 18)
        let colors = palette
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        iconPath.addClip()
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [colors.backgroundTop.cgColor, colors.backgroundBottom.cgColor] as CFArray,
            locations: [0, 1]
        )
        context.drawLinearGradient(
            gradient!,
            start: CGPoint(x: iconRect.midX, y: iconRect.minY),
            end: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            options: []
        )
        drawFluxMotif(in: iconRect, colors: colors)
        context.restoreGState()

        if selected {
            accentColor.setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 21)
            border.lineWidth = 3
            border.stroke()
        } else {
            UIColor.separator.withAlphaComponent(0.22).setStroke()
            let border = UIBezierPath(roundedRect: iconRect, cornerRadius: 18)
            border.lineWidth = 1
            border.stroke()
        }
    }

    private func drawFluxMotif(in rect: CGRect, colors: IconPalette) {
        switch iconStyle {
        case .primary:
            drawDMark(in: rect, color: .white, alpha: 0.90, lineWidth: 8)
            drawFluxLine(in: rect, color: UIColor(red: 0.55, green: 0.82, blue: 0.95, alpha: 1), yOffset: 0.05)
        case .fluxOrbit:
            drawDMark(in: rect, color: .white, alpha: 0.92, lineWidth: 8)
            drawOrbit(in: rect, color: colors.accent)
            drawDots(in: rect, colors: [colors.accent, .white, UIColor(red: 0.95, green: 0.76, blue: 0.28, alpha: 1)])
        case .fluxCards:
            drawCardStack(in: rect, colors: colors)
            drawDMark(in: rect.insetBy(dx: 8, dy: 8), color: .white, alpha: 0.96, lineWidth: 7)
        case .fluxSignal:
            drawDMark(in: rect, color: .white, alpha: 0.90, lineWidth: 8)
            drawSignalWaves(in: rect, color: colors.accent)
            drawDots(in: rect, colors: [.white, colors.accent, UIColor(red: 0.11, green: 0.42, blue: 0.72, alpha: 1)])
        }
    }

    private func drawDMark(in rect: CGRect, color: UIColor, alpha: CGFloat, lineWidth: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.maxY - rect.height * 0.25))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.25))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.midY),
            controlPoint1: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.22),
            controlPoint2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.maxY - rect.height * 0.25),
            controlPoint1: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.34),
            controlPoint2: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY - rect.height * 0.22)
        )
        color.withAlphaComponent(alpha).setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawFluxLine(in rect: CGRect, color: UIColor, yOffset: CGFloat) {
        let line = UIBezierPath()
        line.move(to: CGPoint(x: rect.minX + rect.width * 0.21, y: rect.midY + rect.height * yOffset))
        line.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.midY - rect.height * 0.12),
            controlPoint1: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.24),
            controlPoint2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.maxY - rect.height * 0.15)
        )
        color.withAlphaComponent(0.78).setStroke()
        line.lineWidth = 5
        line.lineCapStyle = .round
        line.stroke()
    }

    private func drawOrbit(in rect: CGRect, color: UIColor) {
        let orbit = UIBezierPath(ovalIn: rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.27))
        color.withAlphaComponent(0.55).setStroke()
        orbit.lineWidth = 4
        orbit.stroke()
        drawFluxLine(in: rect, color: color, yOffset: -0.04)
    }

    private func drawCardStack(in rect: CGRect, colors: IconPalette) {
        let back = UIBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.21, dy: rect.height * 0.23).offsetBy(dx: 5, dy: -7), cornerRadius: 10)
        UIColor.white.withAlphaComponent(0.30).setFill()
        back.fill()
        let front = UIBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.27), cornerRadius: 11)
        colors.accent.withAlphaComponent(0.84).setFill()
        front.fill()
        UIColor.white.withAlphaComponent(0.55).setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.40, width: rect.width * 0.44, height: 5), cornerRadius: 2.5).fill()
        UIBezierPath(roundedRect: CGRect(x: rect.minX + rect.width * 0.28, y: rect.maxY - rect.height * 0.52, width: rect.width * 0.30, height: 5), cornerRadius: 2.5).fill()
    }

    private func drawSignalWaves(in rect: CGRect, color: UIColor) {
        for index in 0..<3 {
            let inset = CGFloat(index) * 7 + rect.width * 0.14
            let wave = UIBezierPath(arcCenter: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.midY), radius: rect.width * 0.28 + CGFloat(index) * 8, startAngle: -.pi / 3, endAngle: .pi / 3, clockwise: true)
            color.withAlphaComponent(0.26 + CGFloat(index) * 0.16).setStroke()
            wave.lineWidth = max(2, 4 - CGFloat(index) * 0.4)
            wave.stroke()
            _ = inset
        }
    }

    private func drawDots(in rect: CGRect, colors: [UIColor]) {
        let dotSize = rect.width * 0.08
        let startX = rect.minX + rect.width * 0.36
        for (index, color) in colors.enumerated() {
            color.withAlphaComponent(0.88).setFill()
            UIBezierPath(
                ovalIn: CGRect(
                    x: startX + CGFloat(index) * dotSize * 1.55,
                    y: rect.maxY - rect.height * 0.22,
                    width: dotSize,
                    height: dotSize
                )
            ).fill()
        }
    }

    private var palette: IconPalette {
        switch iconStyle {
        case .primary:
            return IconPalette(
                backgroundTop: UIColor(red: 0.27, green: 0.34, blue: 0.49, alpha: 1),
                backgroundBottom: UIColor(red: 0.10, green: 0.18, blue: 0.33, alpha: 1),
                accent: UIColor(red: 0.55, green: 0.82, blue: 0.95, alpha: 1)
            )
        case .fluxOrbit:
            return IconPalette(
                backgroundTop: UIColor(red: 0.07, green: 0.16, blue: 0.34, alpha: 1),
                backgroundBottom: UIColor(red: 0.03, green: 0.40, blue: 0.56, alpha: 1),
                accent: UIColor(red: 0.20, green: 0.83, blue: 0.94, alpha: 1)
            )
        case .fluxCards:
            return IconPalette(
                backgroundTop: UIColor(red: 1.0, green: 0.40, blue: 0.49, alpha: 1),
                backgroundBottom: UIColor(red: 0.78, green: 0.10, blue: 0.22, alpha: 1),
                accent: UIColor(red: 1.0, green: 0.82, blue: 0.34, alpha: 1)
            )
        case .fluxSignal:
            return IconPalette(
                backgroundTop: UIColor(red: 0.15, green: 0.63, blue: 0.91, alpha: 1),
                backgroundBottom: UIColor(red: 0.06, green: 0.30, blue: 0.63, alpha: 1),
                accent: UIColor(red: 0.76, green: 0.93, blue: 1.0, alpha: 1)
            )
        }
    }

    private struct IconPalette {
        let backgroundTop: UIColor
        let backgroundBottom: UIColor
        let accent: UIColor
    }
}

private final class AppearanceFontOptionRow: UIControl {
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

private final class AppearanceModePreviewView: UIView {
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

private final class ThemeStylePreviewView: UIView {
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

private extension AppSettings.ThemeStyle {
    var appearancePreviewMainColor: UIColor {
        switch self {
        case .systemDefault: return UIColor(red: 0.27, green: 0.44, blue: 0.60, alpha: 1)
        case .eyeCare: return UIColor(red: 0.24, green: 0.52, blue: 0.32, alpha: 1)
        case .xiaohongshu: return UIColor(red: 0.92, green: 0.13, blue: 0.22, alpha: 1)
        case .telegram: return UIColor(red: 0.13, green: 0.55, blue: 0.82, alpha: 1)
        }
    }

    var appearancePreviewSurfaceColor: UIColor {
        switch self {
        case .systemDefault: return UIColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 1)
        case .eyeCare: return UIColor(red: 0.93, green: 0.98, blue: 0.88, alpha: 1)
        case .xiaohongshu: return UIColor(red: 1.0, green: 0.94, blue: 0.95, alpha: 1)
        case .telegram: return UIColor(red: 0.91, green: 0.97, blue: 1.0, alpha: 1)
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
        }
    }
}

final class ReadingSettingsViewController: ObservableViewController {
    private enum ToggleOption: CaseIterable {
        case readingComfort
        case defaultExpandRelatedLinks
        case bottomBarAutoHide
        case openExternalLinksInAppBrowser
        case hideScrollIndicators

        var title: String {
            switch self {
            case .readingComfort: return String(localized: "settings.reading.comfort")
            case .defaultExpandRelatedLinks: return String(localized: "settings.reading.expand_related_links")
            case .bottomBarAutoHide: return String(localized: "settings.reading.collapse_navigation")
            case .openExternalLinksInAppBrowser: return String(localized: "settings.reading.in_app_browser")
            case .hideScrollIndicators: return String(localized: "settings.reading.hide_scroll_indicators")
            }
        }

        var subtitle: String {
            switch self {
            case .readingComfort: return String(localized: "settings.reading.comfort.subtitle")
            case .defaultExpandRelatedLinks: return String(localized: "settings.reading.expand_related_links.subtitle")
            case .bottomBarAutoHide: return String(localized: "settings.reading.collapse_navigation.subtitle")
            case .openExternalLinksInAppBrowser: return String(localized: "settings.reading.in_app_browser.subtitle")
            case .hideScrollIndicators: return String(localized: "settings.reading.hide_scroll_indicators.subtitle")
            }
        }

        var symbolName: String {
            switch self {
            case .readingComfort: return "wand.and.stars"
            case .defaultExpandRelatedLinks: return "link"
            case .bottomBarAutoHide: return "arrow.up.and.down"
            case .openExternalLinksInAppBrowser: return "rectangle.portrait.and.arrow.right"
            case .hideScrollIndicators: return "scroll"
            }
        }
    }

    private let settings = AppSettings.shared
    private let previewCard = ReadingPreviewHeroView()
    private let fontSizeCard = FontScaleCardView()
    private var toggleRows: [ToggleOption: ReadingToggleRowView] = [:]

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
        stack.spacing = 22
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 32, trailing: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "settings.reading_design")
        configureRootView()
        rebuildContent()
        refreshDataViews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        refreshDataViews()
    }

    override func updateUI() {
        title = String(localized: "settings.reading_design")
        rebuildContent()
        refreshDataViews()
    }

    private func configureRootView() {
        view.backgroundColor = DataManagementPalette.screenBackground
        view.tintColor = settings.themeStyle.accentColor
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
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        toggleRows.removeAll()

        contentStack.addArrangedSubview(previewCard)
        contentStack.addArrangedSubview(makeReadingSection())
        contentStack.addArrangedSubview(makeBasicSection())
    }

    private func makeReadingSection() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(fontSizeCard)
        stack.addArrangedSubview(makeToggleRow(for: .readingComfort))
        stack.addArrangedSubview(makeToggleRow(for: .defaultExpandRelatedLinks))
        return makeSection(
            title: String(localized: "settings.reading.section.reading"),
            symbolName: "book.pages",
            body: stack
        )
    }

    private func makeBasicSection() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(makeToggleRow(for: .bottomBarAutoHide))
        stack.addArrangedSubview(makeToggleRow(for: .openExternalLinksInAppBrowser))
        stack.addArrangedSubview(makeToggleRow(for: .hideScrollIndicators))
        return makeSection(
            title: String(localized: "settings.reading.section.basic"),
            symbolName: "hand.tap",
            body: stack
        )
    }

    private func makeToggleRow(for option: ToggleOption) -> ReadingToggleRowView {
        let row = ReadingToggleRowView()
        row.onValueChanged = { [weak self] isOn in
            self?.setToggle(option, isOn: isOn)
        }
        toggleRows[option] = row
        return row
    }

    private func makeSection(title: String, symbolName: String, body: UIView) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 12
        section.translatesAutoresizingMaskIntoConstraints = false
        section.addArrangedSubview(DataManagementSectionHeaderView(title: title, symbolName: symbolName, tintColor: settings.themeStyle.accentColor))
        section.addArrangedSubview(body)
        return section
    }

    private func refreshDataViews() {
        view.backgroundColor = DataManagementPalette.screenBackground
        view.tintColor = settings.themeStyle.accentColor
        let cardBackground = settings.themeStyle.topicCardBackgroundColor
        let accentColor = settings.themeStyle.accentColor
        previewCard.configure(
            title: String(localized: "settings.reading.preview.title"),
            subtitle: String(localized: "settings.reading.preview.subtitle"),
            sampleTitle: String(localized: "settings.reading.preview.sample_title"),
            sampleBody: String(localized: "settings.reading.preview.sample_body"),
            fontSize: settings.contentFontSize,
            accentColor: accentColor
        )
        fontSizeCard.configure(
            title: String(localized: "settings.content_font_size"),
            resetTitle: String(localized: "settings.reading.reset"),
            sliderValue: settings.contentFontScalePercent,
            minimumValue: AppSettings.minimumFontScalePercent,
            maximumValue: AppSettings.maximumFontScalePercent,
            defaultValue: AppSettings.defaultFontScalePercent,
            accentColor: accentColor,
            backgroundColor: cardBackground
        )
        fontSizeCard.onValueChanged = { [weak self] value in
            guard let self else { return }
            if settings.contentFontSize != .standard {
                settings.contentFontSize = .standard
            }
            settings.contentFontScalePercent = value
            refreshDataViews()
        }
        fontSizeCard.onReset = { [weak self] in
            guard let self else { return }
            settings.contentFontSize = .standard
            settings.contentFontScalePercent = AppSettings.defaultFontScalePercent
            refreshDataViews()
        }

        for option in ToggleOption.allCases {
            toggleRows[option]?.configure(
                title: option.title,
                subtitle: option.subtitle,
                symbolName: option.symbolName,
                isOn: isToggleOn(option),
                accentColor: accentColor,
                backgroundColor: cardBackground
            )
        }
    }

    private func isToggleOn(_ option: ToggleOption) -> Bool {
        switch option {
        case .readingComfort:
            return settings.readingComfortMode
        case .defaultExpandRelatedLinks:
            return settings.defaultExpandRelatedLinks
        case .bottomBarAutoHide:
            return settings.bottomBarAutoHideEnabled
        case .openExternalLinksInAppBrowser:
            return settings.openExternalLinksInAppBrowser
        case .hideScrollIndicators:
            return settings.hideScrollIndicators
        }
    }

    private func setToggle(_ option: ToggleOption, isOn: Bool) {
        switch option {
        case .readingComfort:
            settings.readingComfortMode = isOn
        case .defaultExpandRelatedLinks:
            settings.defaultExpandRelatedLinks = isOn
        case .bottomBarAutoHide:
            settings.bottomBarAutoHideEnabled = isOn
        case .openExternalLinksInAppBrowser:
            settings.openExternalLinksInAppBrowser = isOn
        case .hideScrollIndicators:
            settings.hideScrollIndicators = isOn
        }
        refreshDataViews()
    }

}

private final class ReadingPreviewHeroView: UIView {
    private let gradientLayer = CAGradientLayer()
    private var accentColor = DataManagementPalette.dataBlue

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22, weight: .heavy)
        label.textColor = .white
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.72)
        label.numberOfLines = 2
        return label
    }()

    private let sampleContainer = UIView()
    private let sampleTitleLabel = UILabel()
    private let sampleBodyLabel = UILabel()

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
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = layer.cornerRadius
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 28
        layer.cornerCurve = .continuous
        clipsToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)

        sampleContainer.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        sampleContainer.layer.cornerRadius = 18
        sampleContainer.layer.cornerCurve = .continuous
        sampleContainer.translatesAutoresizingMaskIntoConstraints = false
        sampleContainer.isUserInteractionEnabled = false

        sampleTitleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        sampleTitleLabel.textColor = .white
        sampleTitleLabel.numberOfLines = 1
        sampleTitleLabel.isUserInteractionEnabled = false

        sampleBodyLabel.font = .systemFont(ofSize: 14, weight: .regular)
        sampleBodyLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        sampleBodyLabel.numberOfLines = 3
        sampleBodyLabel.isUserInteractionEnabled = false

        let sampleStack = UIStackView(arrangedSubviews: [sampleTitleLabel, sampleBodyLabel])
        sampleStack.axis = .vertical
        sampleStack.spacing = 7
        sampleStack.isLayoutMarginsRelativeArrangement = true
        sampleStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        sampleStack.translatesAutoresizingMaskIntoConstraints = false
        sampleStack.isUserInteractionEnabled = false
        sampleContainer.addSubview(sampleStack)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 5
        headerStack.isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [headerStack, sampleContainer])
        stack.axis = .vertical
        stack.spacing = 18
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 22, leading: 22, bottom: 20, trailing: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            sampleStack.topAnchor.constraint(equalTo: sampleContainer.topAnchor),
            sampleStack.leadingAnchor.constraint(equalTo: sampleContainer.leadingAnchor),
            sampleStack.trailingAnchor.constraint(equalTo: sampleContainer.trailingAnchor),
            sampleStack.bottomAnchor.constraint(equalTo: sampleContainer.bottomAnchor),
        ])
    }

    func configure(
        title: String,
        subtitle: String,
        sampleTitle: String,
        sampleBody: String,
        fontSize: AppSettings.ContentFontSize,
        accentColor: UIColor
    ) {
        self.accentColor = accentColor
        titleLabel.text = title
        subtitleLabel.text = subtitle
        sampleTitleLabel.text = sampleTitle
        sampleBodyLabel.text = sampleBody
        let settings = AppSettings.shared
        let titleSize = settings.effectiveContentPointSize(for: max(fontSize.basePointSize - 1, 1))
        let bodySize = settings.effectiveContentPointSize(for: max(fontSize.basePointSize - 3, 1))
        sampleTitleLabel.font = settings.contentFont(ofSize: titleSize, weight: .bold)
        sampleBodyLabel.font = settings.contentFont(ofSize: bodySize, weight: .regular)
        updateGradient()
    }

    private func updateGradient() {
        let resolvedAccent = accentColor.resolvedColor(with: traitCollection)
        gradientLayer.colors = [
            resolvedAccent.cgColor,
            DataManagementPalette.dataBlue.resolvedColor(with: traitCollection).cgColor,
            DataManagementPalette.deepBlue.resolvedColor(with: traitCollection).cgColor,
        ]
        gradientLayer.locations = [0, 0.55, 1]
    }
}

private final class FontScaleCardView: UIView {
    var onValueChanged: ((Int) -> Void)?
    var onReset: (() -> Void)?

    private let iconContainer = UIView()
    private let iconLabel = UILabel()
    private let titleLabel = UILabel()
    private let percentLabel = UILabel()
    private let resetButton = UIButton(type: .system)
    private let decreaseButton = UIButton(type: .system)
    private let increaseButton = UIButton(type: .system)
    private let slider = UISlider()
    private var currentValue = AppSettings.defaultFontScalePercent
    private var defaultValue = AppSettings.defaultFontScalePercent
    private var minimumValue = AppSettings.minimumFontScalePercent
    private var maximumValue = AppSettings.maximumFontScalePercent
    private var stepValue = AppSettings.fontScaleStepPercent
    private var accentColor = UIColor.systemBlue

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
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = DataManagementPalette.borderColor.cgColor
        layer.shadowOpacity = 0.07
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 8)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 15
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.isUserInteractionEnabled = false

        iconLabel.text = "Tt"
        iconLabel.font = .systemFont(ofSize: 23, weight: .black)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.isUserInteractionEnabled = false
        iconContainer.addSubview(iconLabel)

        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.isUserInteractionEnabled = false

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
        percentLabel.textColor = .secondaryLabel
        percentLabel.isUserInteractionEnabled = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, percentLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.isUserInteractionEnabled = false

        resetButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        resetButton.addAction(UIAction { [weak self] _ in
            self?.onReset?()
        }, for: .touchUpInside)

        let topRow = UIStackView(arrangedSubviews: [iconContainer, textStack, resetButton])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 14
        topRow.translatesAutoresizingMaskIntoConstraints = false

        slider.minimumValue = Float(AppSettings.minimumFontScalePercent)
        slider.maximumValue = Float(AppSettings.maximumFontScalePercent)
        slider.isContinuous = true
        slider.addTarget(self, action: #selector(sliderChanged(_:)), for: .valueChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false

        configureStepButton(decreaseButton, title: "-")
        configureStepButton(increaseButton, title: "+")
        decreaseButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            adjustValue(by: -stepValue)
        }, for: .touchUpInside)
        increaseButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            adjustValue(by: stepValue)
        }, for: .touchUpInside)

        let sliderRow = UIStackView(arrangedSubviews: [decreaseButton, slider, increaseButton])
        sliderRow.axis = .horizontal
        sliderRow.alignment = .center
        sliderRow.spacing = 10
        sliderRow.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [topRow, sliderRow])
        stack.axis = .vertical
        stack.spacing = 24
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 20, trailing: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 48),
            iconContainer.heightAnchor.constraint(equalToConstant: 48),
            iconLabel.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            textStack.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            decreaseButton.widthAnchor.constraint(equalToConstant: 44),
            decreaseButton.heightAnchor.constraint(equalToConstant: 44),
            increaseButton.widthAnchor.constraint(equalToConstant: 44),
            increaseButton.heightAnchor.constraint(equalToConstant: 44),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureStepButton(_ button: UIButton, title: String) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityTraits.insert(.button)
    }

    func configure(
        title: String,
        resetTitle: String,
        sliderValue: Int,
        minimumValue: Int,
        maximumValue: Int,
        defaultValue: Int,
        stepValue: Int = AppSettings.fontScaleStepPercent,
        accentColor: UIColor,
        backgroundColor: UIColor
    ) {
        self.backgroundColor = backgroundColor
        self.defaultValue = defaultValue
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.stepValue = max(stepValue, 1)
        self.accentColor = accentColor
        currentValue = min(max(sliderValue, minimumValue), maximumValue)
        layer.shadowColor = accentColor.cgColor
        layer.borderColor = accentColor.withAlphaComponent(0.14).cgColor
        iconContainer.backgroundColor = accentColor.withAlphaComponent(0.14)
        iconLabel.textColor = accentColor
        titleLabel.text = title
        percentLabel.text = "\(currentValue)%"
        resetButton.setTitle(resetTitle, for: .normal)
        resetButton.setTitleColor(currentValue == defaultValue ? .tertiaryLabel : accentColor, for: .normal)
        resetButton.isEnabled = currentValue != defaultValue
        slider.minimumValue = Float(minimumValue)
        slider.maximumValue = Float(maximumValue)
        slider.minimumTrackTintColor = accentColor
        slider.maximumTrackTintColor = UIColor.tertiaryLabel.withAlphaComponent(0.35)
        slider.thumbTintColor = accentColor
        slider.setValue(Float(currentValue), animated: false)
        applyStepButtonStyle()
        accessibilityLabel = "\(title)，\(currentValue)%"
    }

    @objc private func sliderChanged(_ sender: UISlider) {
        let value = snappedValue(Int(round(sender.value)))
        setCurrentValue(value, animated: false, notify: true)
    }

    private func adjustValue(by delta: Int) {
        setCurrentValue(currentValue + delta, animated: true, notify: true)
    }

    private func setCurrentValue(_ rawValue: Int, animated: Bool, notify: Bool) {
        let value = snappedValue(rawValue)
        slider.setValue(Float(value), animated: animated)
        guard value != currentValue else {
            applyStepButtonStyle()
            return
        }
        currentValue = value
        percentLabel.text = "\(value)%"
        resetButton.setTitleColor(value == defaultValue ? .tertiaryLabel : accentColor, for: .normal)
        resetButton.isEnabled = value != defaultValue
        applyStepButtonStyle()
        UISelectionFeedbackGenerator().selectionChanged()
        if notify {
            onValueChanged?(value)
        }
    }

    private func snappedValue(_ rawValue: Int) -> Int {
        let clamped = min(max(rawValue, minimumValue), maximumValue)
        let offset = clamped - minimumValue
        let snappedOffset = Int((Double(offset) / Double(stepValue)).rounded()) * stepValue
        return min(max(minimumValue + snappedOffset, minimumValue), maximumValue)
    }

    private func applyStepButtonStyle() {
        decreaseButton.isEnabled = currentValue > minimumValue
        increaseButton.isEnabled = currentValue < maximumValue
        for button in [decreaseButton, increaseButton] {
            button.backgroundColor = accentColor.withAlphaComponent(button.isEnabled ? 0.12 : 0.06)
            button.setTitleColor(button.isEnabled ? accentColor : .tertiaryLabel, for: .normal)
        }
    }
}

private final class ReadingToggleRowView: UIControl {
    var onValueChanged: ((Bool) -> Void)?

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggle = UISwitch()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.99, y: 0.99) : .identity
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
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = DataManagementPalette.borderColor.cgColor
        layer.shadowOpacity = 0.07
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 5)
        addTarget(self, action: #selector(rowTapped), for: .touchUpInside)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 13
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.isUserInteractionEnabled = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        iconContainer.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.isUserInteractionEnabled = false

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isUserInteractionEnabled = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)

        addSubview(iconContainer)
        addSubview(textStack)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -14),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        accessibilityTraits = [.button]
    }

    func configure(
        title: String,
        subtitle: String,
        symbolName: String,
        isOn: Bool,
        accentColor: UIColor,
        backgroundColor: UIColor
    ) {
        self.backgroundColor = backgroundColor
        layer.shadowColor = accentColor.cgColor
        layer.borderColor = accentColor.withAlphaComponent(0.14).cgColor
        iconContainer.backgroundColor = accentColor.withAlphaComponent(0.14)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        iconView.tintColor = accentColor
        titleLabel.text = title
        subtitleLabel.text = subtitle
        toggle.onTintColor = accentColor
        toggle.setOn(isOn, animated: false)
        accessibilityLabel = "\(title)，\(subtitle)"
        accessibilityValue = isOn ? String(localized: "common.on") : String(localized: "common.off")
    }

    @objc private func rowTapped() {
        toggle.setOn(!toggle.isOn, animated: true)
        onValueChanged?(toggle.isOn)
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        onValueChanged?(sender.isOn)
    }
}

private final class SettingsCategoryViewController: ObservableViewController {
    private let settings = AppSettings.shared
    private let category: SettingsViewController.Category

    private enum Row {
        case appearanceMode
        case appLanguage
        case themeStyle
        case readingComfort
        case contentFontSize
        case hideScrollIndicators
        case dohToggle
        case dohDebugLog
        case dohStatus
        case dohProvider
        case dohCustomURL
        case cloudflareVerify
        case bottomBarLayout
        case bottomAutoHide
        case clearImageCache
        case autoOpen
        #if DEBUG
        case renderPreview
        #endif
    }

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        return table
    }()

    init(category: SettingsViewController.Category) {
        self.category = category
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = category.title
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func updateUI() {
        title = category.title
        tableView.reloadData()
    }

    private var rows: [Row] {
        switch category {
        case .appearance:
            return [.appearanceMode, .appLanguage, .themeStyle]
        case .reading:
            return [.readingComfort, .contentFontSize, .hideScrollIndicators]
        case .network:
            return [.cloudflareVerify]
        case .bottomBar:
            return [.bottomBarLayout, .bottomAutoHide]
        case .dataManagement:
            return [.clearImageCache, .autoOpen]
        }
    }
}

extension SettingsCategoryViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]
        switch row {
        case .appearanceMode:
            return valueCell(title: String(localized: "settings.dark_mode"), detail: settings.appearanceMode.title)
        case .appLanguage:
            return valueCell(title: String(localized: "settings.language"), detail: settings.appLanguage.title)
        case .themeStyle:
            return valueCell(title: String(localized: "settings.theme_style"), detail: settings.themeStyle.title)
        case .readingComfort:
            return switchCell(title: String(localized: "settings.reading.comfort"), isOn: settings.readingComfortMode, action: #selector(readingComfortChanged(_:)))
        case .contentFontSize:
            return valueCell(title: String(localized: "settings.content_font_size"), detail: "\(settings.contentFontScalePercent)%")
        case .hideScrollIndicators:
            return switchCell(title: String(localized: "settings.reading.hide_scroll_indicators"), isOn: settings.hideScrollIndicators, action: #selector(hideScrollIndicatorsChanged(_:)))
        case .dohToggle:
            return switchCell(title: "DNS over HTTPS", isOn: settings.dohEnabled, action: #selector(dohToggleChanged(_:)))
        case .dohDebugLog:
            return valueCell(title: "调试日志", detail: "查看并复制最近 200 行")
        case .dohStatus:
            return infoCell(title: "DoH 状态", detail: LightweightDohProxyService.shared.statusDescription)
        case .dohProvider:
            return valueCell(title: String(localized: "settings.network.provider"), detail: settings.dohProvider.title)
        case .dohCustomURL:
            return valueCell(
                title: String(localized: "settings.network.custom_url"),
                detail: settings.dohServerURL.isEmpty ? String(localized: "settings.not_set") : settings.dohServerURL
            )
        case .cloudflareVerify:
            let hasClearance = URL(string: ForumInstance.linuxDoBaseURL)
                .map { WebCookieStore.shared.hasCookie(named: "cf_clearance", for: $0) } ?? false
            return valueCell(
                title: String(localized: "settings.network.cloudflare_verify"),
                detail: hasClearance
                    ? String(localized: "settings.network.cloudflare_ready")
                    : String(localized: "settings.network.cloudflare_required")
            )
        case .bottomBarLayout:
            return valueCell(title: "底栏布局", detail: bottomBarLayoutSummary())
        case .bottomAutoHide:
            return switchCell(title: String(localized: "settings.bottom_bar.auto_hide"), isOn: settings.bottomBarAutoHideEnabled, action: #selector(bottomAutoHideChanged(_:)))
        case .clearImageCache:
            return valueCell(title: String(localized: "settings.data.clear_image_cache"), detail: nil)
        case .autoOpen:
            return switchCell(title: String(localized: "settings.auto_open_last_forum"), isOn: settings.autoOpenLastForum, action: #selector(autoOpenToggleChanged(_:)))
        #if DEBUG
        case .renderPreview:
            return valueCell(title: "Render Preview", detail: nil)
        #endif
        }
    }

    private func valueCell(title: String, detail: String?) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.textColor = detail == nil ? .placeholderText : .secondaryLabel
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func switchCell(title: String, isOn: Bool, action: Selector) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.addTarget(self, action: action, for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    private func infoCell(title: String, detail: String) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = title
        cell.detailTextLabel?.text = detail
        cell.detailTextLabel?.textColor = .secondaryLabel
        cell.detailTextLabel?.numberOfLines = 2
        cell.selectionStyle = .none
        return cell
    }
}

extension SettingsCategoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = rows[indexPath.row]
        switch row {
        case .appearanceMode:
            showAppearancePicker(sourceView: tableView.cellForRow(at: indexPath))
        case .appLanguage:
            showLanguagePicker(sourceView: tableView.cellForRow(at: indexPath))
        case .themeStyle:
            showThemeStylePicker(sourceView: tableView.cellForRow(at: indexPath))
        case .contentFontSize:
            showContentFontSizePicker(sourceView: tableView.cellForRow(at: indexPath))
        case .dohProvider:
            showDohProviderPicker(sourceView: tableView.cellForRow(at: indexPath))
        case .dohCustomURL:
            showCustomURLInput()
        case .dohDebugLog:
            navigationController?.pushViewController(DohDebugLogViewController(), animated: true)
        case .cloudflareVerify:
            guard let baseURL = URL(string: ForumInstance.linuxDoBaseURL) else { return }
            Task { @MainActor [weak self] in
                await CloudflareBackgroundVerificationService.shared.beginForegroundVerification(
                    baseURL: baseURL
                )
                guard let self, let navigationController = self.navigationController else {
                    CloudflareBackgroundVerificationService.shared.endForegroundVerification(
                        baseURL: baseURL
                    )
                    return
                }
                let vc = CloudflareVerificationViewController(baseURL: baseURL) { [weak self] in
                    CloudflareBackgroundVerificationService.shared.endForegroundVerification(
                        baseURL: baseURL
                    )
                    self?.tableView.reloadData()
                }
                navigationController.pushViewController(vc, animated: true)
            }
        case .bottomBarLayout:
            navigationController?.pushViewController(BottomBarLayoutViewController(), animated: true)
        case .clearImageCache:
            clearImageCache()
        #if DEBUG
        case .renderPreview:
            showRenderPreviewInput()
        #endif
        default:
            break
        }
    }
}

private extension SettingsCategoryViewController {
    @objc func autoOpenToggleChanged(_ sender: UISwitch) {
        settings.autoOpenLastForum = sender.isOn
    }

    @objc func readingComfortChanged(_ sender: UISwitch) {
        settings.readingComfortMode = sender.isOn
    }

    @objc func hideScrollIndicatorsChanged(_ sender: UISwitch) {
        settings.hideScrollIndicators = sender.isOn
    }

    @objc func bottomAutoHideChanged(_ sender: UISwitch) {
        settings.bottomBarAutoHideEnabled = sender.isOn
    }

    func bottomBarLayoutSummary() -> String {
        let visibleItems = settings.forumVisibleDynamicTabItems.map(\.title).joined(separator: " / ")
        if visibleItems.isEmpty {
            return "首页 + 我的"
        }
        return "首页 + \(visibleItems) + 我的"
    }

    @objc func dohToggleChanged(_ sender: UISwitch) {
        settings.dohEnabled = sender.isOn
        LightweightDohProxyService.shared.configureFromSettings()
        tableView.reloadData()
    }

    func showAppearancePicker(sourceView: UIView?) {
        let alert = UIAlertController(title: String(localized: "settings.dark_mode"), message: nil, preferredStyle: .actionSheet)
        for mode in AppSettings.AppearanceMode.allCases {
            let action = UIAlertAction(title: mode.title, style: .default) { [weak self] _ in
                self?.settings.appearanceMode = mode
                self?.tableView.reloadData()
            }
            action.setValue(mode == settings.appearanceMode, forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true)
    }

    func showLanguagePicker(sourceView: UIView?) {
        let alert = UIAlertController(
            title: String(localized: "settings.language"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for language in AppSettings.AppLanguage.allCases {
            let action = UIAlertAction(title: language.title, style: .default) { [weak self] _ in
                guard let self else { return }
                settings.appLanguage = language
                tableView.reloadData()
            }
            action.setValue(language == settings.appLanguage, forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true)
    }

    func showThemeStylePicker(sourceView: UIView?) {
        let alert = UIAlertController(title: String(localized: "settings.theme_style"), message: nil, preferredStyle: .actionSheet)
        for style in AppSettings.ThemeStyle.allCases {
            let action = UIAlertAction(title: style.title, style: .default) { [weak self] _ in
                guard let self else { return }
                settings.themeStyle = style
                tableView.reloadData()
            }
            action.setValue(style == settings.themeStyle, forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true)
    }

    func showContentFontSizePicker(sourceView: UIView?) {
        let alert = UIAlertController(title: String(localized: "settings.content_font_size"), message: nil, preferredStyle: .actionSheet)
        let presetValues = [30, 50, 70, 90, 100, 110, 120, 150]
        for value in presetValues {
            let action = UIAlertAction(title: "\(value)%", style: .default) { [weak self] _ in
                guard let self else { return }
                settings.contentFontSize = .standard
                settings.contentFontScalePercent = value
                tableView.reloadData()
            }
            action.setValue(value == settings.contentFontScalePercent, forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true)
    }

    func showDohProviderPicker(sourceView: UIView?) {
        let alert = UIAlertController(title: String(localized: "settings.network.provider"), message: nil, preferredStyle: .actionSheet)
        for provider in AppSettings.DoHProvider.allCases {
            let action = UIAlertAction(title: provider.title, style: .default) { [weak self] _ in
                self?.settings.dohProvider = provider
                LightweightDohProxyService.shared.configureFromSettings()
                self?.tableView.reloadData()
            }
            action.setValue(provider == settings.dohProvider, forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView ?? view
        alert.popoverPresentationController?.sourceRect = sourceView?.bounds ?? view.bounds
        present(alert, animated: true)
    }

    func showCustomURLInput() {
        let alert = UIAlertController(
            title: String(localized: "settings.network.custom_url"),
            message: String(localized: "settings.network.custom_url.message"),
            preferredStyle: .alert
        )
        alert.addTextField { [weak self] textField in
            guard let self else { return }
            textField.text = settings.dohCustomURL.isEmpty ? settings.dohServerURL : settings.dohCustomURL
            textField.placeholder = "https://dns.alidns.com/dns-query"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default) { [weak self] _ in
            let value = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self?.settings.dohCustomURL = value
            if !value.isEmpty {
                self?.settings.dohProvider = .custom
            }
            LightweightDohProxyService.shared.configureFromSettings()
            self?.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    func clearImageCache() {
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk { [weak self] in
            let alert = UIAlertController(
                title: nil,
                message: String(localized: "settings.data.cache_cleared"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
            self?.present(alert, animated: true)
        }
    }

    #if DEBUG
    func showRenderPreviewInput() {
        let alert = UIAlertController(title: "Render Preview", message: "Enter Topic URL", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "https://linux.do/t/topic/12345"
            textField.keyboardType = .URL
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Open", style: .default) { [weak self] _ in
            guard let self,
                  let text = alert.textFields?.first?.text,
                  let url = URL(string: text),
                  let host = url.host,
                  let topicId = url.pathComponents.last.flatMap(Int.init)
            else { return }
            let scheme = url.scheme ?? "https"
            let api = DiscourseAPI(baseURL: "\(scheme)://\(host)")
            let vc = TopicDetailViewController(api: api, topicId: topicId)
            self.navigationController?.pushViewController(vc, animated: true)
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }
    #endif
}

private final class DataManagementSettingsViewController: ObservableViewController {
    private enum CacheRow: Int, CaseIterable {
        case image
        case aiChat
        case cookie
        case all

        var title: String {
            switch self {
            case .image: return String(localized: "settings.data.image_cache")
            case .aiChat: return String(localized: "settings.data.ai_chat")
            case .cookie: return String(localized: "settings.data.cookie_cache")
            case .all: return String(localized: "settings.data.clear_all_cache")
            }
        }

        var symbolName: String {
            switch self {
            case .image: return "photo"
            case .aiChat: return "ellipsis.bubble"
            case .cookie: return "globe.badge.chevron.backward"
            case .all: return "trash"
            }
        }

    }

    private enum BackupRow: Int, CaseIterable {
        case export
        case `import`

        var title: String {
            switch self {
            case .export: return String(localized: "settings.data.export")
            case .import: return String(localized: "settings.data.import")
            }
        }

        var subtitle: String {
            switch self {
            case .export: return String(localized: "settings.data.export.subtitle")
            case .import: return String(localized: "settings.data.import.subtitle")
            }
        }

        var symbolName: String {
            switch self {
            case .export: return "square.and.arrow.up"
            case .import: return "square.and.arrow.down"
            }
        }
    }

    private let settings = AppSettings.shared
    private var imageCacheSize: Int64 = 0
    private weak var heroCard: DataManagementHeroCardView?
    private weak var autoClearCard: DataManagementToggleCardView?
    private var cacheCards: [CacheRow: DataManagementCacheTileView] = [:]
    private var backupRows: [BackupRow: DataManagementActionRowView] = [:]

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
        stack.spacing = 22
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 32, trailing: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var cookieCacheSize: Int64 {
        WebCookieStore.shared.persistedDataSize()
    }

    private var appLocalCacheSize: Int64 {
        MeProfileCacheStore.cacheSize() + EmojiStore.cacheSize()
    }

    private var allCacheSize: Int64 {
        imageCacheSize + cookieCacheSize + appLocalCacheSize
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "settings.data_management")
        configureRootView()
        rebuildContent()
        reloadCacheSizes()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        reloadCacheSizes()
    }

    override func updateUI() {
        title = String(localized: "settings.data_management")
        rebuildContent()
        refreshDataViews()
    }

    private func configureRootView() {
        view.backgroundColor = DataManagementPalette.screenBackground
        view.tintColor = settings.themeStyle.accentColor
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
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        cacheCards.removeAll()
        backupRows.removeAll()
        heroCard = nil
        autoClearCard = nil

        let hero = DataManagementHeroCardView()
        heroCard = hero
        contentStack.addArrangedSubview(hero)
        contentStack.addArrangedSubview(makeCacheSection())
        contentStack.addArrangedSubview(makeAutomaticSection())
        contentStack.addArrangedSubview(makeBackupSection())
    }

    private func makeCacheSection() -> UIView {
        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false

        let rows: [[CacheRow]] = [
            [.image, .cookie],
            [.aiChat, .all],
        ]
        for rowItems in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 12
            rowStack.distribution = .fillEqually
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            for item in rowItems {
                let card = DataManagementCacheTileView()
                card.heightAnchor.constraint(greaterThanOrEqualToConstant: 136).isActive = true
                card.addAction(UIAction { [weak self] _ in
                    guard let self, self.canClear(item) else { return }
                    self.handleCacheRow(item)
                }, for: .touchUpInside)
                rowStack.addArrangedSubview(card)
                cacheCards[item] = card
            }
            grid.addArrangedSubview(rowStack)
        }
        return makeSection(
            title: String(localized: "settings.data.cache_management"),
            symbolName: "externaldrive.badge.icloud",
            body: grid
        )
    }

    private func makeAutomaticSection() -> UIView {
        let card = DataManagementToggleCardView()
        card.addAction(UIAction { [weak self, weak card] _ in
            guard let self, let card else { return }
            let newValue = !self.settings.clearImageCacheOnLaunch
            card.setOn(newValue, animated: true)
            self.settings.clearImageCacheOnLaunch = newValue
        }, for: .touchUpInside)
        card.onValueChanged = { [weak self] isOn in
            self?.settings.clearImageCacheOnLaunch = isOn
        }
        autoClearCard = card
        return makeSection(
            title: String(localized: "settings.data.automatic_management"),
            symbolName: "trash.circle",
            body: card
        )
    }

    private func makeBackupSection() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        for row in BackupRow.allCases {
            let actionRow = DataManagementActionRowView()
            actionRow.addAction(UIAction { [weak self] _ in
                switch row {
                case .export:
                    self?.exportPreferences()
                case .import:
                    self?.importPreferences()
                }
            }, for: .touchUpInside)
            stack.addArrangedSubview(actionRow)
            backupRows[row] = actionRow
        }
        return makeSection(
            title: String(localized: "settings.data.backup"),
            symbolName: "icloud.and.arrow.up",
            body: stack
        )
    }

    private func makeSection(title: String, symbolName: String, body: UIView) -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 12
        section.translatesAutoresizingMaskIntoConstraints = false
        section.addArrangedSubview(DataManagementSectionHeaderView(title: title, symbolName: symbolName, tintColor: settings.themeStyle.accentColor))
        section.addArrangedSubview(body)
        return section
    }

    private func reloadCacheSizes() {
        SDImageCache.shared.calculateSize { [weak self] _, totalSize in
            DispatchQueue.main.async {
                self?.imageCacheSize = Int64(totalSize)
                self?.refreshDataViews()
            }
        }
    }

    private func refreshDataViews() {
        view.backgroundColor = DataManagementPalette.screenBackground
        view.tintColor = settings.themeStyle.accentColor
        let cardBackground = settings.themeStyle.topicCardBackgroundColor
        heroCard?.configure(
            title: String(localized: "settings.data.hero.title"),
            subtitle: String(localized: "settings.data.hero.subtitle"),
            totalTitle: String(localized: "settings.data.cache_footprint"),
            totalSize: formattedSize(allCacheSize),
            imageTitle: String(localized: "settings.data.image_cache"),
            imageSize: formattedSize(imageCacheSize),
            cookieTitle: String(localized: "settings.data.cookie_cache"),
            cookieSize: formattedSize(cookieCacheSize),
            localTitle: String(localized: "settings.data.local_cache"),
            localSize: formattedSize(appLocalCacheSize),
            accentColor: settings.themeStyle.accentColor
        )

        for row in CacheRow.allCases {
            cacheCards[row]?.configure(
                title: row.title,
                detail: cacheDetailText(for: row),
                actionTitle: String(localized: "settings.data.clear"),
                symbolName: row.symbolName,
                tintColor: tintColor(for: row),
                backgroundColor: cardBackground,
                enabled: canClear(row),
                destructive: row == .all
            )
        }

        autoClearCard?.configure(
            title: String(localized: "settings.data.clear_image_on_launch"),
            subtitle: String(localized: "settings.data.clear_image_on_launch.subtitle"),
            symbolName: "trash.circle",
            isOn: settings.clearImageCacheOnLaunch,
            accentColor: settings.themeStyle.accentColor,
            backgroundColor: cardBackground
        )

        for row in BackupRow.allCases {
            backupRows[row]?.configure(
                title: row.title,
                subtitle: row.subtitle,
                symbolName: row.symbolName,
                tintColor: settings.themeStyle.accentColor,
                backgroundColor: cardBackground
            )
        }
    }
}

private extension DataManagementSettingsViewController {
    private func cacheDetailText(for row: CacheRow) -> String {
        switch row {
        case .image:
            return formattedSize(imageCacheSize)
        case .aiChat:
            return String(localized: "settings.data.no_cache")
        case .cookie:
            return formattedSize(cookieCacheSize)
        case .all:
            return formattedSize(allCacheSize)
        }
    }

    private func tintColor(for row: CacheRow) -> UIColor {
        switch row {
        case .image:
            return DataManagementPalette.secondaryBlue
        case .aiChat:
            return .systemIndigo
        case .cookie:
            return .systemTeal
        case .all:
            return .systemRed
        }
    }

    private func canClear(_ row: CacheRow) -> Bool {
        switch row {
        case .image:
            return imageCacheSize > 0
        case .aiChat:
            return false
        case .cookie:
            return cookieCacheSize > 0
        case .all:
            return allCacheSize > 0
        }
    }

    private func formattedSize(_ size: Int64) -> String {
        guard size > 0 else {
            return String(localized: "settings.data.no_cache")
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: size)
    }

    private func handleCacheRow(_ row: CacheRow) {
        switch row {
        case .image:
            clearImageCache(showCompletion: true)
        case .aiChat:
            break
        case .cookie:
            confirm(
                title: String(localized: "settings.data.clear_cookie.confirm.title"),
                message: String(localized: "settings.data.clear_cookie.confirm.message"),
                destructiveTitle: String(localized: "settings.data.clear")
            ) { [weak self] in
                self?.clearCookieCache(showCompletion: true)
            }
        case .all:
            confirm(
                title: String(localized: "settings.data.clear_all.confirm.title"),
                message: String(localized: "settings.data.clear_all.confirm.message"),
                destructiveTitle: String(localized: "settings.data.clear")
            ) { [weak self] in
                self?.clearAllCaches()
            }
        }
    }

    func clearImageCache(showCompletion: Bool, completion: (() -> Void)? = nil) {
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk { [weak self] in
            DispatchQueue.main.async {
                self?.reloadCacheSizes()
                if showCompletion {
                    self?.showMessage(String(localized: "settings.data.image_cache_cleared"))
                }
                completion?()
            }
        }
    }

    func clearCookieCache(showCompletion: Bool, completion: (() -> Void)? = nil) {
        Task { @MainActor [weak self] in
            AuthManager.shared.invalidateWebSession(for: ForumInstance.linuxDoBaseURL)
            await WebCookieStore.shared.clearWebViewCookies(for: ForumInstance.linuxDoBaseURL)
            self?.reloadCacheSizes()
            if showCompletion {
                self?.showMessage(String(localized: "settings.data.cookie_cache_cleared"))
            }
            completion?()
        }
    }

    func clearAllCaches() {
        clearImageCache(showCompletion: false) { [weak self] in
            MeProfileCacheStore.clearAll()
            EmojiStore.clearCache()
            self?.clearCookieCache(showCompletion: false) {
                self?.reloadCacheSizes()
                self?.showMessage(String(localized: "settings.data.all_cache_cleared"))
            }
        }
    }

    func confirm(title: String, message: String, destructiveTitle: String, action: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: destructiveTitle, style: .destructive) { _ in
            action()
        })
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    func exportPreferences() {
        do {
            let data = try settings.makePreferencesBackupData()
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Dexo-Preferences-\(Self.backupTimestamp()).json")
            try data.write(to: fileURL, options: .atomic)
            let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = view.bounds
            present(activity, animated: true)
        } catch {
            showError(error.localizedDescription)
        }
    }

    func importPreferences() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func showMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }

    func showError(_ message: String) {
        let alert = UIAlertController(
            title: String(localized: "settings.operation_failed"),
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }

    static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private enum DataManagementPalette {
    static let dataBlue = UIColor(red: 0.12, green: 0.25, blue: 0.69, alpha: 1)
    static let secondaryBlue = UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1)
    static let deepBlue = UIColor(red: 0.06, green: 0.12, blue: 0.27, alpha: 1)
    static let amber = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1)

    static var screenBackground: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.04, green: 0.07, blue: 0.12, alpha: 1)
                : UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
        }
    }

    static var borderColor: UIColor {
        UIColor.separator.withAlphaComponent(0.22)
    }
}

private final class DataManagementSectionHeaderView: UIView {
    private let iconView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        return label
    }()

    init(title: String, symbolName: String, tintColor: UIColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        iconView.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold))
        iconView.tintColor = tintColor
        addSubview(iconView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    func setTintColor(_ color: UIColor) {
        iconView.tintColor = color
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class DataManagementHeroCardView: UIView {
    private let gradientLayer = CAGradientLayer()
    private var accentColor = DataManagementPalette.dataBlue

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 22, weight: .heavy)
        label.textColor = .white
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.72)
        label.numberOfLines = 2
        return label
    }()

    private let badgeLabel: UILabel = {
        let label = UILabel()
        label.text = "DexoFlux"
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = UIColor(red: 0.18, green: 0.12, blue: 0.02, alpha: 1)
        label.textAlignment = .center
        label.backgroundColor = DataManagementPalette.amber
        label.layer.cornerRadius = 12
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private let totalTitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.70)
        return label
    }()

    private let totalSizeLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 36, weight: .black)
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.56
        return label
    }()

    private let imageMetric = DataManagementMetricPillView()
    private let cookieMetric = DataManagementMetricPillView()
    private let localMetric = DataManagementMetricPillView()

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
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = layer.cornerRadius
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateGradient()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 216).isActive = true
        layer.cornerRadius = 28
        layer.cornerCurve = .continuous
        clipsToBounds = true
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.insertSublayer(gradientLayer, at: 0)
        updateGradient()

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 4
        titleStack.isUserInteractionEnabled = false

        let topRow = UIStackView(arrangedSubviews: [titleStack, badgeLabel])
        topRow.axis = .horizontal
        topRow.alignment = .top
        topRow.spacing = 12
        topRow.isUserInteractionEnabled = false
        badgeLabel.heightAnchor.constraint(equalToConstant: 24).isActive = true
        badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        let totalStack = UIStackView(arrangedSubviews: [totalTitleLabel, totalSizeLabel])
        totalStack.axis = .vertical
        totalStack.spacing = 3
        totalStack.isUserInteractionEnabled = false

        let metricStack = UIStackView(arrangedSubviews: [imageMetric, cookieMetric, localMetric])
        metricStack.axis = .horizontal
        metricStack.spacing = 8
        metricStack.distribution = .fillEqually
        metricStack.isUserInteractionEnabled = false

        let contentStack = UIStackView(arrangedSubviews: [topRow, totalStack, metricStack])
        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 22, leading: 22, bottom: 18, trailing: 22)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.isUserInteractionEnabled = false
        addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(
        title: String,
        subtitle: String,
        totalTitle: String,
        totalSize: String,
        imageTitle: String,
        imageSize: String,
        cookieTitle: String,
        cookieSize: String,
        localTitle: String,
        localSize: String,
        accentColor: UIColor
    ) {
        self.accentColor = accentColor
        titleLabel.text = title
        subtitleLabel.text = subtitle
        totalTitleLabel.text = totalTitle
        totalSizeLabel.text = totalSize
        imageMetric.configure(title: imageTitle, value: imageSize)
        cookieMetric.configure(title: cookieTitle, value: cookieSize)
        localMetric.configure(title: localTitle, value: localSize)
        updateGradient()
    }

    private func updateGradient() {
        let resolvedAccent = accentColor.resolvedColor(with: traitCollection)
        let resolvedBlue = DataManagementPalette.dataBlue.resolvedColor(with: traitCollection)
        let resolvedDeep = DataManagementPalette.deepBlue.resolvedColor(with: traitCollection)
        gradientLayer.colors = [
            resolvedAccent.cgColor,
            resolvedBlue.cgColor,
            resolvedDeep.cgColor,
        ]
        gradientLayer.locations = [0, 0.52, 1]
    }
}

private final class DataManagementMetricPillView: UIView {
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = UIColor.white.withAlphaComponent(0.68)
        label.numberOfLines = 1
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.72
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = UIColor.white.withAlphaComponent(0.13)
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 9, leading: 10, bottom: 9, trailing: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
    }
}

private final class DataManagementCacheTileView: UIControl {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let actionLabel = UILabel()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
            }
        }
    }

    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.68
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
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = DataManagementPalette.borderColor.cgColor
        layer.shadowOpacity = 0.08
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 8)
        accessibilityTraits = [.button]

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 14
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.isUserInteractionEnabled = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 42),
            iconContainer.heightAnchor.constraint(equalToConstant: 42),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),
        ])

        actionLabel.font = .systemFont(ofSize: 12, weight: .bold)
        actionLabel.textAlignment = .center
        actionLabel.layer.cornerRadius = 12
        actionLabel.layer.cornerCurve = .continuous
        actionLabel.clipsToBounds = true
        actionLabel.isUserInteractionEnabled = false
        actionLabel.setContentHuggingPriority(.required, for: .horizontal)
        actionLabel.heightAnchor.constraint(equalToConstant: 24).isActive = true
        actionLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true

        let spacer = UIView()
        spacer.isUserInteractionEnabled = false
        let topRow = UIStackView(arrangedSubviews: [iconContainer, spacer, actionLabel])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = 8
        topRow.isUserInteractionEnabled = false

        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.isUserInteractionEnabled = false

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        detailLabel.textColor = .secondaryLabel
        detailLabel.adjustsFontSizeToFitWidth = true
        detailLabel.minimumScaleFactor = 0.78
        detailLabel.isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [topRow, titleLabel, detailLabel])
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    func configure(
        title: String,
        detail: String,
        actionTitle: String,
        symbolName: String,
        tintColor: UIColor,
        backgroundColor: UIColor,
        enabled: Bool,
        destructive: Bool
    ) {
        self.backgroundColor = backgroundColor
        isEnabled = enabled
        layer.shadowColor = tintColor.cgColor
        layer.borderColor = (enabled ? tintColor.withAlphaComponent(0.22) : DataManagementPalette.borderColor).cgColor

        let actionColor = destructive ? UIColor.systemRed : tintColor
        iconContainer.backgroundColor = actionColor.withAlphaComponent(enabled ? 0.16 : 0.10)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        iconView.tintColor = actionColor
        titleLabel.text = title
        detailLabel.text = detail
        actionLabel.text = enabled ? actionTitle : String(localized: "settings.data.no_cache")
        actionLabel.textColor = enabled ? actionColor : .secondaryLabel
        actionLabel.backgroundColor = (enabled ? actionColor : UIColor.secondaryLabel).withAlphaComponent(enabled ? 0.14 : 0.10)
        accessibilityLabel = "\(title)，\(detail)"
        accessibilityHint = enabled ? actionTitle : nil
        accessibilityTraits = enabled ? [.button] : [.staticText]
    }
}

private final class DataManagementToggleCardView: UIControl {
    var onValueChanged: ((Bool) -> Void)?

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggle = UISwitch()

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.99, y: 0.99) : .identity
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
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = DataManagementPalette.borderColor.cgColor
        layer.shadowOpacity = 0.07
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 7)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 15
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.isUserInteractionEnabled = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        iconContainer.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.isUserInteractionEnabled = false

        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isUserInteractionEnabled = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)

        addSubview(iconContainer)
        addSubview(textStack)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 46),
            iconContainer.heightAnchor.constraint(equalToConstant: 46),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 23),
            iconView.heightAnchor.constraint(equalToConstant: 23),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -14),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        accessibilityTraits = [.button]
    }

    func configure(
        title: String,
        subtitle: String,
        symbolName: String,
        isOn: Bool,
        accentColor: UIColor,
        backgroundColor: UIColor
    ) {
        self.backgroundColor = backgroundColor
        layer.shadowColor = accentColor.cgColor
        layer.borderColor = accentColor.withAlphaComponent(0.16).cgColor
        iconContainer.backgroundColor = accentColor.withAlphaComponent(0.14)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold))
        iconView.tintColor = accentColor
        titleLabel.text = title
        subtitleLabel.text = subtitle
        toggle.onTintColor = accentColor
        setOn(isOn, animated: false)
        accessibilityLabel = "\(title)，\(subtitle)"
    }

    func setOn(_ isOn: Bool, animated: Bool) {
        toggle.setOn(isOn, animated: animated)
    }

    @objc private func toggleChanged(_ sender: UISwitch) {
        onValueChanged?(sender.isOn)
    }
}

private final class DataManagementActionRowView: UIControl {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chevronView = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.alpha = self.isHighlighted ? 0.76 : 1
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.99, y: 0.99) : .identity
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
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 66).isActive = true
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = DataManagementPalette.borderColor.cgColor
        layer.shadowOpacity = 0.07
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 5)

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 13
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.isUserInteractionEnabled = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        iconContainer.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.isUserInteractionEnabled = false

        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isUserInteractionEnabled = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false

        chevronView.tintColor = .tertiaryLabel
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.isUserInteractionEnabled = false

        addSubview(iconContainer)
        addSubview(textStack)
        addSubview(chevronView)
        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -14),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 18),
        ])
        accessibilityTraits = [.button]
    }

    func configure(title: String, subtitle: String, symbolName: String, tintColor: UIColor, backgroundColor: UIColor) {
        self.backgroundColor = backgroundColor
        layer.shadowColor = tintColor.cgColor
        layer.borderColor = tintColor.withAlphaComponent(0.14).cgColor
        iconContainer.backgroundColor = tintColor.withAlphaComponent(0.14)
        iconView.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        iconView.tintColor = tintColor
        titleLabel.text = title
        subtitleLabel.text = subtitle
        accessibilityLabel = "\(title)，\(subtitle)"
    }

}

extension DataManagementSettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            try settings.importPreferencesBackupData(data)
            LightweightDohProxyService.shared.configureFromSettings()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            reloadCacheSizes()
            showMessage(String(localized: "settings.data.import_success"))
        } catch {
            showError(error.localizedDescription)
        }
    }
}

private final class PaddingLabel: UILabel {
    var contentInsets = UIEdgeInsets.zero {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }
}

private final class BottomBarLayoutViewController: ObservableViewController {
    private let settings = AppSettings.shared
    private let autoHideRow = ReadingToggleRowView()

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
        stack.spacing = 22
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 32, trailing: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "settings.bottom_bar")
        configureRootView()
        rebuildContent()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "恢复默认",
            style: .plain,
            target: self,
            action: #selector(restoreDefaultTapped)
        )
        autoHideRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.bottomBarAutoHideEnabled = isOn
            refreshDataViews()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        refreshDataViews()
    }

    override func updateUI() {
        title = String(localized: "settings.bottom_bar")
        rebuildContent()
    }

    @objc private func restoreDefaultTapped() {
        settings.resetForumDynamicTabItems()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        rebuildContent()
    }

    private var configuredItems: [AppSettings.ForumDynamicTabItem] {
        settings.forumDynamicTabItems
    }

    private var availableItems: [AppSettings.ForumDynamicTabItem] {
        let configured = Set(configuredItems)
        return AppSettings.ForumDynamicTabItem.allCases.filter { !configured.contains($0) }
    }

    private func setConfiguredItems(_ items: [AppSettings.ForumDynamicTabItem]) {
        settings.forumDynamicTabItems = items
        rebuildContent()
    }

    private func addAvailableItem(_ item: AppSettings.ForumDynamicTabItem) {
        guard configuredItems.count < AppSettings.maximumConfiguredForumDynamicTabItems else {
            showLimitMessage("最多保留 \(AppSettings.maximumConfiguredForumDynamicTabItems) 个功能候选。")
            return
        }

        setConfiguredItems(configuredItems + [item])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func removeConfiguredItem(at index: Int) {
        var items = configuredItems
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        setConfiguredItems(items)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func moveConfiguredItem(from index: Int, by delta: Int) {
        var items = configuredItems
        let target = index + delta
        guard items.indices.contains(index), items.indices.contains(target) else { return }
        let item = items.remove(at: index)
        items.insert(item, at: target)
        setConfiguredItems(items)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func actualBottomBarSummary() -> String {
        let visibleTitles = settings.forumVisibleDynamicTabItems.map(\.title)
        if visibleTitles.isEmpty {
            return "当前实际底栏：首页 + 我的。"
        }
        return "当前实际底栏：首页 + \(visibleTitles.joined(separator: " / ")) + 我的。"
    }

    private func configureRootView() {
        view.backgroundColor = DataManagementPalette.screenBackground
        view.tintColor = settings.themeStyle.accentColor
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
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { view in
            contentStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        view.backgroundColor = DataManagementPalette.screenBackground
        view.tintColor = settings.themeStyle.accentColor

        contentStack.addArrangedSubview(makePreviewCard())
        contentStack.addArrangedSubview(makeEnabledSection())
        contentStack.addArrangedSubview(makeAvailableSection())
        contentStack.addArrangedSubview(makeBehaviorSection())
        refreshDataViews()
    }

    private func refreshDataViews() {
        autoHideRow.configure(
            title: String(localized: "settings.bottom_bar.auto_hide"),
            subtitle: "首页向上滑动隐藏底栏，向下滑动或回到顶部显示。",
            symbolName: "arrow.up.and.down",
            isOn: settings.bottomBarAutoHideEnabled,
            accentColor: settings.themeStyle.accentColor,
            backgroundColor: settings.themeStyle.topicCardBackgroundColor
        )
    }

    private func makePreviewCard() -> UIView {
        let card = makeCard()
        card.layer.shadowOpacity = 0.08
        card.layer.shadowRadius = 18
        card.layer.shadowOffset = CGSize(width: 0, height: 10)
        card.layer.shadowColor = settings.themeStyle.accentColor.cgColor

        let eyebrow = makePillLabel(text: "当前配置", color: settings.themeStyle.accentColor)
        let title = UILabel()
        title.text = actualBottomBarSummary()
        title.font = .systemFont(ofSize: 20, weight: .heavy)
        title.textColor = .label
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = "首页固定第一位，我的固定末尾；系统底栏最多 5 个入口，前 \(AppSettings.maximumVisibleForumDynamicTabItems) 个功能项会优先显示。"
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        let previewRow = UIStackView()
        previewRow.axis = .horizontal
        previewRow.alignment = .center
        previewRow.spacing = 8
        previewRow.addArrangedSubview(makeMiniTab(title: String(localized: "tab.home"), symbolName: "house.fill", active: true))
        for (index, item) in settings.forumVisibleDynamicTabItems.enumerated() {
            previewRow.addArrangedSubview(makeMiniTab(
                title: item.title,
                symbolName: item.symbolName,
                active: true,
                removeAction: { [weak self] in
                    self?.removeConfiguredItem(at: index)
                }
            ))
        }
        previewRow.addArrangedSubview(makeMiniTab(title: String(localized: "tab.me"), symbolName: "person.crop.circle.fill", active: true))

        let eyebrowRow = UIStackView(arrangedSubviews: [eyebrow, UIView()])
        eyebrowRow.axis = .horizontal
        let stack = makeCardStack([eyebrowRow, title, subtitle, previewRow])
        stack.setCustomSpacing(10, after: subtitle)
        card.addSubview(stack)
        pin(stack, to: card)
        return card
    }

    private func makeEnabledSection() -> UIView {
        let stack = makeSectionStack(title: "底栏入口", symbolName: "rectangle.bottomthird.inset.filled")
        stack.addArrangedSubview(makeFixedItemRow(
            title: String(localized: "tab.home"),
            subtitle: "固定第一位",
            symbolName: "house.fill"
        ))
        for (index, item) in configuredItems.enumerated() {
            stack.addArrangedSubview(makeConfiguredItemRow(item: item, index: index))
        }
        return stack
    }

    private func makeAvailableSection() -> UIView {
        let stack = makeSectionStack(title: "可添加", symbolName: "plus.circle")
        if availableItems.isEmpty {
            stack.addArrangedSubview(makeInfoCard(text: "没有更多可添加。"))
            return stack
        }
        if configuredItems.count >= AppSettings.maximumConfiguredForumDynamicTabItems {
            stack.addArrangedSubview(makeInfoCard(text: "候选已满，先删除一个功能再添加。"))
        }
        for item in availableItems {
            stack.addArrangedSubview(makeAvailableItemRow(item: item))
        }
        return stack
    }

    private func makeBehaviorSection() -> UIView {
        let stack = makeSectionStack(title: "行为", symbolName: "hand.tap")
        stack.addArrangedSubview(autoHideRow)
        return stack
    }

    private func makeSectionStack(title: String, symbolName: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(DataManagementSectionHeaderView(title: title, symbolName: symbolName, tintColor: settings.themeStyle.accentColor))
        return stack
    }

    private func makeFixedItemRow(title: String, subtitle: String, symbolName: String) -> UIView {
        makeItemRow(
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            tintColor: settings.themeStyle.accentColor,
            accessory: makeLockBadge()
        )
    }

    private func makeConfiguredItemRow(item: AppSettings.ForumDynamicTabItem, index: Int) -> UIView {
        let accessory = UIStackView()
        accessory.axis = .horizontal
        accessory.alignment = .center
        accessory.spacing = 6

        let isVisible = index < AppSettings.maximumVisibleForumDynamicTabItems
        accessory.addArrangedSubview(makePillLabel(text: isVisible ? "显示" : "候选", color: isVisible ? settings.themeStyle.accentColor : .secondaryLabel))
        accessory.addArrangedSubview(makeActionButton(symbolName: "chevron.up", enabled: index > 0) { [weak self] in
            self?.moveConfiguredItem(from: index, by: -1)
        })
        accessory.addArrangedSubview(makeActionButton(symbolName: "chevron.down", enabled: index < configuredItems.count - 1) { [weak self] in
            self?.moveConfiguredItem(from: index, by: 1)
        })
        accessory.addArrangedSubview(makeActionButton(symbolName: "minus", enabled: true, color: .systemRed) { [weak self] in
            self?.removeConfiguredItem(at: index)
        })

        return makeItemRow(
            title: item.title,
            subtitle: isVisible ? "显示在底栏" : "候选保留，暂不显示",
            symbolName: item.symbolName,
            tintColor: isVisible ? settings.themeStyle.accentColor : .secondaryLabel,
            accessory: accessory
        )
    }

    private func makeAvailableItemRow(item: AppSettings.ForumDynamicTabItem) -> UIView {
        let canAdd = configuredItems.count < AppSettings.maximumConfiguredForumDynamicTabItems
        let accessory = makeActionButton(symbolName: "plus", enabled: canAdd, color: settings.themeStyle.accentColor) { [weak self] in
            self?.addAvailableItem(item)
        }
        return makeItemRow(
            title: item.title,
            subtitle: item.subtitle,
            symbolName: item.symbolName,
            tintColor: canAdd ? settings.themeStyle.accentColor : .tertiaryLabel,
            accessory: accessory,
            enabled: canAdd
        )
    }

    private func makeItemRow(
        title: String,
        subtitle: String,
        symbolName: String,
        tintColor: UIColor,
        accessory: UIView,
        enabled: Bool = true
    ) -> UIView {
        let card = makeCard()
        card.alpha = enabled ? 1 : 0.62

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = tintColor.withAlphaComponent(0.14)
        iconContainer.layer.cornerRadius = 13
        iconContainer.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentMode = .scaleAspectFit
        icon.tintColor = tintColor
        iconContainer.addSubview(icon)
        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 40),
            iconContainer.heightAnchor.constraint(equalToConstant: 40),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = enabled ? .label : .secondaryLabel

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [iconContainer, textStack, accessory])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        card.addSubview(row)
        pin(row, to: card)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        return card
    }

    private func makeInfoCard(text: String) -> UIView {
        let card = makeCard()
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func makeCard() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = settings.themeStyle.topicCardBackgroundColor
        view.layer.cornerRadius = 22
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = settings.themeStyle.accentColor.withAlphaComponent(0.12).cgColor
        return view
    }

    private func makeCardStack(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeMiniTab(
        title: String,
        symbolName: String,
        active: Bool,
        removeAction: (() -> Void)? = nil
    ) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = active ? settings.themeStyle.accentColor.withAlphaComponent(0.12) : UIColor.tertiarySystemFill
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = false

        let icon = UIImageView(image: UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
        icon.tintColor = active ? settings.themeStyle.accentColor : .secondaryLabel
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = active ? settings.themeStyle.accentColor : .secondaryLabel
        label.lineBreakMode = .byTruncatingTail

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 54),
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -6),
        ])

        if let removeAction {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 8, weight: .heavy)
            )
            config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)

            let removeButton = UIButton(configuration: config)
            removeButton.translatesAutoresizingMaskIntoConstraints = false
            removeButton.tintColor = .white
            removeButton.backgroundColor = UIColor.systemRed
            removeButton.layer.cornerRadius = 9
            removeButton.layer.cornerCurve = .continuous
            removeButton.accessibilityLabel = "移除\(title)"
            removeButton.addAction(UIAction { _ in removeAction() }, for: .touchUpInside)
            view.addSubview(removeButton)
            NSLayoutConstraint.activate([
                removeButton.widthAnchor.constraint(equalToConstant: 18),
                removeButton.heightAnchor.constraint(equalToConstant: 18),
                removeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
                removeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            ])
        }
        return view
    }

    private func makePillLabel(text: String, color: UIColor) -> UILabel {
        let label = PaddingLabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = color
        label.backgroundColor = color.withAlphaComponent(0.11)
        label.layer.cornerRadius = 12
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.contentInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        return label
    }

    private func makeLockBadge() -> UIView {
        let imageView = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)))
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
        ])
        return imageView
    }

    private func makeActionButton(
        symbolName: String,
        enabled: Bool,
        color: UIColor = .secondaryLabel,
        action: @escaping () -> Void
    ) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = enabled ? color : .tertiaryLabel
        button.backgroundColor = (enabled ? color : UIColor.tertiaryLabel).withAlphaComponent(enabled ? 0.12 : 0.06)
        button.layer.cornerRadius = 14
        button.layer.cornerCurve = .continuous
        button.isEnabled = enabled
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32),
        ])
        return button
    }

    private func pin(_ view: UIView, to container: UIView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    private func showLimitMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }
}

private final class DohDebugLogViewController: UIViewController {
    private lazy var textView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.textColor = .label
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.isEditable = false
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "调试日志"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "复制",
            style: .plain,
            target: self,
            action: #selector(copyLog)
        )

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        reloadLog()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        reloadLog()
    }

    private func reloadLog() {
        let log = DohDebugLog.snapshot()
        textView.text = log.isEmpty ? "暂无调试日志。刷新首页或重试网络请求。" : log
        if !textView.text.isEmpty {
            let length = (textView.text as NSString).length
            let bottom = NSRange(location: max(length - 1, 0), length: 1)
            textView.scrollRangeToVisible(bottom)
        }
    }

    @objc private func copyLog() {
        let log = DohDebugLog.snapshot()
        UIPasteboard.general.string = log.isEmpty ? textView.text : log
        let alert = UIAlertController(title: nil, message: "日志已复制", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }
}

enum CloudflareVerificationPolicy {
    static func verificationURL(baseURL: URL, responseURL: URL?) -> URL {
        _ = responseURL
        return URL(string: "/challenge", relativeTo: baseURL)?.absoluteURL ?? baseURL
    }

    static func hasUsableClearance(
        currentValue: String?,
        initialValue: String?,
        requiresFreshValue: Bool
    ) -> Bool {
        guard let currentValue, !currentValue.isEmpty else { return false }
        return !requiresFreshValue || currentValue != initialValue
    }

    static func canCompleteVerification(
        currentValue: String?,
        initialValue: String?,
        requiresFreshValue: Bool,
        hasVerifiedPage: Bool,
        hasActiveChallenge: Bool
    ) -> Bool {
        hasVerifiedPage
            && !hasActiveChallenge
            && hasUsableClearance(
                currentValue: currentValue,
                initialValue: initialValue,
                requiresFreshValue: requiresFreshValue
            )
    }

    static func isVerifiedChallengeLanding(
        _ response: HTTPURLResponse,
        baseURL: URL
    ) -> Bool {
        guard response.statusCode == 404,
              let responseURL = response.url,
              responseURL.scheme?.lowercased() == baseURL.scheme?.lowercased(),
              responseURL.host?.lowercased() == baseURL.host?.lowercased(),
              responseURL.port == baseURL.port,
              responseURL.path.lowercased() == "/challenge"
        else { return false }

        let cfMitigated = response.allHeaderFields.first { key, _ in
            "\(key)".caseInsensitiveCompare("cf-mitigated") == .orderedSame
        }.map { "\($0.value)".lowercased() }
        return cfMitigated?.contains("challenge") != true
    }
}

final class CloudflareVerificationViewController: UIViewController {
    private let baseURL: URL
    private let challengeURL: URL
    private let autoDismissOnSuccess: Bool
    private let onFinish: () -> Void
    private var progressObservation: NSKeyValueObservation?
    private var didDetectClearance = false
    private var isCheckingClearance = false
    private var needsVerificationRecheck = false
    private var initialClearanceValue: String?
    private var preparationTask: Task<Void, Never>?
    private var verificationCheckTask: Task<Void, Never>?
    private var didCallOnFinish = false
    private var preparationGeneration = 0
    private var isPreparingChallenge = false
    private var isClosing = false
    private var isCookieObserverRegistered = false
    private var didFinishVerifiedNavigation = false
    private var isFinishing = false
    private var failureCleanupTask: Task<Void, Never>?

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let statusContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        return view
    }()

    private let statusIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "shield.fill"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .systemOrange
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "cloudflare.verify.instructions")
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }()

    private let progressView: UIProgressView = {
        let view = UIProgressView(progressViewStyle: .bar)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    init(
        baseURL: URL,
        responseURL: URL? = nil,
        verificationURL: URL? = nil,
        autoDismissOnSuccess: Bool = false,
        onFinish: @escaping () -> Void
    ) {
        self.baseURL = baseURL
        self.challengeURL = verificationURL
            ?? CloudflareVerificationPolicy.verificationURL(
                baseURL: baseURL,
                responseURL: responseURL
            )
        self.autoDismissOnSuccess = autoDismissOnSuccess
        self.onFinish = onFinish
        self.initialClearanceValue = WebCookieStore.shared.cookieValue(
            named: "cf_clearance",
            for: baseURL
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor deinit {
        preparationTask?.cancel()
        verificationCheckTask?.cancel()
        failureCleanupTask?.cancel()
        if isCookieObserverRegistered {
            webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "cloudflare.verify.title")
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "weblogin.done"),
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(reloadTapped)
        )
        navigationItem.leftItemsSupplementBackButton = true

        statusContainer.addSubview(statusIconView)
        statusContainer.addSubview(statusLabel)
        view.addSubview(statusContainer)
        view.addSubview(progressView)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            statusContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            statusContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            statusIconView.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 16),
            statusIconView.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 12),
            statusIconView.widthAnchor.constraint(equalToConstant: 20),
            statusIconView.heightAnchor.constraint(equalToConstant: 20),
            statusIconView.bottomAnchor.constraint(lessThanOrEqualTo: statusContainer.bottomAnchor, constant: -12),

            statusLabel.leadingAnchor.constraint(equalTo: statusIconView.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: statusContainer.topAnchor, constant: 10),
            statusLabel.bottomAnchor.constraint(equalTo: statusContainer.bottomAnchor, constant: -10),

            progressView.topAnchor.constraint(equalTo: statusContainer.bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.progressView.progress = Float(webView.estimatedProgress)
                self.progressView.isHidden = webView.estimatedProgress >= 1.0
                guard webView.estimatedProgress >= 1.0 else { return }
                self.scheduleVerificationChecks()
            }
        }

        startChallengePreparation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let wasDismissed = isBeingDismissed
            || navigationController?.isBeingDismissed == true
            || isMovingFromParent
        guard wasDismissed else { return }
        isClosing = true
        if didDetectClearance {
            notifyFinishIfNeeded()
            return
        }
        Task { @MainActor [self] in
            await self.ensureFailureCleanup().value
            self.notifyFinishIfNeeded()
        }
    }

    @objc private func doneTapped() {
        guard !isFinishing else { return }
        isFinishing = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.didDetectClearance, !self.isPreparingChallenge {
                await self.cancelVerificationCheckTask()
                await self.syncCookiesAndDetectClearance()
            }
            if !self.didDetectClearance {
                await self.ensureFailureCleanup().value
            } else {
                self.isClosing = true
            }
            self.finishAndClose()
        }
    }

    @objc private func reloadTapped() {
        guard !isClosing else { return }
        log("foreground reload tapped base=\(baseURL.absoluteString)")
        didDetectClearance = false
        isCheckingClearance = false
        needsVerificationRecheck = false
        didFinishVerifiedNavigation = false
        preparationTask?.cancel()
        verificationCheckTask?.cancel()
        verificationCheckTask = nil
        updateStatus(
            text: String(localized: "cloudflare.verify.instructions"),
            symbolName: "shield.fill",
            color: .systemOrange
        )
        startChallengePreparation()
    }

    @MainActor
    private func startChallengePreparation() {
        preparationGeneration += 1
        let generation = preparationGeneration
        isPreparingChallenge = true
        didFinishVerifiedNavigation = false
        preparationTask = Task { @MainActor [weak self] in
            await self?.prepareAndLoadChallenge(generation: generation)
        }
    }

    @MainActor
    private func prepareAndLoadChallenge(generation: Int) async {
        defer {
            if generation == preparationGeneration {
                isPreparingChallenge = false
                preparationTask = nil
            }
        }
        guard !isClosing else { return }
        log(
            "foreground load challenge base=\(baseURL.absoluteString) url=\(challengeURL.absoluteString) autoDismiss=\(autoDismissOnSuccess)"
        )
        await WebCookieStore.shared.syncToWebView(
            webView.configuration.websiteDataStore,
            for: baseURL
        )
        guard generation == preparationGeneration, !Task.isCancelled, !isClosing else { return }
        if autoDismissOnSuccess {
            WebCookieStore.shared.deleteCookie(named: "cf_clearance", for: baseURL)
            await deleteWebViewCookie(named: "cf_clearance")
        }
        guard generation == preparationGeneration, !Task.isCancelled, !isClosing else { return }
        registerCookieObserverIfNeeded()
        var request = URLRequest(url: challengeURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        webView.load(request)
    }

    @MainActor
    private func registerCookieObserverIfNeeded() {
        guard !isCookieObserverRegistered else { return }
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
        isCookieObserverRegistered = true
    }

    @MainActor
    private func deleteWebViewCookie(named name: String) async {
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        guard let host = baseURL.host?.lowercased() else { return }
        for cookie in cookies where cookie.name == name {
            let domain = cookie.domain.lowercased()
            let domainMatch = host == domain
                || (domain.hasPrefix(".") && (host == String(domain.dropFirst()) || host.hasSuffix(domain)))
            guard domainMatch else { continue }
            await withCheckedContinuation { continuation in
                cookieStore.delete(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func syncCookiesAndDetectClearance() async {
        guard !didDetectClearance, !isPreparingChallenge, !isClosing else { return }
        if isCheckingClearance {
            needsVerificationRecheck = true
            return
        }

        isCheckingClearance = true
        defer {
            isCheckingClearance = false
            if needsVerificationRecheck, !didDetectClearance {
                scheduleVerificationChecks()
            }
        }

        repeat {
            needsVerificationRecheck = false
            await performVerificationCheck()
        } while needsVerificationRecheck && !didDetectClearance
    }

    @MainActor
    private func performVerificationCheck() async {
        if await hasLoadedKnownVerifiedNotFoundPage() {
            await completeKnownVerifiedLanding(
                reason: "foreground known verified not-found page"
            )
            return
        }

        await syncCloudflareCookieFromWebView()
        guard !Task.isCancelled, !isClosing else { return }
        let clearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL)
        let hasVerifiedPage = await hasLoadedVerifiedBasePage()
        guard !Task.isCancelled, !isClosing else { return }
        let hasActiveChallenge = hasVerifiedPage ? await pageHasActiveCloudflareChallenge() : true
        let canComplete = CloudflareVerificationPolicy.canCompleteVerification(
            currentValue: clearanceValue,
            initialValue: initialClearanceValue,
            requiresFreshValue: autoDismissOnSuccess,
            hasVerifiedPage: hasVerifiedPage,
            hasActiveChallenge: hasActiveChallenge
        )
        log(
            "foreground check url=\(webView.url?.absoluteString ?? "none") cf=\(clearanceValue?.isEmpty == false) verifiedPage=\(hasVerifiedPage) activeChallenge=\(hasActiveChallenge) complete=\(canComplete)"
        )
        guard canComplete else {
            if hasVerifiedPage {
                log("foreground verified page loaded but verification state is incomplete; waiting")
            }
            return
        }
        await updateStoredUserAgentFromWebView()
        completeVerification()
    }

    @MainActor
    private func completeIfKnownVerifiedRedirect(_ url: URL?) async {
        guard isKnownVerifiedRedirectURL(url) else { return }
        await completeKnownVerifiedLanding(
            reason: "foreground known verified redirect url=\(url?.absoluteString ?? "none")"
        )
    }

    @MainActor
    private func completeKnownVerifiedLanding(reason: String) async {
        guard !didDetectClearance, !isClosing else { return }
        log(reason)
        await syncCloudflareCookieFromWebView()
        await updateStoredUserAgentFromWebView()
        completeVerification()
    }

    @MainActor
    private func syncCloudflareCookieFromWebView() async {
        await WebCookieStore.shared.syncFromWebView(
            webView.configuration.websiteDataStore,
            names: ["cf_clearance"],
            for: baseURL
        )
    }

    @MainActor
    private func updateStoredUserAgentFromWebView() async {
        if let userAgent = try? await webView.evaluateJavaScript("navigator.userAgent") as? String {
            WebCookieStore.shared.userAgent = userAgent
        }
    }

    @MainActor
    private func cancelVerificationCheckTask() async {
        let task = verificationCheckTask
        verificationCheckTask = nil
        task?.cancel()
        await task?.value
    }

    @MainActor
    private func cancelPendingVerificationWork() async {
        isClosing = true
        preparationGeneration += 1
        let preparation = preparationTask
        preparationTask = nil
        preparation?.cancel()
        await preparation?.value
        isPreparingChallenge = false
        await cancelVerificationCheckTask()
    }

    @MainActor
    private func ensureFailureCleanup() -> Task<Void, Never> {
        if let failureCleanupTask {
            return failureCleanupTask
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.cancelPendingVerificationWork()
        }
        failureCleanupTask = task
        return task
    }

    @MainActor
    private func completeVerification() {
        guard !didDetectClearance else { return }
        log("foreground complete base=\(baseURL.absoluteString)")
        didDetectClearance = true
        needsVerificationRecheck = false
        verificationCheckTask?.cancel()
        verificationCheckTask = nil
        updateStatus(
            text: String(localized: "cloudflare.verify.success"),
            symbolName: "checkmark.shield.fill",
            color: .systemGreen
        )
        NotificationCenter.default.post(
            name: DiscourseAPI.cloudflareVerificationCompletedNotification,
            object: nil,
            userInfo: [
                DiscourseAPI.cloudflareBaseURLUserInfoKey: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
            ]
        )
        guard autoDismissOnSuccess else { return }
        isFinishing = true
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.leftBarButtonItem?.isEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @MainActor
    private func completeFromVerifiedChallengeLanding() async {
        guard !didDetectClearance, !isClosing else { return }
        await syncCloudflareCookieFromWebView()
        try? await Task.sleep(nanoseconds: 150_000_000)
        await syncCloudflareCookieFromWebView()
        await updateStoredUserAgentFromWebView()
        log("foreground complete from origin /challenge 404")
        completeVerification()
    }

    @MainActor
    private func notifyFinishIfNeeded() {
        guard !didCallOnFinish else { return }
        didCallOnFinish = true
        onFinish()
    }

    @MainActor
    private func finishAndClose() {
        if navigationController?.viewControllers.first === self,
           navigationController?.presentingViewController != nil {
            navigationController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @MainActor
    private func hasLoadedVerifiedBasePage() async -> Bool {
        guard didFinishVerifiedNavigation,
              let currentURL = webView.url,
              let currentHost = currentURL.host?.lowercased(),
              let baseHost = baseURL.host?.lowercased()
        else { return false }

        let hostMatches = currentHost == baseHost || currentHost.hasSuffix(".\(baseHost)")
        guard hostMatches else { return false }

        let path = currentURL.path.lowercased()
        guard !path.contains("/cdn-cgi/") else { return false }
        return !(await pageHasActiveCloudflareChallenge())
    }

    private func isKnownVerifiedRedirectURL(_ url: URL?) -> Bool {
        guard let url,
              let currentHost = url.host?.lowercased(),
              let baseHost = baseURL.host?.lowercased()
        else { return false }

        let hostMatches = currentHost == baseHost || currentHost.hasSuffix(".\(baseHost)")
        guard hostMatches else { return false }

        let path = url.path.lowercased()
        return path == "/404" || path == "/404/"
    }

    @MainActor
    private func hasLoadedKnownVerifiedNotFoundPage() async -> Bool {
        guard didFinishVerifiedNavigation,
              let currentURL = webView.url,
              let currentHost = currentURL.host?.lowercased(),
              let baseHost = baseURL.host?.lowercased()
        else { return false }

        let hostMatches = currentHost == baseHost || currentHost.hasSuffix(".\(baseHost)")
        guard hostMatches, !currentURL.path.lowercased().contains("/cdn-cgi/") else {
            return false
        }

        guard let pageText = try? await webView.evaluateJavaScript("""
            [
              document.title || '',
              document.body ? document.body.innerText : ''
            ].join('\\n')
            """) as? String,
            !Self.hasActiveCloudflareChallenge(in: pageText)
        else { return false }

        let lowerText = pageText.lowercased()
        return lowerText.contains("该页面不存在")
            || lowerText.contains("該頁面不存在")
            || lowerText.contains("that page doesn't exist")
            || lowerText.contains("that page doesn’t exist")
    }

    @MainActor
    private func pageHasActiveCloudflareChallenge() async -> Bool {
        guard let pageText = try? await webView.evaluateJavaScript("""
            [
              document.title || '',
              document.body ? document.body.innerText : '',
              document.body ? document.body.innerHTML : ''
            ].join('\\n')
            """) as? String else { return true }
        return Self.hasActiveCloudflareChallenge(in: pageText)
    }

    @MainActor
    private func scheduleVerificationChecks() {
        guard !didDetectClearance, !isPreparingChallenge, !isClosing else { return }
        verificationCheckTask?.cancel()
        verificationCheckTask = Task { @MainActor [weak self] in
            let delays: [UInt64] = [
                0,
                250_000_000,
                700_000_000,
                1_500_000_000,
                2_500_000_000,
                4_000_000_000,
                7_000_000_000,
                10_000_000_000,
            ]
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled, let self, !self.didDetectClearance else { return }
                await self.syncCookiesAndDetectClearance()
            }
        }
    }

    private static func hasActiveCloudflareChallenge(in pageText: String) -> Bool {
        let lowerText = pageText.lowercased()
        return lowerText.contains("cf-turnstile")
            || lowerText.contains("challenge-running")
            || lowerText.contains("challenge-stage")
            || lowerText.contains("cf_chl_opt")
            || lowerText.contains("challenge-platform")
            || (lowerText.contains("just a moment") && lowerText.contains("cloudflare"))
    }

    private func failingURL(from error: Error) -> URL? {
        let nsError = error as NSError
        if let url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            return url
        }
        if let urlString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String {
            return URL(string: urlString)
        }
        return nil
    }

    private func log(_ message: String) {
        DohDebugLog.record(message, subsystem: "CF")
    }

    private func updateStatus(text: String, symbolName: String, color: UIColor) {
        statusLabel.text = text
        statusIconView.image = UIImage(systemName: symbolName)
        statusIconView.tintColor = color
    }
}

extension CloudflareVerificationViewController: WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            self?.scheduleVerificationChecks()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse,
              CloudflareVerificationPolicy.isVerifiedChallengeLanding(
                  response,
                  baseURL: baseURL
              )
        else {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
        Task { @MainActor [weak self] in
            await self?.completeFromVerifiedChallengeLanding()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinishVerifiedNavigation = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.scheduleVerificationChecks()
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        didFinishVerifiedNavigation = false
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if didDetectClearance { return }
        if let url = failingURL(from: error), isKnownVerifiedRedirectURL(url) {
            log("foreground didFail verified url=\(url.absoluteString) error=\(error.localizedDescription)")
            Task { @MainActor [weak self] in
                await self?.completeIfKnownVerifiedRedirect(url)
            }
            return
        }
        log("foreground didFail url=\(webView.url?.absoluteString ?? "none") error=\(error.localizedDescription)")
        updateStatus(
            text: String(localized: "cloudflare.verify.load_failed"),
            symbolName: "exclamationmark.triangle.fill",
            color: .systemRed
        )
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if didDetectClearance { return }
        if let url = failingURL(from: error), isKnownVerifiedRedirectURL(url) {
            log("foreground didFailProvisional verified url=\(url.absoluteString) error=\(error.localizedDescription)")
            Task { @MainActor [weak self] in
                await self?.completeIfKnownVerifiedRedirect(url)
            }
            return
        }
        log("foreground didFailProvisional url=\(webView.url?.absoluteString ?? "none") error=\(error.localizedDescription)")
        updateStatus(
            text: String(localized: "cloudflare.verify.load_failed"),
            symbolName: "exclamationmark.triangle.fill",
            color: .systemRed
        )
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

private extension UIViewController {
    func enableSettingsInteractiveBackSwipe() {
        guard let navigationController,
              navigationController.viewControllers.count > 1
        else { return }
        navigationController.interactivePopGestureRecognizer?.isEnabled = true
        navigationController.interactivePopGestureRecognizer?.delegate = nil
    }
}
