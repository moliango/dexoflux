import Combine
import UIKit

/// FluxDo `MyBadgesPage` — large header + gold/silver/bronze grid cards.
final class UserBadgesViewController: UIViewController {
    /// Section indices: 0 = summary, then gold/silver/bronze in order present.
    private var sectionTypes: [DiscourseBadge.BadgeType?] = [.none]
    private let api: DiscourseAPI
    private let username: String
    private var sections: [(DiscourseBadge.BadgeType, [DiscourseUserBadge])] = []
    private var badgesById: [Int: DiscourseUserBadge] = [:]
    private var isLoading = false
    private var errorMessage: String?
    private var settingsObservation: AnyCancellable?

    /// Diffable ids: `0` = summary header; positive = user-badge id.
    private static let summaryItemId = 0

    private lazy var collectionView: UICollectionView = {
        let view = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.register(BadgeGridCell.self, forCellWithReuseIdentifier: BadgeGridCell.reuseIdentifier)
        view.register(
            BadgeSummaryHeaderCell.self,
            forCellWithReuseIdentifier: BadgeSummaryHeaderCell.reuseIdentifier
        )
        view.register(
            BadgeSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: BadgeSectionHeaderView.reuseIdentifier
        )
        view.delegate = self
        return view
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<Int, Int> = {
        let source = UICollectionViewDiffableDataSource<Int, Int>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, itemId in
            guard let self else { return UICollectionViewCell() }
            if itemId == Self.summaryItemId {
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: BadgeSummaryHeaderCell.reuseIdentifier,
                    for: indexPath
                ) as! BadgeSummaryHeaderCell
                let total = self.sections.reduce(0) { $0 + $1.1.count }
                cell.configure(total: total)
                return cell
            }
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: BadgeGridCell.reuseIdentifier,
                for: indexPath
            ) as! BadgeGridCell
            if let userBadge = self.badgesById[itemId] {
                cell.configure(userBadge: userBadge, baseURL: self.api.baseURL)
            }
            return cell
        }
        source.supplementaryViewProvider = { [weak self] collectionView, kind, indexPath in
            guard kind == UICollectionView.elementKindSectionHeader,
                  let self,
                  indexPath.section < self.sectionTypes.count,
                  let type = self.sectionTypes[indexPath.section]
            else { return nil }
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: BadgeSectionHeaderView.reuseIdentifier,
                for: indexPath
            ) as! BadgeSectionHeaderView
            let count = self.sections.first(where: { $0.0 == type })?.1.count ?? 0
            header.configure(type: type, count: count)
            return header
        }
        return source
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15, weight: .medium)
        return label
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        return control
    }()

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.badges")
        navigationItem.largeTitleDisplayMode = .never
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        view.addSubview(stateLabel)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        settingsObservation = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.applyTheme()
                self?.collectionView.reloadData()
            }
        }
        applyTheme()
        loadBadges()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }

    private func applyTheme() {
        view.backgroundColor = BadgeUIStyle.pageBackground
        collectionView.backgroundColor = .clear
        refreshControl.tintColor = BadgeUIStyle.chromeAccent
        navigationController?.navigationBar.tintColor = BadgeUIStyle.chromeAccent
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard let self else {
                return Self.gridSection(environment: environment, includeHeader: false)
            }
            let type = sectionIndex < self.sectionTypes.count ? self.sectionTypes[sectionIndex] : nil
            if type == nil && sectionIndex == 0 {
                let itemSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(168)
                )
                let item = NSCollectionLayoutItem(layoutSize: itemSize)
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitems: [item])
                let layoutSection = NSCollectionLayoutSection(group: group)
                layoutSection.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
                return layoutSection
            }
            return Self.gridSection(environment: environment, includeHeader: type != nil)
        }
    }

    private static func gridSection(
        environment: NSCollectionLayoutEnvironment,
        includeHeader: Bool
    ) -> NSCollectionLayoutSection {
        let width = environment.container.effectiveContentSize.width
        let columns = width >= 700 ? 3 : 2
        let spacing: CGFloat = 16
        let sideInset: CGFloat = 16
        let available = width - sideInset * 2 - spacing * CGFloat(columns - 1)
        let itemWidth = floor(available / CGFloat(columns))
        let itemHeight = ceil(itemWidth / 1.35)

        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(itemWidth),
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .absolute(itemHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            subitem: item,
            count: columns
        )
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: sideInset, bottom: 8, trailing: sideInset)

        if includeHeader {
            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(44)
            )
            let header = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [header]
            section.contentInsets.top = 8
        }
        return section
    }

    private func loadBadges() {
        isLoading = true
        errorMessage = nil
        updateState()
        Task { @MainActor in
            do {
                let response = try await api.fetchUserBadges(username: username)
                let grouped = Dictionary(grouping: response.userBadges) { badge in
                    badge.badge?.type ?? .bronze
                }
                let ordered: [DiscourseBadge.BadgeType] = [.gold, .silver, .bronze]
                sections = ordered.compactMap { type in
                    guard let badges = grouped[type], !badges.isEmpty else { return nil }
                    return (type, badges.sorted { ($0.badge?.name ?? "") < ($1.badge?.name ?? "") })
                }
                var map: [Int: DiscourseUserBadge] = [:]
                for (_, badges) in sections {
                    for badge in badges {
                        map[badge.id] = badge
                    }
                }
                badgesById = map
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                sections = []
                badgesById = [:]
            }
            isLoading = false
            refreshControl.endRefreshing()
            applySnapshot()
            updateState()
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        sectionTypes = [nil]
        snapshot.appendSections([0])
        snapshot.appendItems([Self.summaryItemId], toSection: 0)

        for (offset, pair) in sections.enumerated() {
            let sectionIndex = offset + 1
            sectionTypes.append(pair.0)
            snapshot.appendSections([sectionIndex])
            // Guard against colliding with summary id 0.
            let ids = pair.1.map { max($0.id, 1) }
            for (badge, id) in zip(pair.1, ids) {
                badgesById[id] = badge
            }
            snapshot.appendItems(ids, toSection: sectionIndex)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func updateState() {
        let hasBadges = !sections.isEmpty
        if let errorMessage {
            stateLabel.isHidden = false
            stateLabel.text = errorMessage
            collectionView.isHidden = true
            return
        }
        if isLoading && !hasBadges {
            stateLabel.isHidden = true
            collectionView.isHidden = false
            applySnapshot()
            return
        }
        if !hasBadges {
            stateLabel.isHidden = false
            stateLabel.text = String(localized: "badges.empty")
            collectionView.isHidden = true
            return
        }
        stateLabel.isHidden = true
        collectionView.isHidden = false
    }

    @objc private func refreshPulled() {
        loadBadges()
    }
}

extension UserBadgesViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let itemId = dataSource.itemIdentifier(for: indexPath),
              itemId != Self.summaryItemId,
              let userBadge = badgesById[itemId],
              let badge = userBadge.badge
        else { return }
        let detail = BadgeDetailViewController(
            api: api,
            badgeId: badge.id,
            username: username,
            previewBadge: badge
        )
        navigationController?.pushViewController(detail, animated: true)
    }
}


// MARK: - Summary header cell

private final class BadgeSummaryHeaderCell: UICollectionViewCell {
    static let reuseIdentifier = "BadgeSummaryHeaderCell"

    private let watermark = UIImageView()
    private let captionLabel = UILabel()
    private let countLabel = UILabel()
    private let unitLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(total: Int) {
        countLabel.text = "\(total)"
        captionLabel.text = String(localized: "badges.total_earned", defaultValue: "累计获得")
        unitLabel.text = String(localized: "badges.unit", defaultValue: "枚徽章")
        applyTheme()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyTheme()
    }

    private func setupUI() {
        let stack = UIStackView(arrangedSubviews: [captionLabel, countLabel, unitLabel])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        watermark.translatesAutoresizingMaskIntoConstraints = false
        watermark.contentMode = .scaleAspectFit
        watermark.alpha = 0.08

        captionLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .medium,
            fallback: .systemFont(ofSize: 14, weight: .medium)
        )
        countLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 36,
            weight: .semibold,
            fallback: .systemFont(ofSize: 36, weight: .semibold)
        )
        unitLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 14,
            weight: .regular,
            fallback: .systemFont(ofSize: 14, weight: .regular)
        )

        contentView.addSubview(watermark)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            watermark.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 12),
            watermark.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -8),
            watermark.widthAnchor.constraint(equalToConstant: 160),
            watermark.heightAnchor.constraint(equalToConstant: 160),

            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: watermark.leadingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    private func applyTheme() {
        let accent = BadgeUIStyle.chromeAccent
        captionLabel.textColor = accent
        countLabel.textColor = .label
        unitLabel.textColor = .secondaryLabel
        let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)
        watermark.image = UIImage(systemName: "medal.fill", withConfiguration: config)?
            .withTintColor(accent, renderingMode: .alwaysOriginal)
        contentView.backgroundColor = BadgeUIStyle.pageBackground
    }
}

// MARK: - Section header

private final class BadgeSectionHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "BadgeSectionHeaderView"

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let countPill = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(type: DiscourseBadge.BadgeType, count: Int) {
        let color = type.color
        titleLabel.text = type.title
        titleLabel.textColor = color
        titleLabel.font = AppSettings.shared.appInterfaceFont(
            ofSize: 18,
            weight: .semibold,
            fallback: .systemFont(ofSize: 18, weight: .semibold)
        )
        iconView.image = BadgeUIStyle.medalSymbolImage(color: color, pointSize: 18)
        countPill.text = " \(count) "
        countPill.textColor = color
        countPill.backgroundColor = color.withAlphaComponent(0.12)
    }

    private func setupUI() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        countPill.translatesAutoresizingMaskIntoConstraints = false
        countPill.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        countPill.textAlignment = .center
        countPill.layer.cornerRadius = 11
        countPill.clipsToBounds = true

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(countPill)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            countPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            countPill.centerYAnchor.constraint(equalTo: centerYAnchor),
            countPill.heightAnchor.constraint(equalToConstant: 22),
            countPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            countPill.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }
}
