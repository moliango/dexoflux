import Combine
import Network
import UIKit

// MARK: - IncomingTopics
extension HomeViewController {
    func updateCategoryButton() {
        let selected = viewModel.selectedCategory()
        let title = viewModel.categoryDisplayName(for: selected) ?? String(localized: "home.filter.categories")
        applyDropdownStyle(to: categoryButton, title: title, selected: selected != nil)
        categoryButton.sizeToFit()
    }

    func updateFilterButton() {
        filterButton.menu = UIMenu(title: "", children: buildFilterMenuElements())
        applyDropdownStyle(to: filterButton, title: title(for: viewModel.listMode), selected: true)
    }

    func prefetchAvatarImages(for topics: [DiscourseTopicList.Topic]) {
        let prefetchLimit = AppSettings.shared.avatarLoadingProfile.homeAvatarPrefetchLimit
        let urls = topics
            .prefix(prefetchLimit)
            .compactMap { topic in
                AvatarImageLoader.url(
                    from: viewModel.avatarTemplate(for: topic),
                    baseURL: api.baseURL,
                    size: AvatarImageLoader.primaryAvatarPixelSize
                )
            }
        AvatarImageLoader.prefetch(urls: urls, cloudflareBaseURL: api.baseURL)
    }

    /// Prefetch avatars for the visible window + a few rows ahead (FluxDo-style scroll following).
    /// Called from `willDisplay` so deep lists don't only warm the first N topics.
    func prefetchAvatarsAroundVisibleRows(around indexPath: IndexPath) {
        let topics = viewModel.topics
        guard !topics.isEmpty else { return }
        let lookAhead = max(AppSettings.shared.avatarLoadingProfile.homeAvatarPrefetchLimit, 8)
        let start = max(0, indexPath.row - 2)
        let end = min(topics.count, indexPath.row + lookAhead)
        guard start < end else { return }
        let window = Array(topics[start..<end])
        let urls = window.compactMap { topic in
            AvatarImageLoader.url(
                from: viewModel.avatarTemplate(for: topic),
                baseURL: api.baseURL,
                size: AvatarImageLoader.primaryAvatarPixelSize
            )
        }
        guard !urls.isEmpty else { return }
        AvatarImageLoader.prefetch(urls: urls, cloudflareBaseURL: api.baseURL)
    }

    func updateIncomingTopicsHeader() {
        let count = viewModel.incomingTopicIds.count
        guard viewModel.listMode == .latest,
              viewModel.selectedCategoryId == nil,
              count > 0
        else {
            setIncomingTopicsBannerVisible(false, animated: view.window != nil)
            setIncomingTopicsInlineBannerVisible(false)
            updateIncomingTopicsPlacement(animated: false)
            return
        }

        let title = String.localizedStringWithFormat(String(localized: "home.incoming_topics %lld"), Int64(count))
        incomingTopicsButton.configure(title: title, isLoading: viewModel.isLoadingIncomingTopics)
        incomingTopicsInlineButton.configure(title: title, isLoading: viewModel.isLoadingIncomingTopics)
        incomingTopicsButton.isEnabled = !viewModel.isLoadingIncomingTopics
        incomingTopicsInlineButton.isEnabled = !viewModel.isLoadingIncomingTopics
        let usesFloatingBanner = AppSettings.shared.homeIncomingTopicsBannerFloatingEnabled
        setIncomingTopicsBannerVisible(usesFloatingBanner, animated: view.window != nil)
        setIncomingTopicsInlineBannerVisible(!usesFloatingBanner)
        updateIncomingTopicsPlacement(animated: view.window != nil)
    }

    func setIncomingTopicsBannerVisible(_ visible: Bool, animated: Bool) {
        if !visible {
            setIncomingTopicsUsesTopSpace(false)
        }
        guard isIncomingTopicsBannerVisible != visible else {
            if visible {
                incomingTopicsHeaderView.isHidden = false
                incomingTopicsHeaderView.accessibilityElementsHidden = false
                incomingTopicsHeaderView.alpha = 1
                incomingTopicsHeaderView.transform = .identity
            }
            return
        }

        isIncomingTopicsBannerVisible = visible
        incomingTopicsHeaderView.accessibilityElementsHidden = !visible

        let hiddenTransform = CGAffineTransform(translationX: 0, y: -6)
        let updates = {
            self.incomingTopicsHeaderView.alpha = visible ? 1 : 0
            self.incomingTopicsHeaderView.transform = visible ? .identity : hiddenTransform
        }
        let completion: (Bool) -> Void = { _ in
            self.incomingTopicsHeaderView.isHidden = !self.isIncomingTopicsBannerVisible
            if !self.isIncomingTopicsBannerVisible {
                self.incomingTopicsHeaderView.transform = hiddenTransform
            }
        }

        if visible {
            incomingTopicsHeaderView.isHidden = false
            incomingTopicsHeaderView.transform = hiddenTransform
        }

        guard animated else {
            updates()
            completion(true)
            return
        }

        DexoMotion.animate(
            duration: DexoMotion.quick,
            animations: updates
        ) { _ in
            completion(true)
        }
    }

    func updateIncomingTopicsPlacement(animated: Bool) {
        let shouldUseTopSpace = isIncomingTopicsBannerVisible && AppSettings.shared.homeIncomingTopicsBannerFloatingEnabled
        setIncomingTopicsUsesTopSpace(shouldUseTopSpace)
        incomingTopicsButton.setFloating(AppSettings.shared.homeIncomingTopicsBannerFloatingEnabled)
        incomingTopicsInlineButton.setFloating(false)

        guard animated else { return }
        DexoMotion.animate(duration: DexoMotion.quick) {
            self.view.layoutIfNeeded()
        }
    }

    func setIncomingTopicsInlineBannerVisible(_ visible: Bool) {
        guard isIncomingTopicsInlineBannerVisible != visible else {
            updateIncomingTopicsInlineHeaderFrame()
            return
        }
        isIncomingTopicsInlineBannerVisible = visible
        updateIncomingTopicsInlineHeaderFrame()
    }

    func updateIncomingTopicsInlineHeaderFrame() {
        let headerView = isIncomingTopicsInlineBannerVisible ? incomingTopicsInlineHeaderView : emptyTableHeaderView
        let height = isIncomingTopicsInlineBannerVisible ? Self.incomingTopicsBannerHeight : CGFloat.leastNormalMagnitude
        let nextFrame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: height)
        let needsFrameUpdate = headerView.frame.size != nextFrame.size
        if needsFrameUpdate {
            headerView.frame = nextFrame
        }
        if tableView.tableHeaderView !== headerView || needsFrameUpdate {
            tableView.tableHeaderView = headerView
        }
    }

    func setIncomingTopicsUsesTopSpace(_ usesTopSpace: Bool) {
        guard incomingTopicsUsesTopSpace != usesTopSpace else { return }
        incomingTopicsUsesTopSpace = usesTopSpace
        updateTableInsets()
    }

    func updateTableInsets() {
        let incomingTopicsTopSpace = isIncomingTopicsBannerVisible && incomingTopicsUsesTopSpace
            ? Self.incomingTopicsBannerHeight
            : 0
        // Offline strip sits under the header; include its laid-out height.
        let offlineHeight = offlineIndicatorView.isHidden ? 0 : offlineIndicatorView.bounds.height
        let topInset = headerContainer.frame.maxY + offlineHeight + tableTopSpacing + incomingTopicsTopSpace
        let bottomInset = currentBottomChromeHeight + tableBottomSpacing

        var insets = tableView.contentInset
        let oldTopInset = insets.top
        let oldBottomInset = insets.bottom
        guard abs(oldTopInset - topInset) > 0.5 || abs(oldBottomInset - bottomInset) > 0.5 else { return }

        insets.top = topInset
        insets.bottom = bottomInset
        tableView.contentInset = insets
        tableView.verticalScrollIndicatorInsets = insets

        let shouldPreserveVisibleTopContent = !isTopRefreshGeometryLocked

        // Keep the visible content stable for normal header/banner changes. During
        // an intentional top refresh, the final offset is owned by the geometry lock.
        if shouldPreserveVisibleTopContent, oldTopInset > 0, abs(oldTopInset - topInset) > 0.5 {
            tableView.contentOffset.y += oldTopInset - topInset
        }
        if bottomInset < oldBottomInset {
            let minimumOffsetY = -insets.top
            let maximumOffsetY = max(
                minimumOffsetY,
                tableView.contentSize.height + insets.bottom - tableView.bounds.height
            )
            if tableView.contentOffset.y > maximumOffsetY {
                tableView.contentOffset.y = maximumOffsetY
            }
        }
    }

    var currentBottomChromeHeight: CGFloat {
        if let forumTabBarController = tabBarController as? ForumTabBarController {
            return forumTabBarController.visibleTabBarHeight
        }
        guard let tabBar = tabBarController?.tabBar, !tabBar.isHidden else { return 0 }
        return tabBar.frame.height
    }

    var tableTopSpacing: CGFloat {
        usesXiaohongshuCardLayout ? Self.xiaohongshuTableTopSpacing : Self.baseTableTopSpacing
    }

    var tableBottomSpacing: CGFloat {
        usesXiaohongshuCardLayout ? Self.xiaohongshuTableBottomSpacing : Self.baseTableBottomSpacing
    }
}
