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
        #if DEBUG
        case debug
        #endif

        var title: String {
            switch self {
            case .appearance: return String(localized: "settings.appearance_design")
            case .reading: return String(localized: "settings.reading_design")
            case .network: return String(localized: "settings.network")
            case .bottomBar: return String(localized: "settings.bottom_bar")
            case .dataManagement: return String(localized: "settings.data_management")
            #if DEBUG
            case .debug: return "Debug"
            #endif
            }
        }

        var subtitle: String {
            switch self {
            case .appearance: return String(localized: "settings.appearance.subtitle")
            case .reading: return String(localized: "settings.reading.subtitle")
            case .network: return String(localized: "settings.network.subtitle")
            case .bottomBar: return String(localized: "settings.bottom_bar.subtitle")
            case .dataManagement: return String(localized: "settings.data_management.subtitle")
            #if DEBUG
            case .debug: return "Render preview"
            #endif
            }
        }

        var symbolName: String {
            switch self {
            case .appearance: return "paintpalette.fill"
            case .reading: return "book.closed.fill"
            case .network: return "network"
            case .bottomBar: return "rectangle.bottomthird.inset.filled"
            case .dataManagement: return "externaldrive.fill"
            #if DEBUG
            case .debug: return "hammer.fill"
            #endif
            }
        }

        var tintColor: UIColor {
            switch self {
            case .appearance: return .systemTeal
            case .reading: return .systemOrange
            case .network: return .systemBlue
            case .bottomBar: return .systemPurple
            case .dataManagement: return .systemBrown
            #if DEBUG
            case .debug: return .systemRed
            #endif
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
        if category == .bottomBar {
            navigationController?.pushViewController(BottomBarLayoutViewController(), animated: true)
            return
        }
        let vc = SettingsCategoryViewController(category: category)
        navigationController?.pushViewController(vc, animated: true)
    }
}

private final class AppearanceSettingsViewController: ObservableViewController {
    private let settings = AppSettings.shared
    private var modeCards: [AppSettings.AppearanceMode: AppearanceModeCardView] = [:]
    private var styleCards: [AppSettings.ThemeStyle: ThemeStyleCardView] = [:]
    private var iconCards: [AppSettings.AppIconStyle: AppIconCardView] = [:]
    private var fontRows: [AppSettings.ContentFontFamily: AppearanceFontOptionRow] = [:]
    private var sectionIconViews: [UIImageView] = []
    private var renderedLanguage: AppSettings.AppLanguage?
    private var pendingFontImportTarget: AppSettings.ContentFontFamily?

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
        if renderedLanguage != currentLanguage {
            rebuildContent()
            renderedLanguage = currentLanguage
        }
        title = String(localized: "settings.section.appearance")

        let themeStyle = settings.themeStyle
        let accentColor = themeStyle.accentColor
        let pageBackground = themeStyle == .systemDefault ? UIColor.systemGroupedBackground : themeStyle.mutedContentBackgroundColor
        let cardBackground = themeStyle.topicCardBackgroundColor

        view.backgroundColor = pageBackground
        scrollView.backgroundColor = pageBackground
        view.tintColor = accentColor
        sectionIconViews.forEach { $0.tintColor = accentColor }
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
        fontRows.forEach { family, row in
            row.configure(
                title: family.title,
                subtitle: settings.contentFontSubtitle(for: family),
                selected: family == settings.contentFontFamily,
                available: settings.isContentFontFamilyAvailable(family),
                accentColor: accentColor,
                backgroundColor: cardBackground
            )
        }
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
        rebuildContent()
        renderedLanguage = settings.appLanguage
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
        contentStack.addArrangedSubview(styleSection)

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
        fontSection.addArrangedSubview(makeFontOptionsCard())
        contentStack.addArrangedSubview(fontSection)
    }

    private func verticalSection(title: String, symbolName: String) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 10

        let icon = UIImageView(image: UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)))
        icon.tintColor = AppSettings.shared.themeStyle.accentColor
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        sectionIconViews.append(icon)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
        ])

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 20, weight: .semibold)
        label.textColor = .label

        header.addArrangedSubview(icon)
        header.addArrangedSubview(label)
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

        for family in AppSettings.ContentFontFamily.allCases {
            let row = AppearanceFontOptionRow(family: family)
            row.addTarget(self, action: #selector(fontFamilyTapped(_:)), for: .touchUpInside)
            card.addArrangedSubview(row)
            fontRows[family] = row
        }
        return card
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
        switch sender.family {
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
        case .custom:
            if settings.isContentFontFamilyAvailable(.custom), settings.contentFontFamily != .custom {
                settings.contentFontFamily = .custom
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                updateUI()
            } else {
                presentFontImporter(for: .custom)
            }
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

    private func presentFontImporter(for family: AppSettings.ContentFontFamily) {
        pendingFontImportTarget = family
        let fontTypes = [
            UTType(filenameExtension: "ttf"),
            UTType(filenameExtension: "otf"),
            UTType(filenameExtension: "ttc"),
        ].compactMap { $0 }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: fontTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
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
        guard let target = pendingFontImportTarget, let url = urls.first else { return }
        pendingFontImportTarget = nil
        do {
            try settings.importContentFont(from: url, targetFamily: target)
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
    let family: AppSettings.ContentFontFamily

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

    init(family: AppSettings.ContentFontFamily) {
        self.family = family
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
        accentColor: UIColor,
        backgroundColor: UIColor
    ) {
        self.backgroundColor = backgroundColor
        titleLabel.text = title
        subtitleLabel.text = subtitle
        radioView.layer.borderColor = (selected ? accentColor : UIColor.secondaryLabel).withAlphaComponent(selected ? 1 : 0.65).cgColor
        radioDotView.backgroundColor = selected ? accentColor : .clear
        titleLabel.textColor = available || family == .system ? .label : .secondaryLabel
        uploadIconView.tintColor = accentColor
        uploadIconView.isHidden = family == .system || (family == .miSans && available)
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
            var rows: [Row] = [.cloudflareVerify, .dohToggle, .dohDebugLog]
            if settings.dohEnabled {
                rows.append(.dohStatus)
                rows.append(.dohProvider)
                rows.append(.dohCustomURL)
            }
            return rows
        case .bottomBar:
            return [.bottomBarLayout, .bottomAutoHide]
        case .dataManagement:
            return [.clearImageCache, .autoOpen]
        #if DEBUG
        case .debug:
            return [.renderPreview]
        #endif
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
            return valueCell(title: String(localized: "settings.content_font_size"), detail: settings.contentFontSize.title)
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
            let vc = CloudflareVerificationViewController(baseURL: baseURL) { [weak self] in
                self?.tableView.reloadData()
            }
            navigationController?.pushViewController(vc, animated: true)
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
        for size in AppSettings.ContentFontSize.allCases {
            let action = UIAlertAction(title: size.title, style: .default) { [weak self] _ in
                guard let self else { return }
                settings.contentFontSize = size
                tableView.reloadData()
            }
            action.setValue(size == settings.contentFontSize, forKey: "checked")
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

private final class BottomBarLayoutViewController: ObservableViewController {
    private enum Section: Int, CaseIterable {
        case enabled
        case available
        case behavior

        var title: String {
            switch self {
            case .enabled: return "底栏布局"
            case .available: return "可添加"
            case .behavior: return "行为"
            }
        }
    }

    private let settings = AppSettings.shared

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .systemGroupedBackground
        table.dataSource = self
        table.delegate = self
        table.isEditing = true
        table.allowsSelectionDuringEditing = true
        return table
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "底栏"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "恢复默认",
            style: .plain,
            target: self,
            action: #selector(restoreDefaultTapped)
        )

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
        tableView.reloadData()
    }

    @objc private func restoreDefaultTapped() {
        settings.resetForumDynamicTabItems()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var configuredItems: [AppSettings.ForumDynamicTabItem] {
        settings.forumDynamicTabItems
    }

    private var availableItems: [AppSettings.ForumDynamicTabItem] {
        let configured = Set(configuredItems)
        return AppSettings.ForumDynamicTabItem.allCases.filter { !configured.contains($0) }
    }

    private func item(for indexPath: IndexPath) -> AppSettings.ForumDynamicTabItem? {
        guard let section = Section(rawValue: indexPath.section) else { return nil }
        switch section {
        case .enabled:
            guard indexPath.row > 0 else { return nil }
            let itemIndex = indexPath.row - 1
            guard itemIndex < configuredItems.count else { return nil }
            return configuredItems[itemIndex]
        case .available:
            guard indexPath.row < availableItems.count else { return nil }
            return availableItems[indexPath.row]
        case .behavior:
            return nil
        }
    }

    private func setConfiguredItems(_ items: [AppSettings.ForumDynamicTabItem]) {
        settings.forumDynamicTabItems = items
    }

    private func addAvailableItem(at indexPath: IndexPath) {
        guard Section(rawValue: indexPath.section) == .available,
              let item = item(for: indexPath)
        else { return }

        guard configuredItems.count < AppSettings.maximumConfiguredForumDynamicTabItems else {
            showLimitMessage("最多保留 \(AppSettings.maximumConfiguredForumDynamicTabItems) 个功能候选。")
            return
        }

        setConfiguredItems(configuredItems + [item])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func actualBottomBarSummary() -> String {
        let visibleTitles = settings.forumVisibleDynamicTabItems.map(\.title)
        if visibleTitles.isEmpty {
            return "当前实际底栏：首页 + 我的。"
        }
        return "当前实际底栏：首页 + \(visibleTitles.joined(separator: " / ")) + 我的。"
    }

    private func showLimitMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }
}

extension BottomBarLayoutViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }
        switch section {
        case .enabled:
            return configuredItems.count + 1
        case .available:
            return availableItems.count
        case .behavior:
            return 1
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch section {
        case .enabled where indexPath.row == 0:
            return fixedHomeCell()
        case .enabled:
            guard let item = item(for: indexPath) else { return UITableViewCell() }
            return configuredCell(for: item, itemIndex: indexPath.row - 1)
        case .available:
            guard let item = item(for: indexPath) else { return UITableViewCell() }
            return availableCell(for: item)
        case .behavior:
            return behaviorCell()
        }
    }

    private func fixedHomeCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: "house")
        content.imageProperties.tintColor = .systemBlue
        content.text = String(localized: "tab.home")
        content.secondaryText = "固定第一位"
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        let lockView = UIImageView(image: UIImage(systemName: "lock.fill"))
        lockView.tintColor = .tertiaryLabel
        cell.accessoryView = lockView
        cell.selectionStyle = .none
        return cell
    }

    private func configuredCell(for item: AppSettings.ForumDynamicTabItem, itemIndex: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: item.symbolName)
        content.imageProperties.tintColor = itemIndex < AppSettings.maximumVisibleForumDynamicTabItems ? .systemBlue : .secondaryLabel
        content.text = item.title
        content.secondaryText = itemIndex < AppSettings.maximumVisibleForumDynamicTabItems ? "显示在底栏" : "候选保留，暂不显示"
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.showsReorderControl = true
        return cell
    }

    private func availableCell(for item: AppSettings.ForumDynamicTabItem) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let canAdd = configuredItems.count < AppSettings.maximumConfiguredForumDynamicTabItems
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: item.symbolName)
        content.imageProperties.tintColor = canAdd ? .systemBlue : .tertiaryLabel
        content.text = item.title
        content.secondaryText = item.subtitle
        content.textProperties.font = .systemFont(ofSize: 16, weight: .semibold)
        content.textProperties.color = canAdd ? .label : .tertiaryLabel
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.selectionStyle = canAdd ? .default : .none
        return cell
    }

    private func behaviorCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = String(localized: "settings.bottom_bar.auto_hide")
        cell.selectionStyle = .none
        let toggle = UISwitch()
        toggle.isOn = settings.bottomBarAutoHideEnabled
        toggle.addTarget(self, action: #selector(bottomAutoHideChanged(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func bottomAutoHideChanged(_ sender: UISwitch) {
        settings.bottomBarAutoHideEnabled = sender.isOn
    }
}

extension BottomBarLayoutViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .enabled:
            return "\(actualBottomBarSummary())\n首页固定第一位，我的固定在底栏末尾但不显示在这个配置列表里。系统底栏最多 5 个入口，所以优先显示前 \(AppSettings.maximumVisibleForumDynamicTabItems) 个功能项。"
        case .available:
            if availableItems.isEmpty {
                return "没有更多可添加。"
            }
            return configuredItems.count >= AppSettings.maximumConfiguredForumDynamicTabItems
                ? "候选已满，先删除一个功能再添加。"
                : "最多保留 \(AppSettings.maximumConfiguredForumDynamicTabItems) 个功能候选；拖动已启用项目可调整显示优先级。"
        case .behavior:
            return "开启后，首页向上滑动会隐藏底栏，向下滑动或回到顶部会显示底栏。"
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        addAvailableItem(at: indexPath)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard let section = Section(rawValue: indexPath.section) else { return false }
        switch section {
        case .enabled:
            return indexPath.row > 0
        case .available:
            return true
        case .behavior:
            return false
        }
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        guard let section = Section(rawValue: indexPath.section) else { return .none }
        switch section {
        case .enabled:
            return indexPath.row == 0 ? .none : .delete
        case .available:
            return .insert
        case .behavior:
            return .none
        }
    }

    func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath
    ) {
        switch editingStyle {
        case .delete:
            guard Section(rawValue: indexPath.section) == .enabled, indexPath.row > 0 else { return }
            guard configuredItems.count > AppSettings.minimumConfiguredForumDynamicTabItems else {
                showLimitMessage("至少保留 \(AppSettings.minimumConfiguredForumDynamicTabItems) 个功能入口。")
                return
            }
            var items = configuredItems
            items.remove(at: indexPath.row - 1)
            setConfiguredItems(items)
        case .insert:
            addAvailableItem(at: indexPath)
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .enabled && indexPath.row > 0
    }

    func tableView(
        _ tableView: UITableView,
        moveRowAt sourceIndexPath: IndexPath,
        to destinationIndexPath: IndexPath
    ) {
        guard Section(rawValue: sourceIndexPath.section) == .enabled,
              Section(rawValue: destinationIndexPath.section) == .enabled,
              sourceIndexPath.row > 0
        else {
            tableView.reloadData()
            return
        }

        var items = configuredItems
        let sourceIndex = sourceIndexPath.row - 1
        let destinationIndex = max(destinationIndexPath.row - 1, 0)
        guard sourceIndex < items.count, destinationIndex <= items.count else {
            tableView.reloadData()
            return
        }

        let item = items.remove(at: sourceIndex)
        items.insert(item, at: min(destinationIndex, items.count))
        setConfiguredItems(items)
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        guard Section(rawValue: proposedDestinationIndexPath.section) == .enabled else {
            return sourceIndexPath
        }
        return IndexPath(row: max(proposedDestinationIndexPath.row, 1), section: proposedDestinationIndexPath.section)
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        Section(rawValue: indexPath.section) == .enabled && indexPath.row > 0
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
    private var verificationCheckTask: Task<Void, Never>?
    private var didCallOnFinish = false

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

    init(baseURL: URL, autoDismissOnSuccess: Bool = false, onFinish: @escaping () -> Void) {
        self.baseURL = baseURL
        self.challengeURL = URL(string: "/challenge", relativeTo: baseURL)?.absoluteURL ?? baseURL
        self.autoDismissOnSuccess = autoDismissOnSuccess
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor deinit {
        verificationCheckTask?.cancel()
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
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
            self?.progressView.progress = Float(webView.estimatedProgress)
            self?.progressView.isHidden = webView.estimatedProgress >= 1.0
            guard webView.estimatedProgress >= 1.0 else { return }
            Task { @MainActor [weak self] in
                self?.scheduleVerificationChecks()
            }
        }

        initialClearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL)
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
        Task { @MainActor [weak self] in
            await self?.prepareAndLoadChallenge()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
    }

    @objc private func doneTapped() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if !self.didDetectClearance {
                await self.syncCookiesAndDetectClearance()
            }
            self.finishAndClose()
        }
    }

    @objc private func reloadTapped() {
        log("foreground reload tapped base=\(baseURL.absoluteString)")
        didDetectClearance = false
        isCheckingClearance = false
        needsVerificationRecheck = false
        verificationCheckTask?.cancel()
        verificationCheckTask = nil
        updateStatus(
            text: String(localized: "cloudflare.verify.instructions"),
            symbolName: "shield.fill",
            color: .systemOrange
        )
        Task { @MainActor [weak self] in
            await self?.prepareAndLoadChallenge()
        }
    }

    @MainActor
    private func prepareAndLoadChallenge() async {
        log("foreground load challenge base=\(baseURL.absoluteString) autoDismiss=\(autoDismissOnSuccess)")
        if autoDismissOnSuccess {
            WebCookieStore.shared.deleteCookie(named: "cf_clearance", for: baseURL)
            await deleteWebViewCookie(named: "cf_clearance")
        }
        webView.load(URLRequest(url: challengeURL))
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
        guard !didDetectClearance else { return }
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
        await syncCloudflareCookieFromWebView()
        let clearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL)
        let hasNewClearance = clearanceValue?.isEmpty == false
            && (!autoDismissOnSuccess || clearanceValue != initialClearanceValue)
        let hasKnownVerifiedRedirect = isKnownVerifiedRedirectURL(webView.url)
        let hasLoadedVerifiedPage = hasKnownVerifiedRedirect ? true : await hasLoadedVerifiedBasePage()
        let hasVerifiedPage = hasKnownVerifiedRedirect || hasLoadedVerifiedPage
        log(
            "foreground check url=\(webView.url?.absoluteString ?? "none") cf=\(clearanceValue?.isEmpty == false) newCf=\(hasNewClearance) verifiedPage=\(hasVerifiedPage)"
        )
        guard hasNewClearance else {
            if hasVerifiedPage {
                log("foreground verified page loaded but cf_clearance is not available yet; waiting")
            }
            return
        }
        let hasActiveChallenge = hasKnownVerifiedRedirect ? false : await pageHasActiveCloudflareChallenge()
        if hasActiveChallenge {
            log("foreground check active challenge still present")
            return
        }
        await updateStoredUserAgentFromWebView()
        completeVerification()
    }

    @MainActor
    private func completeIfKnownVerifiedRedirect(_ url: URL?) async {
        guard isKnownVerifiedRedirectURL(url) else { return }
        log("foreground known verified redirect url=\(url?.absoluteString ?? "none")")
        let clearanceValue = await drainCloudflareCookieFromWebView(maxAttempts: 6)
        guard clearanceValue?.isEmpty == false else {
            log("foreground known verified redirect without cf_clearance; waiting")
            scheduleVerificationChecks()
            return
        }
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
    @discardableResult
    private func drainCloudflareCookieFromWebView(maxAttempts: Int) async -> String? {
        let attempts = max(maxAttempts, 1)
        for attempt in 0 ..< attempts {
            await syncCloudflareCookieFromWebView()
            if let clearanceValue = WebCookieStore.shared.cookieValue(named: "cf_clearance", for: baseURL),
               !clearanceValue.isEmpty {
                return clearanceValue
            }
            guard attempt < attempts - 1 else { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    @MainActor
    private func updateStoredUserAgentFromWebView() async {
        if let userAgent = try? await webView.evaluateJavaScript("navigator.userAgent") as? String {
            WebCookieStore.shared.userAgent = userAgent
        }
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
        notifyFinishIfNeeded()
        guard autoDismissOnSuccess else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @MainActor
    private func notifyFinishIfNeeded() {
        guard !didCallOnFinish else { return }
        didCallOnFinish = true
        onFinish()
    }

    @MainActor
    private func finishAndClose() {
        notifyFinishIfNeeded()
        if navigationController?.viewControllers.first === self,
           navigationController?.presentingViewController != nil {
            navigationController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    @MainActor
    private func hasLoadedVerifiedBasePage() async -> Bool {
        guard let currentURL = webView.url,
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
    private func pageHasActiveCloudflareChallenge() async -> Bool {
        guard let pageText = try? await webView.evaluateJavaScript("""
            [
              document.title || '',
              document.body ? document.body.innerText : '',
              document.body ? document.body.innerHTML : ''
            ].join('\\n')
            """) as? String else {
            return false
        }
        return Self.hasActiveCloudflareChallenge(in: pageText)
    }

    @MainActor
    private func scheduleVerificationChecks() {
        guard !didDetectClearance else { return }
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
            await self?.syncCookiesAndDetectClearance()
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let url = navigationAction.request.url
        Task { @MainActor [weak self] in
            await self?.completeIfKnownVerifiedRedirect(url)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.completeIfKnownVerifiedRedirect(url)
            self.scheduleVerificationChecks()
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let url = webView.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.completeIfKnownVerifiedRedirect(url)
            self.scheduleVerificationChecks()
        }
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
