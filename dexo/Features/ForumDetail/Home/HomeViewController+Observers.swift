import Combine
import UIKit

// MARK: - Observers
extension HomeViewController {
    func startObservingCloudflareVerification() {
        cloudflareCompletionObservationToken = NotificationCenter.default.addObserver(
            forName: DiscourseAPI.cloudflareVerificationCompletedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCloudflareVerificationCompleted(notification)
        }
    }

    func startObservingAuthChanges() {
        authObservationToken = AuthManager.shared.objectWillChange.sink { [weak self] in
            self?.handleAuthChanged()
        }
    }

    func startObservingSettingsChanges() {
        settingsObservationToken = AppSettings.shared.objectWillChange.sink { [weak self] in
            self?.handleSettingsChanged()
        }
    }

    func startObservingForeground() {
        foregroundObservationToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // FluxDo: resume 时主动 check 连通性（等同 visibilitychange）
                ConnectivityService.shared.check()
                ConnectivityService.shared.pingBaseURL = self.api.baseURL
                self.reassertBottomChromeAfterApplicationActivation()
                self.viewModel.restoreBackgroundTopicUpdates()
                self.updateIncomingTopicsHeader()
                self.reloadAfterBecomingVisibleIfNeeded()
            }
        }
    }

    func startObservingTopicReadProgress() {
        topicReadProgressObservationToken = NotificationCenter.default.addObserver(
            forName: .topicReadProgressDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let baseURL = notification.userInfo?[TopicReadProgressUserInfoKey.baseURL] as? String,
                  baseURL == self.api.baseURL,
                  let topicId = notification.userInfo?[TopicReadProgressUserInfoKey.topicId] as? Int,
                  let highestSeen = notification.userInfo?[TopicReadProgressUserInfoKey.highestSeen] as? Int
            else { return }
            self.viewModel.updateTopicReadProgress(topicId: topicId, highestSeen: highestSeen)
        }
    }

    /// Subscribe to app-wide connectivity (FluxDo ConnectivityService).
    func startMonitoringNetwork() {
        ConnectivityService.shared.pingBaseURL = api.baseURL
        ConnectivityService.shared.start()
        applyConnectivityUI(isConnected: ConnectivityService.shared.isConnected, animated: false)

        if connectivityObservationToken == nil {
            connectivityObservationToken = NotificationCenter.default.addObserver(
                forName: ConnectivityService.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let connected = (notification.userInfo?[ConnectivityService.isConnectedUserInfoKey] as? Bool)
                    ?? ConnectivityService.shared.isConnected
                self?.handleConnectivityChanged(isConnected: connected)
            }
        }
    }

    func handleConnectivityChanged(isConnected: Bool) {
        applyConnectivityUI(isConnected: isConnected, animated: true)
        // 网络从断开恢复：重置会话/DoH 缓存并刷新列表（原 NWPathMonitor 行为）
        if isConnected {
            recoverTransportAndReload()
        }
    }

    func applyConnectivityUI(isConnected: Bool, animated: Bool) {
        offlineIndicatorView.setVisible(!isConnected, animated: animated)
        updateTableInsets()
        view.setNeedsLayout()
    }

    func handleCloudflareVerificationCompleted(_ notification: Notification) {
        guard let baseURL = notification.userInfo?[DiscourseAPI.cloudflareBaseURLUserInfoKey] as? String else { return }
        guard normalizedBaseURL(baseURL) == normalizedBaseURL(api.baseURL) else { return }
        let shouldReloadTopics = shouldReloadTopicsAfterCloudflareVerification()
        logCloudflareState("verification completed base=\(baseURL) reloadTopics=\(shouldReloadTopics)")
        restoreTabBarAfterCloudflareVerification()
        // Image gate resumes via markVerificationGrace; re-allow prefetch + repaint visible avatars.
        let retryURLs = viewModel.topics.prefix(AppSettings.shared.avatarLoadingProfile.homeAvatarPrefetchLimit).compactMap { topic in
            AvatarImageLoader.url(
                from: viewModel.avatarTemplate(for: topic),
                baseURL: api.baseURL,
                size: AvatarImageLoader.primaryAvatarPixelSize
            )
        }
        AvatarImageLoader.credentialsDidChange(for: api.baseURL, retrying: Array(retryURLs))
        prefetchAvatarImages(for: viewModel.topics)
        if let visible = tableView.indexPathsForVisibleRows, !visible.isEmpty {
            var snapshot = dataSource.snapshot()
            let ids = visible.compactMap { dataSource.itemIdentifier(for: $0) }
            if !ids.isEmpty {
                snapshot.reconfigureItems(ids)
                dataSource.apply(snapshot, animatingDifferences: false)
            }
        }
        reloadTopicsAfterCloudflareVerificationIfNeeded(shouldReloadTopics)
        retryLoadMoreAfterCloudflareIfNeeded()
        retryIncomingTopicsAfterCloudflareIfNeeded()
    }

    /// Parent-presented CF sheet skips our appear callbacks; re-assert bottom bar.
    func restoreTabBarAfterCloudflareVerification() {
        guard isViewLoaded else { return }
        // Clear freezes that may have been left mid-challenge so scroll hide works again.
        isTabBarScrollFrozenForRefresh = false
        isTabBarScrollFrozenForLoadMore = false
        tabBarScrollFreezeID += 1
        tabBarLoadMoreFreezeID += 1
        applyCloudflareTabBarReveal()
        // Sheet dismiss + topic list layout can hide/cover the bar one or two
        // runloops later; keep re-asserting briefly so it cannot stay gone.
        DispatchQueue.main.async { [weak self] in
            self?.applyCloudflareTabBarReveal()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.view.window != nil else { return }
            self.applyCloudflareTabBarReveal()
        }
    }

    func applyCloudflareTabBarReveal() {
        guard isViewLoaded else { return }
        isHomeTabBarHidden = true // force setHomeTabBarHidden to re-apply even if flag already false
        setHomeTabBarHidden(false, animated: false)
        lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top
        (tabBarController as? ForumTabBarController)?.forceRevealTabBarForRootContent()
        updateBottomChrome(animated: false)
    }

    func logCloudflareState(_ message: String) {
        DohDebugLog.record("home \(message) sequence=\(reloadSequence)", subsystem: "CF")
    }

    func handleAuthChanged() {
        let isAuthenticated = AuthManager.shared.isAuthenticated(for: api.baseURL)
        guard let previous = lastAuthenticatedState else {
            lastAuthenticatedState = isAuthenticated
            return
        }
        guard previous != isAuthenticated else { return }
        lastAuthenticatedState = isAuthenticated
        reloadTopics(resetCategoryMetadata: true)
    }

    func reloadAfterBecomingVisibleIfNeeded() {
        guard isViewLoaded, view.window != nil, !viewModel.isLoading else { return }
        guard viewModel.topics.isEmpty || viewModel.errorMessage != nil else { return }
        recoverTransportAndReload()
    }

    func recoverTransportAndReload(resetCategoryMetadata: Bool = false) {
        api.resetSession()
        LightweightDohProxyService.shared.clearCache()
        reloadTopics(resetCategoryMetadata: resetCategoryMetadata)
    }

    func normalizedBaseURL(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}
