import PhotosUI
import UIKit

/// Mini-program management — redesigned for clarity and touch-first mobile UX
/// (ui-ux-pro-max: large targets, low density, clear hierarchy, no emoji icons).
final class PluginCenterViewController: UIViewController {
    private enum Tab: Int {
        case programs = 0
        case categories = 1
    }

    private let apiBaseURL: String
    private let username: String?
    private let store: MiniProgramStore
    private let settings = AppSettings.shared
    private var pendingLogoProgramID: String?
    private var catalogObserver: NSObjectProtocol?
    private var activeTab: Tab = .programs
    private var isReorderMode = false

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.showsVerticalScrollIndicator = false
        scroll.keyboardDismissMode = .onDrag
        return scroll
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 40, trailing: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var segmentControl: UISegmentedControl = {
        let control = UISegmentedControl(items: [
            String(localized: "mini_program.management.tab.programs", defaultValue: "小程序"),
            String(localized: "mini_program.management.tab.categories", defaultValue: "分类"),
        ])
        control.selectedSegmentIndex = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()

    private lazy var addBarButton = UIBarButtonItem(
        image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)),
        style: .plain,
        target: self,
        action: #selector(addTapped)
    )

    private lazy var reorderBarButton = UIBarButtonItem(
        title: String(localized: "mini_program.management.reorder", defaultValue: "排序"),
        style: .plain,
        target: self,
        action: #selector(reorderTapped)
    )

    init(
        baseURL: String,
        username: String?,
        store: MiniProgramStore = .shared
    ) {
        apiBaseURL = baseURL
        self.username = username
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let catalogObserver {
            NotificationCenter.default.removeObserver(catalogObserver)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "mini_program.management.title", defaultValue: "小程序管理")
        navigationItem.rightBarButtonItems = [addBarButton, reorderBarButton]
        configureBackNavigationItem()
        configureRootView()
        rebuildContent()

        catalogObserver = NotificationCenter.default.addObserver(
            forName: MiniProgramStore.catalogDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildContent()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        configureBackNavigationItem()
        rebuildContent()
    }

    // MARK: - Navigation

    private func configureBackNavigationItem() {
        navigationItem.hidesBackButton = false
        let isNavRoot = navigationController?.viewControllers.first === self
        let canPop = (navigationController?.viewControllers.count ?? 0) > 1

        if canPop && !isNavRoot {
            navigationItem.leftBarButtonItem = nil
            return
        }

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "common.back", defaultValue: "返回"),
            style: .plain,
            target: self,
            action: #selector(backTapped)
        )
    }

    @objc private func backTapped() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
            return
        }
        if presentingViewController != nil {
            dismiss(animated: true)
            return
        }
        navigationController?.popViewController(animated: true)
    }

    @objc private func segmentChanged() {
        activeTab = Tab(rawValue: segmentControl.selectedSegmentIndex) ?? .programs
        isReorderMode = false
        updateReorderButtonTitle()
        UISelectionFeedbackGenerator().selectionChanged()
        rebuildContent()
    }

    @objc private func reorderTapped() {
        isReorderMode.toggle()
        updateReorderButtonTitle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        rebuildContent()
    }

    private func updateReorderButtonTitle() {
        reorderBarButton.title = isReorderMode
            ? String(localized: "common.done", defaultValue: "完成")
            : String(localized: "mini_program.management.reorder", defaultValue: "排序")
        reorderBarButton.style = isReorderMode ? .done : .plain
    }

    // MARK: - Layout

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
        segmentControl.selectedSegmentIndex = activeTab.rawValue

        contentStack.addArrangedSubview(makeSegmentHost())
        contentStack.addArrangedSubview(makeStatsBar())

        switch activeTab {
        case .programs:
            contentStack.addArrangedSubview(makeProgramsList())
        case .categories:
            contentStack.addArrangedSubview(makeCategoriesList())
        }

        if !isReorderMode {
            contentStack.addArrangedSubview(makeHintCard())
        }
    }

    // MARK: - Header

    private func makeSegmentHost() -> UIView {
        let host = UIView()
        host.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(segmentControl)
        NSLayoutConstraint.activate([
            segmentControl.topAnchor.constraint(equalTo: host.topAnchor, constant: 4),
            segmentControl.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            segmentControl.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            segmentControl.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -4),
            segmentControl.heightAnchor.constraint(equalToConstant: 34),
        ])
        return host
    }

    /// Compact metric chips — scannable, no wall of text (ux: density + hierarchy).
    private func makeStatsBar() -> UIView {
        let programs = store.allPrograms()
        let visibleCount = programs.filter(\.isVisible).count
        let customCount = programs.filter { !$0.isBuiltIn }.count
        let accent = settings.themeStyle.accentColor

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(makeStatCard(
            value: "\(visibleCount)",
            title: String(localized: "mini_program.management.stat.visible", defaultValue: "显示中"),
            color: accent
        ))
        row.addArrangedSubview(makeStatCard(
            value: "\(customCount)",
            title: String(localized: "mini_program.management.stat.custom", defaultValue: "自定义"),
            color: .systemOrange
        ))
        row.addArrangedSubview(makeStatCard(
            value: "\(store.allCategories().count)",
            title: String(localized: "mini_program.management.stat.categories", defaultValue: "分类"),
            color: .systemTeal
        ))
        return row
    }

    private func makeStatCard(value: String, title: String, color: UIColor) -> UIView {
        let card = makeSurfaceCard()
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = color
        valueLabel.textAlignment = .center

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [valueLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(equalToConstant: 72),
            stack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -8),
        ])
        return card
    }

    // MARK: - Programs list

    private func makeProgramsList() -> UIView {
        let programs = store.allPrograms()
        let card = makeSurfaceCard()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        pin(stack, to: card)

        if programs.isEmpty {
            stack.addArrangedSubview(makeEmptyRow(
                symbol: "square.grid.2x2",
                title: String(localized: "mini_program.management.programs.empty", defaultValue: "还没有小程序"),
                subtitle: String(
                    localized: "mini_program.management.programs.empty_hint",
                    defaultValue: "点右上角 + 添加网址小程序"
                )
            ))
            return card
        }

        for (index, program) in programs.enumerated() {
            stack.addArrangedSubview(makeProgramRow(program: program, index: index, total: programs.count))
            if index < programs.count - 1 {
                stack.addArrangedSubview(makeHairline())
            }
        }
        return card
    }

    private func makeProgramRow(program: MiniProgramRecord, index: Int, total: Int) -> UIView {
        let accent = settings.themeStyle.accentColor
        let row = UIControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.backgroundColor = .clear
        // 44pt+ touch target (ux-pro-max touch guideline).
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true

        let iconBadge = MiniProgramIconBadge.view(for: program.id, size: 44)
        iconBadge.isUserInteractionEnabled = false

        let titleLabel = UILabel()
        titleLabel.text = program.displayName
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = program.isVisible ? .label : .secondaryLabel
        titleLabel.lineBreakMode = .byTruncatingTail

        let subtitleLabel = UILabel()
        subtitleLabel.text = programSubtitle(program)
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.isUserInteractionEnabled = false

        let trailing = UIStackView()
        trailing.axis = .horizontal
        trailing.alignment = .center
        trailing.spacing = 10

        if isReorderMode {
            trailing.addArrangedSubview(makeIconButton(
                symbol: "chevron.up",
                enabled: index > 0,
                color: .secondaryLabel
            ) { [weak self] in
                self?.moveProgram(id: program.id, from: index, by: -1)
            })
            trailing.addArrangedSubview(makeIconButton(
                symbol: "chevron.down",
                enabled: index < total - 1,
                color: .secondaryLabel
            ) { [weak self] in
                self?.moveProgram(id: program.id, from: index, by: 1)
            })
        } else {
            let visibilitySwitch = UISwitch()
            visibilitySwitch.isOn = program.isVisible
            visibilitySwitch.onTintColor = accent
            // Keep switch tappable without opening the row menu.
            visibilitySwitch.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.store.setProgram(program.id, isVisible: visibilitySwitch.isOn)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self.rebuildContent()
            }, for: .valueChanged)
            trailing.addArrangedSubview(visibilitySwitch)

            let chevron = UIImageView(
                image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
            )
            chevron.tintColor = .tertiaryLabel
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            trailing.addArrangedSubview(chevron)
        }

        let stack = UIStackView(arrangedSubviews: [iconBadge, textStack, trailing])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        // Trailing controls keep their size; text compresses.
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addSubview(stack)
        pin(stack, to: row)

        if !isReorderMode {
            row.addAction(UIAction { [weak self] _ in
                self?.presentProgramActions(program)
            }, for: .touchUpInside)
            row.addAction(UIAction { _ in
                UIView.animate(withDuration: 0.12) { row.alpha = 0.72 }
            }, for: .touchDown)
            let reset = UIAction { _ in
                UIView.animate(withDuration: 0.15) { row.alpha = 1 }
            }
            row.addAction(reset, for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }

        return row
    }

    // MARK: - Categories list

    private func makeCategoriesList() -> UIView {
        let categories = store.allCategories()
        let card = makeSurfaceCard()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        pin(stack, to: card)

        for (index, category) in categories.enumerated() {
            stack.addArrangedSubview(makeCategoryRow(category: category, index: index, total: categories.count))
            if index < categories.count - 1 {
                stack.addArrangedSubview(makeHairline())
            }
        }
        return card
    }

    private func makeCategoryRow(category: MiniProgramCategory, index: Int, total: Int) -> UIView {
        let accent = settings.themeStyle.accentColor
        let count = store.allPrograms().filter { $0.categoryID == category.id }.count

        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        let iconWrap = UIView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.backgroundColor = accent.withAlphaComponent(0.12)
        iconWrap.layer.cornerRadius = 22
        iconWrap.layer.cornerCurve = .continuous
        let folder = UIImageView(
            image: UIImage(systemName: "folder.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        )
        folder.tintColor = accent
        folder.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(folder)
        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 44),
            iconWrap.heightAnchor.constraint(equalToConstant: 44),
            folder.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            folder.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
        ])

        let titleLabel = UILabel()
        titleLabel.text = category.name
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label

        let subtitleLabel = UILabel()
        subtitleLabel.text = String(
            format: String(localized: "mini_program.management.category_count", defaultValue: "%d 个小程序"),
            count
        )
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .tertiaryLabel

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        let trailing = UIStackView()
        trailing.axis = .horizontal
        trailing.alignment = .center
        trailing.spacing = 8

        if isReorderMode {
            trailing.addArrangedSubview(makeIconButton(symbol: "chevron.up", enabled: index > 0, color: .secondaryLabel) { [weak self] in
                self?.moveCategory(id: category.id, from: index, by: -1)
            })
            trailing.addArrangedSubview(makeIconButton(symbol: "chevron.down", enabled: index < total - 1, color: .secondaryLabel) { [weak self] in
                self?.moveCategory(id: category.id, from: index, by: 1)
            })
        } else if category.isBuiltIn {
            trailing.addArrangedSubview(makeTag(
                text: String(localized: "mini_program.management.builtin", defaultValue: "内置"),
                color: accent
            ))
            let lock = UIImageView(
                image: UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
            )
            lock.tintColor = .tertiaryLabel
            trailing.addArrangedSubview(lock)
        } else {
            trailing.addArrangedSubview(makeIconButton(symbol: "pencil", enabled: true, color: accent) { [weak self] in
                self?.presentRenameCategory(category)
            })
            trailing.addArrangedSubview(makeIconButton(symbol: "trash", enabled: true, color: .systemRed) { [weak self] in
                guard let self else { return }
                _ = self.store.deleteCategory(id: category.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self.rebuildContent()
            })
        }

        let stack = UIStackView(arrangedSubviews: [iconWrap, textStack, trailing])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addSubview(stack)
        pin(stack, to: row)
        return row
    }

    private func makeHintCard() -> UIView {
        let card = makeSurfaceCard()
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        switch activeTab {
        case .programs:
            label.text = isReorderMode
                ? String(localized: "mini_program.management.reorder_hint", defaultValue: "使用上下箭头调整顺序，完成后点「完成」。")
                : String(
                    localized: "mini_program.management.programs.footer",
                    defaultValue: "点按条目管理；开关控制是否在首页显示。需要排序时点右上角「排序」。"
                )
        case .categories:
            label.text = String(
                localized: "mini_program.management.categories.footer",
                defaultValue: "删除分类不会删除小程序，分类下内容会移动到「其他」。"
            )
        }
        card.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    private func makeEmptyRow(symbol: String, title: String, subtitle: String) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(
            image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium))
        )
        icon.tintColor = .tertiaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center

        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(stack)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(greaterThanOrEqualToConstant: 140),
            stack.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: wrap.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor, constant: -24),
        ])
        return wrap
    }

    // MARK: - Shared UI atoms

    private func makeSurfaceCard() -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = settings.themeStyle.topicCardBackgroundColor
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        return view
    }

    private func makeHairline() -> UIView {
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
        line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true

        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 70),
            line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            line.topAnchor.constraint(equalTo: wrap.topAnchor),
            line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }

    private func makeTag(text: String, color: UIColor) -> UILabel {
        let label = PaddingLabel()
        label.text = text
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = color
        label.backgroundColor = color.withAlphaComponent(0.12)
        label.layer.cornerRadius = 10
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.contentInsets = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        return label
    }

    /// 44×44 minimum hit area (ux-pro-max touch target).
    private func makeIconButton(
        symbol: String,
        enabled: Bool,
        color: UIColor,
        action: @escaping () -> Void
    ) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        )
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = enabled ? color : .tertiaryLabel
        button.backgroundColor = (enabled ? color : UIColor.tertiaryLabel).withAlphaComponent(enabled ? 0.10 : 0.05)
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous
        button.isEnabled = enabled
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
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

    private func programSubtitle(_ program: MiniProgramRecord) -> String {
        let categoryName = store.category(id: program.categoryID)?.name ?? "其他"
        if program.isBuiltIn {
            return String(
                format: String(localized: "mini_program.management.builtin_subtitle", defaultValue: "内置 · %@"),
                categoryName
            )
        }
        let host = program.urlString.flatMap(URL.init(string:))?.host
        return [host, categoryName].compactMap { $0 }.joined(separator: " · ")
    }

    private func moveProgram(id: String, from index: Int, by delta: Int) {
        let target = index + delta
        let programs = store.allPrograms()
        guard programs.indices.contains(index), programs.indices.contains(target) else { return }
        store.moveProgram(id: id, to: target)
        UISelectionFeedbackGenerator().selectionChanged()
        rebuildContent()
    }

    private func moveCategory(id: String, from index: Int, by delta: Int) {
        let target = index + delta
        let categories = store.allCategories()
        guard categories.indices.contains(index), categories.indices.contains(target) else { return }
        store.moveCategory(id: id, to: target)
        UISelectionFeedbackGenerator().selectionChanged()
        rebuildContent()
    }

    // MARK: - Actions (behavior preserved)

    @objc private func addTapped() {
        let sheet = UIAlertController(
            title: String(localized: "mini_program.management.add", defaultValue: "添加"),
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: String(localized: "mini_program.management.add_url", defaultValue: "添加网址小程序"),
            style: .default
        ) { [weak self] _ in self?.presentAddURLProgram() })
        sheet.addAction(UIAlertAction(
            title: String(localized: "mini_program.management.add_category", defaultValue: "新建分类"),
            style: .default
        ) { [weak self] _ in self?.presentAddCategory() })
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = addBarButton
        present(sheet, animated: true)
    }

    private func presentAddURLProgram() {
        let alert = UIAlertController(
            title: String(localized: "mini_program.add_url.title", defaultValue: "添加网址小程序"),
            message: String(localized: "mini_program.add_url.message", defaultValue: "输入网址后会自动尝试获取名称和 Logo。"),
            preferredStyle: .alert
        )
        alert.addTextField {
            $0.placeholder = "https://example.com"
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.next", defaultValue: "下一步"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let raw = alert?.textFields?.first?.text,
                  let url = self.normalizedInputURL(raw)
            else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                self.presentFetchingLogoHUD()
                let service = MiniProgramMetadataService()
                let metadata = await service.fetch(url: url)
                let logoData = try? await service.fetchLogoImageData(for: metadata.sourceURL)
                await self.dismissFetchingLogoHUD()
                self.presentProgramPreview(metadata: metadata, logoData: logoData)
            }
        })
        present(alert, animated: true)
    }

    private func presentProgramPreview(metadata: MiniProgramMetadata, logoData: Data?) {
        let alert = UIAlertController(
            title: String(localized: "mini_program.install_preview.title", defaultValue: "添加到小程序"),
            message: metadata.sourceURL.host,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(localized: "mini_program.name", defaultValue: "名称")
            field.text = metadata.name
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let name = alert?.textFields?.first?.text ?? metadata.name
            do {
                let programID = try self.store.addCustomProgram(
                    name: name,
                    url: metadata.sourceURL,
                    categoryID: MiniProgramCategoryID.other,
                    icon: .system(symbolName: "globe")
                )
                if let logoData,
                   let path = try? MiniProgramIconStore.shared.saveIconData(logoData, programID: programID) {
                    try? self.store.updateCustomProgram(
                        id: programID,
                        name: name,
                        url: metadata.sourceURL,
                        categoryID: MiniProgramCategoryID.other,
                        icon: .local(relativePath: path),
                        isVisible: true
                    )
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self.rebuildContent()
            } catch {
                self.presentError(error)
            }
        })
        present(alert, animated: true)
    }

    private func presentAddCategory() {
        let alert = UIAlertController(
            title: String(localized: "mini_program.category.add", defaultValue: "新建分类"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = String(localized: "mini_program.category.name", defaultValue: "分类名称") }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            _ = self.store.addCategory(name: alert?.textFields?.first?.text ?? "")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.activeTab = .categories
            self.rebuildContent()
        })
        present(alert, animated: true)
    }

    private func presentProgramActions(_ program: MiniProgramRecord) {
        let sheet = UIAlertController(title: program.displayName, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(
            title: String(localized: "mini_program.management.change_category", defaultValue: "修改分类"),
            style: .default
        ) { [weak self] _ in self?.presentCategoryPicker(for: program) })
        if !program.isBuiltIn {
            sheet.addAction(UIAlertAction(
                title: String(localized: "mini_program.management.edit", defaultValue: "编辑名称和网址"),
                style: .default
            ) { [weak self] _ in self?.presentEditCustomProgram(program) })
            sheet.addAction(UIAlertAction(
                title: String(localized: "mini_program.management.fetch_logo", defaultValue: "获取网站 Logo"),
                style: .default
            ) { [weak self] _ in self?.fetchWebsiteLogo(for: program) })
            sheet.addAction(UIAlertAction(
                title: String(localized: "mini_program.management.choose_logo", defaultValue: "从相册选择 Logo"),
                style: .default
            ) { [weak self] _ in self?.presentLogoPicker(for: program.id) })
            sheet.addAction(UIAlertAction(
                title: String(localized: "common.delete", defaultValue: "删除"),
                style: .destructive
            ) { [weak self] _ in
                guard let self else { return }
                _ = self.store.deleteProgram(id: program.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self.rebuildContent()
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX,
            y: view.bounds.midY,
            width: 1,
            height: 1
        )
        present(sheet, animated: true)
    }

    private func presentEditCustomProgram(_ program: MiniProgramRecord) {
        let alert = UIAlertController(
            title: String(localized: "mini_program.management.edit", defaultValue: "编辑名称和网址"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { $0.text = program.displayName }
        alert.addTextField {
            $0.text = program.urlString
            $0.keyboardType = .URL
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let rawURL = alert?.textFields?.dropFirst().first?.text,
                  let url = self.normalizedInputURL(rawURL)
            else { return }
            do {
                try self.store.updateCustomProgram(
                    id: program.id,
                    name: alert?.textFields?.first?.text ?? program.displayName,
                    url: url,
                    categoryID: program.categoryID,
                    icon: program.icon,
                    isVisible: program.isVisible
                )
                self.rebuildContent()
            } catch {
                self.presentError(error)
            }
        })
        present(alert, animated: true)
    }

    private func presentCategoryPicker(for program: MiniProgramRecord) {
        let sheet = UIAlertController(
            title: String(localized: "mini_program.management.change_category", defaultValue: "修改分类"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for category in store.allCategories() {
            let title = category.id == program.categoryID ? "✓ \(category.name)" : category.name
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.store.setProgram(program.id, categoryID: category.id)
                self?.rebuildContent()
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        present(sheet, animated: true)
    }

    private func presentRenameCategory(_ category: MiniProgramCategory) {
        let alert = UIAlertController(
            title: String(localized: "common.rename", defaultValue: "重命名"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { $0.text = category.name }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default) { [weak self, weak alert] _ in
            self?.store.renameCategory(id: category.id, name: alert?.textFields?.first?.text ?? category.name)
            self?.rebuildContent()
        })
        present(alert, animated: true)
    }

    private func presentLogoPicker(for programID: String) {
        pendingLogoProgramID = programID
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func fetchWebsiteLogo(for program: MiniProgramRecord) {
        guard let urlString = program.urlString,
              let url = URL(string: urlString)
        else {
            presentError(MiniProgramLogoFetchError.invalidURL)
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            presentFetchingLogoHUD()
            do {
                let path = try await MiniProgramMetadataService().downloadAndSaveLogo(
                    for: url,
                    programID: program.id
                )
                try store.updateCustomProgram(
                    id: program.id,
                    name: program.displayName,
                    url: url,
                    categoryID: program.categoryID,
                    icon: .local(relativePath: path),
                    isVisible: program.isVisible
                )
                await dismissFetchingLogoHUD()
                rebuildContent()
            } catch {
                await dismissFetchingLogoHUD()
                presentError(error)
            }
        }
    }

    private func presentFetchingLogoHUD() {
        guard presentedViewController == nil else { return }
        let hud = UIAlertController(
            title: nil,
            message: String(localized: "mini_program.logo.fetching", defaultValue: "正在获取 Logo…"),
            preferredStyle: .alert
        )
        present(hud, animated: true)
    }

    @MainActor
    private func dismissFetchingLogoHUD() async {
        guard let presented = presentedViewController as? UIAlertController,
              presented.actions.isEmpty
        else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presented.dismiss(animated: true) {
                continuation.resume()
            }
        }
    }

    private func normalizedInputURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private func presentError(_ error: Error) {
        let alert = UIAlertController(
            title: String(localized: "extensions.error.title", defaultValue: "操作失败"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default))
        present(alert, animated: true)
    }
}

extension PluginCenterViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let programID = pendingLogoProgramID,
              let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self)
        else {
            pendingLogoProgramID = nil
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage,
                  let data = image.pngData()
            else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      let program = self.store.program(id: programID),
                      let urlString = program.urlString,
                      let url = URL(string: urlString)
                else { return }
                do {
                    let path = try MiniProgramIconStore.shared.saveIconData(data, programID: programID)
                    try self.store.updateCustomProgram(
                        id: programID,
                        name: program.displayName,
                        url: url,
                        categoryID: program.categoryID,
                        icon: .local(relativePath: path),
                        isVisible: program.isVisible
                    )
                    self.pendingLogoProgramID = nil
                    self.rebuildContent()
                } catch {
                    self.presentError(error)
                }
            }
        }
    }
}
