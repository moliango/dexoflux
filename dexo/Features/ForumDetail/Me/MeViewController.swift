import SafariServices
import SDWebImage
import UIKit
import WebKit

final class MeViewController: ObservableViewController {
    private let api: DiscourseAPI
    private let viewModel: MeViewModel
    private weak var authGate: AuthGating?

    private let statsPreferences = MeStatsPreferences()
    private let profileCard = MeProfileCardView()
    private let statsCard = MeStatsCardView()
    private let actionsCard = MeActionCardView()
    private let loadingSkeletonView = MeDashboardSkeletonView()

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let contentStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        return rc
    }()

    init(api: DiscourseAPI, authGate: AuthGating? = nil) {
        self.api = api
        self.viewModel = MeViewModel(api: api)
        self.authGate = authGate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "tab.me")
        applyThemeStyle()

        setupLayout()
        setupActions()
        loadData()
    }

    override func updateUI() {
        applyThemeStyle()
        if !viewModel.isLoading, refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        activityIndicator.stopAnimating()

        let isLoggedIn = (authGate?.isAuthenticated() ?? false) && !viewModel.requiresLogin
        let showsInitialSkeleton = viewModel.isLoading
            && isLoggedIn
            && viewModel.currentUser == nil
            && viewModel.userProfile == nil
        loadingSkeletonView.setSkeletonActive(showsInitialSkeleton, animated: view.window != nil)
        scrollView.isHidden = showsInitialSkeleton

        if let error = viewModel.errorMessage {
            loadingSkeletonView.setSkeletonActive(false, animated: view.window != nil)
            scrollView.isHidden = false
            let alert = UIAlertController(title: nil, message: error, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
            present(alert, animated: true)
            viewModel.errorMessage = nil
            return
        }

        if isLoggedIn {
            profileCard.configure(
                user: viewModel.currentUser,
                profile: viewModel.userProfile,
                baseURL: api.baseURL
            )
            statsCard.configure(items: makeStatItems(), isLoggedIn: true)
        } else {
            profileCard.configure(user: nil, profile: nil, baseURL: api.baseURL)
            statsCard.configure(items: [], isLoggedIn: false)
        }

        configureActionRows(isLoggedIn: isLoggedIn)
    }

    private func setupLayout() {
        scrollView.refreshControl = refreshControl

        view.addSubview(scrollView)
        view.addSubview(loadingSkeletonView)
        view.addSubview(activityIndicator)
        scrollView.addSubview(contentStackView)

        contentStackView.addArrangedSubview(profileCard)
        contentStackView.addArrangedSubview(statsCard)
        contentStackView.addArrangedSubview(actionsCard)
        contentStackView.addArrangedSubview(makeAuthButtonContainer())

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingSkeletonView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            loadingSkeletonView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            loadingSkeletonView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            loadingSkeletonView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -28),

            contentStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupActions() {
        profileCard.onLoginTapped = { [weak self] in
            self?.loginTapped()
        }
        profileCard.onProfileTapped = { [weak self] in
            self?.openCurrentUserProfile()
        }
        statsCard.onCustomizeTapped = { [weak self] in
            self?.showStatsCustomizer()
        }
    }

    private func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        view.backgroundColor = themeStyle.topicListBackgroundColor
        scrollView.backgroundColor = themeStyle.topicListBackgroundColor
        refreshControl.tintColor = themeStyle.accentColor
        activityIndicator.color = themeStyle.accentColor
        loadingSkeletonView.applyThemeStyle()
    }

    private func makeAuthButtonContainer() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.addTarget(self, action: #selector(authButtonTapped), for: .touchUpInside)
        button.tag = 9001

        container.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        return container
    }

    private func configureActionRows(isLoggedIn: Bool) {
        let trustLevel = viewModel.userProfile?.trustLevel ?? 0
        let rows: [MeActionRow] = [
            MeActionRow(
                title: String(localized: "messages.title"),
                subtitle: String(localized: "me.action.messages.subtitle"),
                symbolName: "envelope.fill",
                tintColor: .systemIndigo,
                isEnabled: isLoggedIn,
                action: { [weak self] in self?.openMessages() }
            ),
            MeActionRow(
                title: String(localized: "me.bookmarks"),
                subtitle: String(localized: "me.action.bookmarks.subtitle"),
                symbolName: "bookmark.fill",
                tintColor: .systemOrange,
                isEnabled: isLoggedIn,
                action: { [weak self] in self?.openBookmarks() }
            ),
            MeActionRow(
                title: String(localized: "me.badges"),
                subtitle: String(localized: "me.action.badges.subtitle"),
                symbolName: "medal.fill",
                tintColor: .systemYellow,
                isEnabled: isLoggedIn,
                action: { [weak self] in self?.openBadges() }
            ),
            MeActionRow(
                title: String(localized: "me.trust_requirements"),
                subtitle: String(localized: "me.action.trust.subtitle"),
                symbolName: "checkmark.shield.fill",
                tintColor: .systemGreen,
                isEnabled: isLoggedIn,
                action: { [weak self] in self?.openTrustRequirements() }
            ),
            MeActionRow(
                title: String(localized: "me.invite_links"),
                subtitle: trustLevel >= 3 ? String(localized: "me.action.invites.subtitle") : String(localized: "me.invite_links.requires_level"),
                symbolName: "link.circle.fill",
                tintColor: .systemCyan,
                isEnabled: isLoggedIn && trustLevel >= 3,
                action: { [weak self] in self?.openInviteLinks() }
            ),
            MeActionRow(
                title: String(localized: "me.settings"),
                subtitle: String(localized: "me.action.settings.subtitle"),
                symbolName: "gearshape.fill",
                tintColor: .systemBlue,
                isEnabled: true,
                action: { [weak self] in self?.openSettings() }
            ),
        ]
        actionsCard.configure(title: String(localized: "me.actions.title"), rows: rows)

        if let authButton = (contentStackView.arrangedSubviews.last?.subviews.first as? UIButton) {
            let title = isLoggedIn ? String(localized: "me.logout") : String(localized: "me.login")
            authButton.setTitle(title, for: .normal)
            authButton.setTitleColor(isLoggedIn ? .systemRed : .tintColor, for: .normal)
        }
    }

    private func loadData() {
        guard authGate?.isAuthenticated() == true else {
            MeProfileCacheStore.clear(baseURL: api.baseURL)
            viewModel.clearSessionState(requiresLogin: true)
            return
        }
        Task {
            await viewModel.loadProfile()
        }
    }

    @objc private func pullToRefresh() {
        Task {
            if authGate?.isAuthenticated() == true {
                await viewModel.reload()
            }
            refreshControl.endRefreshing()
        }
    }

    @objc private func authButtonTapped() {
        if authGate?.isAuthenticated() == true {
            logoutTapped()
        } else {
            loginTapped()
        }
    }

    private func loginTapped() {
        authGate?.requireAuth { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.reload()
            }
        }
    }

    private func logoutTapped() {
        let alert = UIAlertController(
            title: String(localized: "me.logout.confirm.title"),
            message: String(localized: "me.logout.confirm.message"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "me.logout"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.authGate?.performLogout()
            self.viewModel.clearSessionState(requiresLogin: true)
            self.updateUI()
        })
        alert.addAction(UIAlertAction(title: String(localized: "cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func makeStatItems() -> [MeStatItem] {
        statsPreferences.selectedStats.compactMap { type in
            switch type {
            case .topicCount:
                return MeStatItem(type: type, value: viewModel.summary?.topicCount)
            case .postCount:
                return MeStatItem(type: type, value: viewModel.summary?.postCount)
            case .likesReceived:
                return MeStatItem(type: type, value: viewModel.summary?.likesReceived)
            case .likesGiven:
                return MeStatItem(type: type, value: viewModel.summary?.likesGiven)
            case .daysVisited:
                return MeStatItem(type: type, value: viewModel.summary?.daysVisited)
            case .timeRead:
                return MeStatItem(type: type, valueText: formatDuration(seconds: viewModel.userProfile?.timeRead))
            case .profileViews:
                return MeStatItem(type: type, value: viewModel.userProfile?.profileViewCount)
            case .badges:
                return MeStatItem(type: type, value: viewModel.userProfile?.badgeCount)
            }
        }
    }

    private func formatDuration(seconds: Int?) -> String? {
        guard let seconds else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour] : [.minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds))
    }

    private func showStatsCustomizer() {
        let alert = UIAlertController(title: String(localized: "me.stats.customize"), message: nil, preferredStyle: .actionSheet)
        let selected = Set(statsPreferences.selectedStats)
        for type in MeStatType.allCases {
            let action = UIAlertAction(title: type.title, style: .default) { [weak self] _ in
                self?.toggleStat(type)
            }
            action.setValue(selected.contains(type), forKey: "checked")
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = statsCard
        alert.popoverPresentationController?.sourceRect = statsCard.bounds
        present(alert, animated: true)
    }

    private func toggleStat(_ type: MeStatType) {
        var selected = statsPreferences.selectedStats
        if selected.contains(type) {
            guard selected.count > 1 else { return }
            selected.removeAll { $0 == type }
        } else {
            selected.append(type)
        }
        statsPreferences.selectedStats = selected
        statsCard.configure(items: makeStatItems(), isLoggedIn: authGate?.isAuthenticated() == true)
    }

    private func openCurrentUserProfile() {
        guard let username = viewModel.currentUser?.username else { return }
        let vc = UserProfileViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openMessages() {
        guard authGate?.isAuthenticated() == true else {
            loginTapped()
            return
        }
        let vc = MessagesViewController(api: api, authGate: authGate)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openBookmarks() {
        guard let username = viewModel.currentUser?.username else {
            loginTapped()
            return
        }
        let vc = BookmarksViewController(api: api, username: username, authGate: authGate)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openBadges() {
        guard let username = viewModel.currentUser?.username else {
            loginTapped()
            return
        }
        let vc = UserBadgesViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openTrustRequirements() {
        let vc = TrustRequirementsViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openInviteLinks() {
        guard let username = viewModel.currentUser?.username else {
            loginTapped()
            return
        }
        let vc = InviteLinksViewController(api: api, username: username)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openSettings() {
        let vc = SettingsViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openUserWebPath(_ path: String) {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let baseURL = api.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        openExternalURL(baseURL + normalizedPath)
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            showInfoAlert(String(localized: "me.web.open_error"))
            return
        }
        let safari = SFSafariViewController(url: url)
        present(safari, animated: true)
    }

    private func showInfoAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        present(alert, animated: true)
    }
}

private final class UserBadgesViewController: UIViewController {
    private let api: DiscourseAPI
    private let username: String
    private var sections: [(DiscourseBadge.BadgeType, [DiscourseUserBadge])] = []
    private var isLoading = false
    private var errorMessage: String?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 76
        return table
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
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
        view.backgroundColor = .systemGroupedBackground
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        view.addSubview(stateLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        loadBadges()
    }

    private func loadBadges() {
        isLoading = true
        errorMessage = nil
        updateState()
        Task {
            do {
                let response = try await api.fetchUserBadges(username: username)
                let grouped: [DiscourseBadge.BadgeType: [DiscourseUserBadge]] = Dictionary(grouping: response.userBadges) { badge in
                    badge.badge?.type ?? DiscourseBadge.BadgeType.bronze
                }
                let orderedTypes: [DiscourseBadge.BadgeType] = [.gold, .silver, .bronze]
                sections = orderedTypes.compactMap { type in
                    guard let badges = grouped[type], !badges.isEmpty else { return nil }
                    return (type, badges.sorted { ($0.badge?.name ?? "") < ($1.badge?.name ?? "") })
                }
            } catch {
                errorMessage = error.localizedDescription
                sections = []
            }
            isLoading = false
            refreshControl.endRefreshing()
            tableView.reloadData()
            updateState()
        }
    }

    private func updateState() {
        tableView.isHidden = sections.isEmpty
        stateLabel.isHidden = !sections.isEmpty
        if isLoading {
            stateLabel.text = String(localized: "badges.loading")
        } else if let errorMessage {
            stateLabel.text = errorMessage
        } else {
            stateLabel.text = String(localized: "badges.empty")
        }
    }

    @objc private func refreshPulled() {
        loadBadges()
    }
}

extension UserBadgesViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].1.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section = sections[section]
        return "\(section.0.title) · \(section.1.count)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let badge = sections[indexPath.section].1[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let type = badge.badge?.type ?? .bronze
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: "medal.fill")
        content.imageProperties.tintColor = type.color
        content.text = badge.badge?.name ?? String(localized: "badges.unknown")
        content.secondaryText = badge.topicTitle ?? badge.badge?.description
        content.secondaryTextProperties.color = .secondaryLabel
        content.textProperties.font = .systemFont(ofSize: 15, weight: .semibold)
        cell.contentConfiguration = content
        if badge.count > 1 {
            let label = UILabel()
            label.text = "×\(badge.count)"
            label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            label.textColor = type.color
            cell.accessoryView = label
        } else if badge.topicId != nil {
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }
}

extension UserBadgesViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicId = sections[indexPath.section].1[indexPath.row].topicId else { return }
        let detail = TopicDetailViewController(api: api, topicId: topicId)
        navigationController?.pushViewController(detail, animated: true)
    }
}

private final class InviteLinksViewController: UIViewController {
    private let api: DiscourseAPI
    private let username: String
    private var invites: [DiscourseInviteLink] = []
    private var isLoading = false
    private var errorMessage: String?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        return table
    }()

    private let stateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
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
        title = String(localized: "me.invite_links")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(createTapped))
        tableView.refreshControl = refreshControl

        view.addSubview(tableView)
        view.addSubview(stateLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stateLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        loadInvites()
    }

    private func loadInvites() {
        isLoading = true
        errorMessage = nil
        updateState()
        Task {
            do {
                invites = try await api.fetchPendingInvites(username: username)
            } catch {
                errorMessage = error.localizedDescription
                invites = []
            }
            isLoading = false
            refreshControl.endRefreshing()
            tableView.reloadData()
            updateState()
        }
    }

    private func updateState() {
        tableView.isHidden = invites.isEmpty
        stateLabel.isHidden = !invites.isEmpty
        if isLoading {
            stateLabel.text = String(localized: "invites.loading")
        } else if let errorMessage {
            stateLabel.text = errorMessage
        } else {
            stateLabel.text = String(localized: "invites.empty")
        }
    }

    @objc private func refreshPulled() {
        loadInvites()
    }

    @objc private func createTapped() {
        let alert = UIAlertController(
            title: String(localized: "invites.create.title"),
            message: String(localized: "invites.create.message"),
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = String(localized: "invites.description.placeholder")
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "invites.create.action"), style: .default) { [weak self] _ in
            guard let self else { return }
            let description = alert.textFields?.first?.text
            let expiresAt = Calendar.current.date(byAdding: .day, value: 1, to: Date())
            Task {
                do {
                    let invite = try await self.api.createInvite(description: description, expiresAt: expiresAt)
                    self.invites.insert(invite, at: 0)
                    self.tableView.reloadData()
                    self.updateState()
                    if let url = invite.effectiveURLString {
                        UIPasteboard.general.string = url
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.updateState()
                }
            }
        })
        present(alert, animated: true)
    }

    private func showActions(for invite: DiscourseInviteLink, sourceView: UIView) {
        guard let urlString = invite.effectiveURLString else { return }
        let alert = UIAlertController(title: urlString, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: String(localized: "invites.copy"), style: .default) { _ in
            UIPasteboard.general.string = urlString
        })
        alert.addAction(UIAlertAction(title: String(localized: "invites.share"), style: .default) { [weak self] _ in
            let activity = UIActivityViewController(activityItems: [urlString], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = sourceView
            self?.present(activity, animated: true)
        })
        if let url = URL(string: urlString) {
            alert.addAction(UIAlertAction(title: String(localized: "action.open"), style: .default) { [weak self] _ in
                self?.present(SFSafariViewController(url: url), animated: true)
            })
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.popoverPresentationController?.sourceView = sourceView
        alert.popoverPresentationController?.sourceRect = sourceView.bounds
        present(alert, animated: true)
    }
}

extension InviteLinksViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        invites.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let invite = invites[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.image = UIImage(systemName: "link.circle.fill")
        content.imageProperties.tintColor = .systemCyan
        content.text = invite.effectiveURLString ?? String(localized: "invites.unknown")
        content.secondaryText = invite.description ?? invite.expiresAt ?? invite.createdAt
        content.secondaryTextProperties.color = .secondaryLabel
        content.textProperties.font = .systemFont(ofSize: 14, weight: .semibold)
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

extension InviteLinksViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        showActions(for: invites[indexPath.row], sourceView: cell)
    }
}

private final class TrustRequirementsViewController: UIViewController, WKNavigationDelegate {
    private let webView: WKWebView = {
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        return webView
    }()

    private let progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.trust_requirements")
        view.backgroundColor = .systemBackground
        webView.navigationDelegate = self

        view.addSubview(webView)
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        if let url = URL(string: "https://connect.linux.do/") {
            webView.load(URLRequest(url: url))
        }
    }

    deinit {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == #keyPath(WKWebView.estimatedProgress) else { return }
        progressView.progress = Float(webView.estimatedProgress)
        progressView.isHidden = webView.estimatedProgress >= 1
    }
}

private struct MeActionRow {
    let title: String
    let subtitle: String
    let symbolName: String
    let tintColor: UIColor
    let isEnabled: Bool
    let action: () -> Void
}

private enum MeStatType: String, CaseIterable {
    case daysVisited
    case topicCount
    case postCount
    case likesReceived
    case likesGiven
    case timeRead
    case profileViews
    case badges

    var title: String {
        switch self {
        case .daysVisited: return String(localized: "me.stats.days")
        case .topicCount: return String(localized: "me.stats.topics")
        case .postCount: return String(localized: "me.stats.posts")
        case .likesReceived: return String(localized: "me.stats.likes")
        case .likesGiven: return String(localized: "me.stats.likes_given")
        case .timeRead: return String(localized: "me.stats.time_read")
        case .profileViews: return String(localized: "me.stats.profile_views")
        case .badges: return String(localized: "me.stats.badges")
        }
    }

    var symbolName: String {
        switch self {
        case .daysVisited: return "calendar"
        case .topicCount: return "text.bubble.fill"
        case .postCount: return "bubble.left.and.bubble.right.fill"
        case .likesReceived: return "heart.fill"
        case .likesGiven: return "hand.thumbsup.fill"
        case .timeRead: return "clock.fill"
        case .profileViews: return "eye.fill"
        case .badges: return "medal.fill"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .daysVisited: return .systemTeal
        case .topicCount: return .systemBlue
        case .postCount: return .systemIndigo
        case .likesReceived: return .systemPink
        case .likesGiven: return .systemPurple
        case .timeRead: return .systemGreen
        case .profileViews: return .systemOrange
        case .badges: return .systemYellow
        }
    }
}

private struct MeStatItem {
    let type: MeStatType
    let valueText: String

    init(type: MeStatType, value: Int?) {
        self.type = type
        self.valueText = value.map(Self.formatNumber) ?? "-"
    }

    init(type: MeStatType, valueText: String?) {
        self.type = type
        self.valueText = valueText ?? "-"
    }

    private static func formatNumber(_ value: Int) -> String {
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

private final class MeStatsPreferences {
    private let key = "me.stats.selected"
    private let defaults = UserDefaults.standard
    private let fallback: [MeStatType] = [.daysVisited, .postCount, .likesReceived, .topicCount]

    var selectedStats: [MeStatType] {
        get {
            guard let raw = defaults.stringArray(forKey: key) else { return fallback }
            let selected = raw.compactMap(MeStatType.init(rawValue:))
            return selected.isEmpty ? fallback : selected
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: key)
        }
    }
}

private final class MeDashboardSkeletonView: DexoSkeletonPlaceholderView {
    private var cardSurfaces: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        skeletonContentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: skeletonContentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: skeletonContentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: skeletonContentView.bottomAnchor),
        ])

        stack.addArrangedSubview(makeProfileCard())
        stack.addArrangedSubview(makeStatsCard())
        stack.addArrangedSubview(makeActionsCard())
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        applySkeletonTheme(
            backgroundColor: .clear,
            blockColor: themeStyle.accentColor.withAlphaComponent(0.12)
        )
        cardSurfaces.forEach {
            $0.backgroundColor = themeStyle.topicCardBackgroundColor
            $0.layer.borderColor = UIColor.separator.withAlphaComponent(0.20).cgColor
        }
    }

    private func makeCardSurface(height: CGFloat) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0.5
        cardSurfaces.append(card)
        card.heightAnchor.constraint(equalToConstant: height).isActive = true
        return card
    }

    private func makeProfileCard() -> UIView {
        let card = makeCardSurface(height: 108)
        let avatar = makeSkeletonBlock(cornerRadius: 36)
        let name = makeSkeletonBlock(cornerRadius: 6)
        let username = makeSkeletonBlock(cornerRadius: 5)
        let badge = makeSkeletonBlock(cornerRadius: 11)

        [avatar, name, username, badge].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            avatar.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 72),
            avatar.heightAnchor.constraint(equalToConstant: 72),

            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 16),
            name.topAnchor.constraint(equalTo: avatar.topAnchor, constant: 6),
            name.widthAnchor.constraint(equalToConstant: 156),
            name.heightAnchor.constraint(equalToConstant: 20),

            username.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            username.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 10),
            username.widthAnchor.constraint(equalToConstant: 118),
            username.heightAnchor.constraint(equalToConstant: 14),

            badge.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            badge.topAnchor.constraint(equalTo: username.bottomAnchor, constant: 10),
            badge.widthAnchor.constraint(equalToConstant: 82),
            badge.heightAnchor.constraint(equalToConstant: 22),
        ])

        return card
    }

    private func makeStatsCard() -> UIView {
        let card = makeCardSurface(height: 142)
        let title = makeSkeletonBlock(cornerRadius: 6)
        card.addSubview(title)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.widthAnchor.constraint(equalToConstant: 110),
            title.heightAnchor.constraint(equalToConstant: 16),
        ])

        var previous: UIView?
        for index in 0 ..< 4 {
            let column = UIView()
            column.translatesAutoresizingMaskIntoConstraints = false
            let icon = makeSkeletonBlock(cornerRadius: 12)
            let value = makeSkeletonBlock(cornerRadius: 5)
            let label = makeSkeletonBlock(cornerRadius: 4)
            column.addSubview(icon)
            column.addSubview(value)
            column.addSubview(label)
            card.addSubview(column)

            NSLayoutConstraint.activate([
                column.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 20),
                column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
                column.widthAnchor.constraint(equalTo: card.widthAnchor, multiplier: 0.20),

                icon.topAnchor.constraint(equalTo: column.topAnchor),
                icon.centerXAnchor.constraint(equalTo: column.centerXAnchor),
                icon.widthAnchor.constraint(equalToConstant: 34),
                icon.heightAnchor.constraint(equalToConstant: 34),

                value.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 9),
                value.centerXAnchor.constraint(equalTo: column.centerXAnchor),
                value.widthAnchor.constraint(equalToConstant: 44),
                value.heightAnchor.constraint(equalToConstant: 16),

                label.topAnchor.constraint(equalTo: value.bottomAnchor, constant: 8),
                label.centerXAnchor.constraint(equalTo: column.centerXAnchor),
                label.widthAnchor.constraint(equalToConstant: 52),
                label.heightAnchor.constraint(equalToConstant: 10),
            ])

            if let previous {
                column.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 8).isActive = true
            } else {
                column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14).isActive = true
            }
            if index == 3 {
                column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14).isActive = true
            }
            previous = column
        }

        return card
    }

    private func makeActionsCard() -> UIView {
        let card = makeCardSurface(height: 224)
        let title = makeSkeletonBlock(cornerRadius: 6)
        card.addSubview(title)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.widthAnchor.constraint(equalToConstant: 128),
            title.heightAnchor.constraint(equalToConstant: 16),
        ])

        var previousRow: UIView = title
        for _ in 0 ..< 3 {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false
            let icon = makeSkeletonBlock(cornerRadius: 11)
            let rowTitle = makeSkeletonBlock(cornerRadius: 5)
            let subtitle = makeSkeletonBlock(cornerRadius: 4)
            row.addSubview(icon)
            row.addSubview(rowTitle)
            row.addSubview(subtitle)
            card.addSubview(row)

            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: previousRow.bottomAnchor, constant: previousRow === title ? 14 : 0),
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                row.heightAnchor.constraint(equalToConstant: 56),

                icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
                icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 38),
                icon.heightAnchor.constraint(equalToConstant: 38),

                rowTitle.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
                rowTitle.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
                rowTitle.widthAnchor.constraint(equalToConstant: 136),
                rowTitle.heightAnchor.constraint(equalToConstant: 14),

                subtitle.leadingAnchor.constraint(equalTo: rowTitle.leadingAnchor),
                subtitle.topAnchor.constraint(equalTo: rowTitle.bottomAnchor, constant: 8),
                subtitle.widthAnchor.constraint(equalToConstant: 188),
                subtitle.heightAnchor.constraint(equalToConstant: 11),
            ])
            previousRow = row
        }

        return card
    }
}

private final class MeProfileCardView: UIView {
    var onLoginTapped: (() -> Void)?
    var onProfileTapped: (() -> Void)?

    private let cardView = MeCardSurfaceView()
    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = .tertiarySystemFill
        iv.layer.cornerRadius = 36
        return iv
    }()
    private let nameLabel = UILabel()
    private let usernameLabel = UILabel()
    private let levelLabel = UILabel()
    private let loginButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "me.login")
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let chevronImageView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = .tertiaryLabel
        return iv
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
        translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 1
        usernameLabel.font = .systemFont(ofSize: 14, weight: .regular)
        usernameLabel.textColor = .secondaryLabel
        levelLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        levelLabel.textAlignment = .center
        levelLabel.textColor = .systemBlue
        levelLabel.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        levelLabel.layer.cornerRadius = 7
        levelLabel.layer.cornerCurve = .continuous
        levelLabel.layer.masksToBounds = true
        levelLabel.setContentHuggingPriority(.required, for: .horizontal)

        let infoStack = UIStackView(arrangedSubviews: [nameLabel, usernameLabel, levelLabel])
        infoStack.axis = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 6
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(avatarImageView)
        cardView.addSubview(infoStack)
        cardView.addSubview(chevronImageView)
        cardView.addSubview(loginButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(profileTapped))
        cardView.addGestureRecognizer(tap)
        cardView.isUserInteractionEnabled = true
        loginButton.addTarget(self, action: #selector(loginTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            avatarImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            avatarImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            avatarImageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),
            avatarImageView.widthAnchor.constraint(equalToConstant: 72),
            avatarImageView.heightAnchor.constraint(equalToConstant: 72),

            infoStack.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 16),
            infoStack.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor),
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: chevronImageView.leadingAnchor, constant: -12),
            infoStack.trailingAnchor.constraint(lessThanOrEqualTo: loginButton.leadingAnchor, constant: -12),

            levelLabel.heightAnchor.constraint(equalToConstant: 22),
            levelLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 74),

            chevronImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            chevronImageView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 10),

            loginButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            loginButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            loginButton.heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    func configure(user: DiscourseCurrentUser?, profile: DiscourseUserProfile?, baseURL: String) {
        guard let user else {
            avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
            avatarImageView.tintColor = .tertiaryLabel
            nameLabel.text = String(localized: "me.not_logged_in")
            usernameLabel.text = String(localized: "me.login_prompt")
            levelLabel.isHidden = true
            chevronImageView.isHidden = true
            loginButton.isHidden = false
            return
        }

        loginButton.isHidden = true
        chevronImageView.isHidden = false
        levelLabel.isHidden = false
        nameLabel.text = profile?.name ?? user.name ?? user.username
        usernameLabel.text = "@\(user.username)"
        levelLabel.text = trustLevelText(profile?.trustLevel)

        let avatarTemplate = profile?.avatarTemplate ?? user.avatarTemplate
        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: avatarTemplate,
            baseURL: baseURL,
            size: 240,
            placeholder: UIImage(systemName: "person.crop.circle.fill")
        )
    }

    private func trustLevelText(_ level: Int?) -> String {
        switch level {
        case 0: return String(localized: "me.profile.level_0")
        case 1: return String(localized: "me.profile.level_1")
        case 2: return String(localized: "me.profile.level_2")
        case 3: return String(localized: "me.profile.level_3")
        case 4: return String(localized: "me.profile.level_4")
        case let level?: return String(localized: "me.profile.level_unknown \(level)")
        case nil: return String(localized: "me.profile.level_unknown 0")
        }
    }

    @objc private func loginTapped() {
        onLoginTapped?()
    }

    @objc private func profileTapped() {
        if loginButton.isHidden {
            onProfileTapped?()
        }
    }
}

private final class MeStatsCardView: UIView {
    var onCustomizeTapped: (() -> Void)?

    private let cardView = MeCardSurfaceView()
    private let titleLabel = UILabel()
    private let customizeButton = UIButton(type: .system)
    private let gridStackView = UIStackView()
    private let emptyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = String(localized: "me.stats.title")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        customizeButton.setTitle(String(localized: "me.stats.customize"), for: .normal)
        customizeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        customizeButton.addTarget(self, action: #selector(customizeTapped), for: .touchUpInside)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, UIView(), customizeButton])
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        gridStackView.axis = .vertical
        gridStackView.spacing = 14
        gridStackView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.text = String(localized: "me.stats.login_required")
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(headerStack)
        cardView.addSubview(gridStackView)
        cardView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            headerStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            headerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            gridStackView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            gridStackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            gridStackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
            gridStackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),

            emptyLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 18),
            emptyLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            emptyLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),
        ])
    }

    func configure(items: [MeStatItem], isLoggedIn: Bool) {
        gridStackView.arrangedSubviews.forEach { view in
            gridStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        customizeButton.isHidden = !isLoggedIn
        emptyLabel.isHidden = isLoggedIn
        gridStackView.isHidden = !isLoggedIn
        guard isLoggedIn else { return }

        let rows = stride(from: 0, to: items.count, by: 4).map {
            Array(items[$0..<min($0 + 4, items.count)])
        }
        for rowItems in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.distribution = .fillEqually
            rowStack.spacing = 8
            rowItems.forEach { rowStack.addArrangedSubview(MeStatView(item: $0)) }
            if rowItems.count < 4 {
                for _ in rowItems.count..<4 {
                    rowStack.addArrangedSubview(UIView())
                }
            }
            gridStackView.addArrangedSubview(rowStack)
        }
    }

    @objc private func customizeTapped() {
        onCustomizeTapped?()
    }
}

private final class MeStatView: UIView {
    init(item: MeStatItem) {
        super.init(frame: .zero)
        setup(item: item)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(item: MeStatItem) {
        let iconView = UIImageView(image: UIImage(systemName: item.type.symbolName))
        iconView.tintColor = item.type.tintColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = item.type.tintColor.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 12
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.addSubview(iconView)

        let valueLabel = UILabel()
        valueLabel.text = item.valueText
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.75

        let titleLabel = UILabel()
        titleLabel.text = item.type.title
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.75

        let stack = UIStackView(arrangedSubviews: [iconContainer, valueLabel, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalToConstant: 34),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
}

private final class MeActionCardView: UIView {
    private let cardView = MeCardSurfaceView()
    private let titleLabel = UILabel()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(stackView)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: topAnchor),
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -6),
        ])
    }

    func configure(title: String, rows: [MeActionRow]) {
        titleLabel.text = title
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (index, row) in rows.enumerated() {
            let rowView = MeActionRowView(row: row, showsDivider: index < rows.count - 1)
            stackView.addArrangedSubview(rowView)
        }
    }
}

private final class MeActionRowView: UIControl {
    private let action: () -> Void

    init(row: MeActionRow, showsDivider: Bool) {
        self.action = row.action
        super.init(frame: .zero)
        setup(row: row, showsDivider: showsDivider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(row: MeActionRow, showsDivider: Bool) {
        isEnabled = row.isEnabled
        alpha = row.isEnabled ? 1 : 0.48
        addTarget(self, action: #selector(tapped), for: .touchUpInside)

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = row.tintColor.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 11
        iconContainer.layer.cornerCurve = .continuous

        let iconView = UIImageView(image: UIImage(systemName: row.symbolName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = row.tintColor
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = row.title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label

        let subtitleLabel = UILabel()
        subtitleLabel.text = row.subtitle
        subtitleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel

        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
        divider.isHidden = !showsDivider

        addSubview(iconContainer)
        addSubview(textStack)
        addSubview(chevron)
        addSubview(divider)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 62),

            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 38),
            iconContainer.heightAnchor.constraint(equalToConstant: 38),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 19),
            iconView.heightAnchor.constraint(equalToConstant: 19),

            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 14),
            textStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -12),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 10),

            divider.leadingAnchor.constraint(equalTo: textStack.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    @objc private func tapped() {
        action()
    }
}

private class MeCardSurfaceView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.withAlphaComponent(0.22).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
