import SDWebImage
import UIKit

final class EmojiPickerView: UIView {
    var onEmojiSelected: ((String) -> Void)?

    private static let recentEmojiKey = "reply_recent_forum_emojis"
    private static let maxRecentCount = 30

    private var baseURL = ""
    private var groups: [DiscourseEmojiGroup] = []
    private var recentNames: [String] = []
    private var selectedGroupIndex = 0
    private var isProgrammaticScroll = false

    private var displayGroups: [DiscourseEmojiGroup] {
        var result: [DiscourseEmojiGroup] = []
        let recent = recentEmojis()
        if !recent.isEmpty {
            result.append(DiscourseEmojiGroup(key: "recent", emojis: recent))
        }
        result.append(contentsOf: groups)
        return result
    }

    private let topBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()

    private let searchButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        button.setImage(UIImage(systemName: "magnifyingglass", withConfiguration: config), for: .normal)
        button.tintColor = .systemBlue
        button.accessibilityLabel = String(localized: "emoji.search")
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let dividerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    private lazy var tabCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 40, height: 40)
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.register(EmojiGroupTabCell.self, forCellWithReuseIdentifier: EmojiGroupTabCell.reuseId)
        cv.delegate = self
        cv.dataSource = self
        return cv
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 40, height: 40)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 4, left: 12, bottom: 8, right: 12)
        layout.headerReferenceSize = CGSize(width: 1, height: 28)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.register(ForumEmojiCell.self, forCellWithReuseIdentifier: ForumEmojiCell.reuseId)
        cv.register(
            EmojiSectionHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: EmojiSectionHeaderView.reuseId
        )
        cv.delegate = self
        cv.dataSource = self
        return cv
    }()

    private let loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .callout)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        setupViews()
        loadRecentEmojis()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setEmojiGroups(_ groups: [DiscourseEmojiGroup], baseURL: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.groups = groups.filter { !$0.emojis.isEmpty }
        selectedGroupIndex = 0
        loadingIndicator.stopAnimating()
        statusLabel.isHidden = !self.groups.isEmpty
        statusLabel.text = self.groups.isEmpty ? String(localized: "emoji.not_found") : nil
        tabCollectionView.reloadData()
        collectionView.reloadData()
    }

    func setCustomEmojis(_ emojis: [DiscourseCustomEmoji]) {
        let entries = emojis.map {
            DiscourseEmojiEntry(name: $0.name, url: $0.url, searchAliases: nil)
        }
        setEmojiGroups([DiscourseEmojiGroup(key: "custom", emojis: entries)], baseURL: baseURL)
    }

    func showLoading() {
        statusLabel.isHidden = true
        loadingIndicator.startAnimating()
    }

    func showError() {
        loadingIndicator.stopAnimating()
        groups = []
        selectedGroupIndex = 0
        statusLabel.text = String(localized: "emoji.load_failed")
        statusLabel.isHidden = false
        tabCollectionView.reloadData()
        collectionView.reloadData()
    }

    private func setupViews() {
        addSubview(topBar)
        topBar.addSubview(searchButton)
        topBar.addSubview(dividerView)
        topBar.addSubview(tabCollectionView)
        addSubview(collectionView)
        addSubview(loadingIndicator)
        addSubview(statusLabel)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: topAnchor),
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44),

            searchButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 2),
            searchButton.topAnchor.constraint(equalTo: topBar.topAnchor),
            searchButton.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 44),

            dividerView.leadingAnchor.constraint(equalTo: searchButton.trailingAnchor, constant: 2),
            dividerView.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 0.5),
            dividerView.heightAnchor.constraint(equalToConstant: 22),

            tabCollectionView.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor, constant: 4),
            tabCollectionView.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            tabCollectionView.topAnchor.constraint(equalTo: topBar.topAnchor),
            tabCollectionView.bottomAnchor.constraint(equalTo: topBar.bottomAnchor),

            collectionView.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),

            statusLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])

        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
    }

    private func loadRecentEmojis() {
        recentNames = UserDefaults.standard.stringArray(forKey: Self.recentEmojiKey) ?? []
    }

    private func saveRecentEmoji(_ emoji: DiscourseEmojiEntry) {
        recentNames.removeAll { $0 == emoji.name }
        recentNames.insert(emoji.name, at: 0)
        if recentNames.count > Self.maxRecentCount {
            recentNames = Array(recentNames.prefix(Self.maxRecentCount))
        }
        UserDefaults.standard.set(recentNames, forKey: Self.recentEmojiKey)
    }

    private func recentEmojis() -> [DiscourseEmojiEntry] {
        guard !recentNames.isEmpty else { return [] }
        let allEmojis = groups.flatMap(\.emojis)
        var lookup: [String: DiscourseEmojiEntry] = [:]
        for emoji in allEmojis where lookup[emoji.name] == nil {
            lookup[emoji.name] = emoji
        }
        return recentNames.compactMap { lookup[$0] }
    }

    private func selectEmoji(_ emoji: DiscourseEmojiEntry) {
        saveRecentEmoji(emoji)
        onEmojiSelected?(":\(emoji.name):")
    }

    @objc private func searchTapped() {
        let allEmojis = groups.flatMap(\.emojis)
        guard !allEmojis.isEmpty, let presenter = nearestViewController() else { return }
        let search = EmojiSearchViewController(emojis: allEmojis, baseURL: baseURL)
        search.onEmojiSelected = { [weak self] emoji in
            self?.selectEmoji(emoji)
        }
        let nav = UINavigationController(rootViewController: search)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        presenter.present(nav, animated: true)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let viewController = next as? UIViewController {
                return viewController
            }
            responder = next
        }
        return nil
    }

    private func scrollToGroup(at index: Int) {
        let groups = displayGroups
        guard groups.indices.contains(index) else { return }
        selectedGroupIndex = index
        tabCollectionView.reloadData()
        isProgrammaticScroll = true
        collectionView.scrollToItem(at: IndexPath(item: 0, section: index), at: .top, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.isProgrammaticScroll = false
        }
    }

    private func updateSelectedGroupFromVisibleItems() {
        guard !isProgrammaticScroll else { return }
        let visibleSections = collectionView.indexPathsForVisibleItems.map(\.section)
        guard let section = visibleSections.min(), section != selectedGroupIndex else { return }
        selectedGroupIndex = section
        tabCollectionView.reloadData()
        tabCollectionView.scrollToItem(at: IndexPath(item: section, section: 0), at: .centeredHorizontally, animated: true)
    }
}

extension EmojiPickerView: UICollectionViewDataSource {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        collectionView === tabCollectionView ? 1 : displayGroups.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let groups = displayGroups
        if collectionView === tabCollectionView {
            return groups.count
        }
        guard groups.indices.contains(section) else { return 0 }
        return groups[section].emojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let groups = displayGroups
        if collectionView === tabCollectionView {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmojiGroupTabCell.reuseId, for: indexPath) as! EmojiGroupTabCell
            guard groups.indices.contains(indexPath.item) else { return cell }
            cell.configure(
                group: groups[indexPath.item],
                isSelected: indexPath.item == selectedGroupIndex,
                baseURL: baseURL
            )
            return cell
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ForumEmojiCell.reuseId, for: indexPath) as! ForumEmojiCell
        guard groups.indices.contains(indexPath.section),
              groups[indexPath.section].emojis.indices.contains(indexPath.item)
        else { return cell }
        cell.configure(emoji: groups[indexPath.section].emojis[indexPath.item], baseURL: baseURL)
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard collectionView === self.collectionView,
              kind == UICollectionView.elementKindSectionHeader
        else {
            return UICollectionReusableView()
        }
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: EmojiSectionHeaderView.reuseId,
            for: indexPath
        ) as! EmojiSectionHeaderView
        let groups = displayGroups
        if groups.indices.contains(indexPath.section) {
            header.configure(title: Self.groupTitle(for: groups[indexPath.section].key))
        }
        return header
    }
}

extension EmojiPickerView: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let groups = displayGroups
        if collectionView === tabCollectionView {
            scrollToGroup(at: indexPath.item)
            return
        }
        guard groups.indices.contains(indexPath.section),
              groups[indexPath.section].emojis.indices.contains(indexPath.item)
        else { return }
        selectEmoji(groups[indexPath.section].emojis[indexPath.item])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateSelectedGroupFromVisibleItems()
    }
}

extension EmojiPickerView {
    static func resolvedEmojiURL(_ rawURL: String, baseURL: String) -> URL? {
        if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
            return URL(string: rawURL)
        }
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if rawURL.hasPrefix("//") {
            return URL(string: "https:\(rawURL)")
        }
        if rawURL.hasPrefix("/") {
            return URL(string: trimmedBase + rawURL)
        }
        return URL(string: trimmedBase + "/" + rawURL)
    }

    static func groupTitle(for key: String) -> String {
        switch key {
        case "recent":
            return String(localized: "emoji.recent")
        case "custom":
            return String(localized: "emoji.custom")
        case "smileys_&_emotion":
            return String(localized: "emoji.smileys")
        case "people_&_body":
            return String(localized: "emoji.people")
        case "animals_&_nature":
            return String(localized: "emoji.animals")
        case "food_&_drink":
            return String(localized: "emoji.food")
        case "activities":
            return String(localized: "emoji.activities")
        case "travel_&_places":
            return String(localized: "emoji.travel")
        case "objects":
            return String(localized: "emoji.objects")
        case "symbols":
            return String(localized: "emoji.symbols")
        case "flags":
            return String(localized: "emoji.flags")
        default:
            return key
                .replacingOccurrences(of: "_&_", with: " & ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }
}

private final class EmojiGroupTabCell: UICollectionViewCell {
    static let reuseId = "EmojiGroupTabCell"

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let symbolView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .secondaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        contentView.addSubview(imageView)
        contentView.addSubview(symbolView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalToConstant: 24),

            symbolView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            symbolView.widthAnchor.constraint(equalToConstant: 20),
            symbolView.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(group: DiscourseEmojiGroup, isSelected: Bool, baseURL: String) {
        contentView.backgroundColor = isSelected ? UIColor.systemBlue.withAlphaComponent(0.14) : .clear
        if group.key == "recent" {
            imageView.isHidden = true
            symbolView.isHidden = false
            symbolView.image = UIImage(systemName: "clock")
            symbolView.tintColor = isSelected ? .systemBlue : .secondaryLabel
            return
        }

        symbolView.isHidden = true
        imageView.isHidden = false
        if let first = group.emojis.first,
           let url = EmojiPickerView.resolvedEmojiURL(first.url, baseURL: baseURL) {
            ForumImageLoader.setImage(on: imageView, url: url)
        } else {
            imageView.image = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = nil
        symbolView.image = nil
    }
}

private final class EmojiSectionHeaderView: UICollectionReusableView {
    static let reuseId = "EmojiSectionHeaderView"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        titleLabel.text = title
    }
}

private final class ForumEmojiCell: UICollectionViewCell {
    static let reuseId = "ForumEmojiCell"

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 6
        contentView.layer.cornerCurve = .continuous
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: DiscourseEmojiEntry, baseURL: String) {
        accessibilityLabel = ":\(emoji.name):"
        if let url = EmojiPickerView.resolvedEmojiURL(emoji.url, baseURL: baseURL) {
            ForumImageLoader.setImage(on: imageView, url: url)
        } else {
            imageView.image = nil
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = nil
    }
}

private final class EmojiSearchViewController: UIViewController {
    var onEmojiSelected: ((DiscourseEmojiEntry) -> Void)?

    private let emojis: [DiscourseEmojiEntry]
    private let baseURL: String
    private var filteredEmojis: [DiscourseEmojiEntry] = []

    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = String(localized: "emoji.search_placeholder")
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 44, height: 44)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 16, right: 16)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .systemBackground
        cv.register(ForumEmojiCell.self, forCellWithReuseIdentifier: ForumEmojiCell.reuseId)
        cv.delegate = self
        cv.dataSource = self
        return cv
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .callout)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.text = String(localized: "emoji.search_prompt")
        return label
    }()

    init(emojis: [DiscourseEmojiEntry], baseURL: String) {
        self.emojis = emojis
        self.baseURL = baseURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "emoji.search")
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "common.cancel"),
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        searchBar.delegate = self

        view.addSubview(searchBar)
        view.addSubview(collectionView)
        view.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            collectionView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func applySearch(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            filteredEmojis = []
            emptyLabel.text = String(localized: "emoji.search_prompt")
            emptyLabel.isHidden = false
            collectionView.reloadData()
            return
        }
        filteredEmojis = emojis.filter { emoji in
            emoji.name.lowercased().contains(query)
                || (emoji.searchAliases ?? []).contains { $0.lowercased().contains(query) }
        }
        emptyLabel.text = filteredEmojis.isEmpty
            ? String(localized: "emoji.search_not_found")
            : nil
        emptyLabel.isHidden = !filteredEmojis.isEmpty
        collectionView.reloadData()
    }
}

extension EmojiSearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applySearch(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

extension EmojiSearchViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        filteredEmojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ForumEmojiCell.reuseId, for: indexPath) as! ForumEmojiCell
        cell.configure(emoji: filteredEmojis[indexPath.item], baseURL: baseURL)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = filteredEmojis[indexPath.item]
        dismiss(animated: true) { [onEmojiSelected] in
            onEmojiSelected?(emoji)
        }
    }
}
