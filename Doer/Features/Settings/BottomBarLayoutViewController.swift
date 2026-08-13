import UIKit

final class BottomBarLayoutViewController: ObservableViewController {
    private struct TabItemDescriptor: Hashable {
        let id: String
        let title: String
        let subtitle: String
        let symbolName: String
    }

    private let settings = AppSettings.shared
    private let autoHideRow = ReadingToggleRowView()
    private let profileTabsRow = DataManagementActionRowView()

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
        observe(settings)
        title = String(localized: "settings.bottom_bar")
        configureRootView()
        rebuildContent()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "settings.bottom_bar.restore_default", defaultValue: "恢复默认"),
            style: .plain,
            target: self,
            action: #selector(restoreDefaultTapped)
        )
        autoHideRow.onValueChanged = { [weak self] isOn in
            guard let self else { return }
            settings.bottomBarAutoHideEnabled = isOn
            refreshDataViews()
        }
        profileTabsRow.addTarget(self, action: #selector(profileTabsTapped), for: .touchUpInside)
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

    private var allItems: [TabItemDescriptor] {
        AppSettings.ForumDynamicTabItem.allCases.map {
            TabItemDescriptor(id: $0.rawValue, title: $0.title, subtitle: $0.subtitle, symbolName: $0.symbolName)
        }
    }

    private var configuredItems: [TabItemDescriptor] {
        let itemsByID = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return settings.forumConfiguredTabItemIDs.compactMap { itemsByID[$0] }
    }

    private var availableItems: [TabItemDescriptor] {
        let configured = Set(settings.forumConfiguredTabItemIDs)
        return allItems.filter { !configured.contains($0.id) }
    }

    private func setConfiguredItems(_ items: [TabItemDescriptor]) {
        settings.forumConfiguredTabItemIDs = items.map(\.id)
        rebuildContent()
    }

    private func addAvailableItem(_ item: TabItemDescriptor) {
        guard configuredItems.count < AppSettings.maximumConfiguredForumDynamicTabItems else {
            showLimitMessage(String(
                format: String(localized: "settings.bottom_bar.candidate_limit_format", defaultValue: "最多保留 %lld 个功能候选。"),
                AppSettings.maximumConfiguredForumDynamicTabItems
            ))
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
        let visibleTitles = Array(configuredItems.prefix(AppSettings.maximumVisibleForumDynamicTabItems)).map(\.title)
        if visibleTitles.isEmpty {
            return String(localized: "settings.bottom_bar.summary_empty", defaultValue: "当前实际底栏：首页 + 我的。")
        }
        return String(
            format: String(localized: "settings.bottom_bar.summary_format", defaultValue: "当前实际底栏：首页 + %@ + 我的。"),
            visibleTitles.joined(separator: " / ")
        )
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
            subtitle: String(localized: "settings.bottom_bar.auto_hide.subtitle", defaultValue: "首页向上滑动隐藏底栏，向下滑动或回到顶部显示。"),
            symbolName: "arrow.up.and.down",
            isOn: settings.bottomBarAutoHideEnabled,
            accentColor: settings.themeStyle.accentColor,
            backgroundColor: settings.themeStyle.topicCardBackgroundColor
        )
        profileTabsRow.configure(
            title: String(localized: "settings.profile_tabs"),
            subtitle: String(localized: "settings.profile_tabs.subtitle"),
            symbolName: "rectangle.3.group.fill",
            tintColor: settings.themeStyle.accentColor,
            backgroundColor: settings.themeStyle.topicCardBackgroundColor
        )
    }

    private func makePreviewCard() -> UIView {
        let card = makeCard()
        card.layer.shadowOpacity = 0.08
        card.layer.shadowRadius = 18
        card.layer.shadowOffset = CGSize(width: 0, height: 10)
        card.layer.shadowColor = settings.themeStyle.accentColor.cgColor

        let eyebrow = makePillLabel(text: String(localized: "settings.bottom_bar.current_configuration", defaultValue: "当前配置"), color: settings.themeStyle.accentColor)
        let title = UILabel()
        title.text = actualBottomBarSummary()
        title.font = .systemFont(ofSize: 20, weight: .heavy)
        title.textColor = .label
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = String(
            format: String(localized: "settings.bottom_bar.preview_help_format", defaultValue: "首页固定第一位，我的固定末尾；系统底栏最多 5 个入口，前 %lld 个功能项会优先显示。"),
            AppSettings.maximumVisibleForumDynamicTabItems
        )
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0

        let previewRow = UIStackView()
        previewRow.axis = .horizontal
        previewRow.alignment = .center
        previewRow.spacing = 8
        previewRow.addArrangedSubview(makeMiniTab(title: String(localized: "tab.home"), symbolName: "house.fill", active: true))
        for (index, item) in configuredItems.prefix(AppSettings.maximumVisibleForumDynamicTabItems).enumerated() {
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
        let stack = makeSectionStack(title: String(localized: "settings.bottom_bar.entries", defaultValue: "底栏入口"), symbolName: "rectangle.bottomthird.inset.filled")
        stack.addArrangedSubview(makeFixedItemRow(
            title: String(localized: "tab.home"),
            subtitle: String(localized: "settings.bottom_bar.fixed_first", defaultValue: "固定第一位"),
            symbolName: "house.fill"
        ))
        for (index, item) in configuredItems.enumerated() {
            stack.addArrangedSubview(makeConfiguredItemRow(item: item, index: index))
        }
        return stack
    }

    private func makeAvailableSection() -> UIView {
        let stack = makeSectionStack(title: String(localized: "settings.bottom_bar.available", defaultValue: "可添加"), symbolName: "plus.circle")
        if availableItems.isEmpty {
            stack.addArrangedSubview(makeInfoCard(text: String(localized: "settings.bottom_bar.available_empty", defaultValue: "没有更多可添加。")))
            return stack
        }
        if configuredItems.count >= AppSettings.maximumConfiguredForumDynamicTabItems {
            stack.addArrangedSubview(makeInfoCard(text: String(localized: "settings.bottom_bar.available_full", defaultValue: "候选已满，先删除一个功能再添加。")))
        }
        for item in availableItems {
            stack.addArrangedSubview(makeAvailableItemRow(item: item))
        }
        return stack
    }

    private func makeBehaviorSection() -> UIView {
        let stack = makeSectionStack(title: String(localized: "settings.bottom_bar.behavior", defaultValue: "行为"), symbolName: "hand.tap")
        stack.addArrangedSubview(autoHideRow)
        stack.addArrangedSubview(profileTabsRow)
        return stack
    }

    @objc private func profileTabsTapped() {
        navigationController?.pushViewController(UserProfileTabsSettingsViewController(), animated: true)
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

    private func makeConfiguredItemRow(item: TabItemDescriptor, index: Int) -> UIView {
        let accessory = UIStackView()
        accessory.axis = .horizontal
        accessory.alignment = .center
        accessory.spacing = 6

        let isVisible = index < AppSettings.maximumVisibleForumDynamicTabItems
        accessory.addArrangedSubview(makePillLabel(
            text: isVisible
                ? String(localized: "settings.bottom_bar.visible", defaultValue: "显示")
                : String(localized: "settings.bottom_bar.candidate", defaultValue: "候选"),
            color: isVisible ? settings.themeStyle.accentColor : .secondaryLabel
        ))
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
            subtitle: isVisible
                ? String(localized: "settings.bottom_bar.visible.subtitle", defaultValue: "显示在底栏")
                : String(localized: "settings.bottom_bar.candidate.subtitle", defaultValue: "候选保留，暂不显示"),
            symbolName: item.symbolName,
            tintColor: isVisible ? settings.themeStyle.accentColor : .secondaryLabel,
            accessory: accessory
        )
    }

    private func makeAvailableItemRow(item: TabItemDescriptor) -> UIView {
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

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let iconImage = UIImage(systemName: symbolName, withConfiguration: symbolConfiguration)
            ?? UIImage(named: symbolName)?.withRenderingMode(.alwaysOriginal)
        let icon = UIImageView(image: iconImage)
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

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        let iconImage = UIImage(systemName: symbolName, withConfiguration: symbolConfiguration)
            ?? UIImage(named: symbolName)?.withRenderingMode(.alwaysOriginal)
        let icon = UIImageView(image: iconImage)
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
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
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
