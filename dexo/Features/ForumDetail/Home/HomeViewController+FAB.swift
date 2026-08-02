import Combine
import Network
import UIKit

// MARK: - FAB
extension HomeViewController {
    func setFABMode(_ mode: HomeFABMode, animated: Bool) {
        if mode != .create {
            setCreateMenuVisible(false, animated: animated)
        }
        guard fabMode != mode else { return }
        fabMode = mode
        updateFloatingActionButton(animated: animated)
    }

    func setCreateMenuVisible(_ visible: Bool, animated: Bool) {
        let shouldShow = visible && fabMode == .create && !floatingActionButton.isHidden
        guard isCreateMenuVisible != shouldShow else { return }
        isCreateMenuVisible = shouldShow
        createMenuDismissTapGesture.isEnabled = shouldShow

        if shouldShow {
            createMenuBackdrop.isHidden = false
            createMenuContainer.isHidden = false
            createMenuBackdrop.alpha = 0
            createMenuContainer.alpha = 0
            createMenuContainer.transform = CGAffineTransform(translationX: 0, y: 12)
                .scaledBy(x: 0.94, y: 0.94)
            view.bringSubviewToFront(createMenuBackdrop)
            view.bringSubviewToFront(createMenuContainer)
            view.bringSubviewToFront(floatingActionButton)
        }

        updateFloatingActionButton(animated: animated)
        let updates = {
            self.createMenuBackdrop.alpha = shouldShow ? 1 : 0
            self.createMenuContainer.alpha = shouldShow ? 1 : 0
            self.createMenuContainer.transform = shouldShow ? .identity : CGAffineTransform(translationX: 0, y: 8)
                .scaledBy(x: 0.96, y: 0.96)
        }
        let completion = {
            guard !self.isCreateMenuVisible else { return }
            self.createMenuBackdrop.isHidden = true
            self.createMenuContainer.isHidden = true
        }

        if animated && !UIAccessibility.isReduceMotionEnabled {
            DexoMotion.animate(
                duration: DexoMotion.quick,
                timingParameters: shouldShow ? DexoMotion.easeOutCubic : DexoMotion.easeInCubic,
                animations: updates
            ) { _ in completion() }
        } else {
            updates()
            completion()
        }
    }

    func configureCreateMenuButton(_ button: UIButton, accentColor: UIColor) {
        guard var configuration = button.configuration else { return }
        configuration.baseForegroundColor = accentColor
        configuration.baseBackgroundColor = accentColor.withAlphaComponent(0.10)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 15, weight: .semibold)
            attributes.foregroundColor = .label
            return attributes
        }
        configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 11.5, weight: .regular)
            attributes.foregroundColor = .secondaryLabel
            return attributes
        }
        button.configuration = configuration
    }

    func updateFloatingActionButton(animated: Bool) {
        let symbolName: String
        let accessibilityLabel: String
        switch (fabMode, isCreateMenuVisible) {
        case (.create, true):
            symbolName = "xmark"
            accessibilityLabel = String(localized: "common.close", defaultValue: "关闭")
        case (.create, false):
            symbolName = "plus"
            accessibilityLabel = String(localized: "new_topic.title")
        case (.refresh, _):
            symbolName = "arrow.clockwise"
            accessibilityLabel = String(localized: "action.refresh")
        }
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        let image = UIImage(systemName: symbolName, withConfiguration: config)
        let updates = {
            self.floatingActionButton.setImage(image, for: .normal)
            self.floatingActionButton.accessibilityLabel = accessibilityLabel
            self.floatingActionButton.transform = self.fabMode == .refresh && !self.isCreateMenuVisible
                ? CGAffineTransform(rotationAngle: .pi / 8)
                : .identity
        }
        if animated {
            UIView.transition(
                with: floatingActionButton,
                duration: DexoMotion.quick,
                options: [.transitionCrossDissolve, .beginFromCurrentState],
                animations: updates
            )
        } else {
            updates()
        }
    }

    /// 是否接近列表底部（即将/正在分页）。这个区间 contentSize 最容易跳。
    var isNearTopicListBottomForPagination: Bool {
        let contentHeight = tableView.contentSize.height
        guard contentHeight > tableView.bounds.height else { return false }
        let visibleBottom = tableView.contentOffset.y
            + tableView.bounds.height
            - tableView.adjustedContentInset.bottom
        // 大约最后几屏高度，覆盖 willDisplay 提前 5 行触发的窗口。
        return (contentHeight - visibleBottom) < max(tableView.bounds.height * 1.2, 480)
    }

    /// 刷新 / 加载下一页 / 触底滚动 / settle 窗口：不要用 deltaY 改 tab bar。
    var shouldFreezeTabBarScrollControl: Bool {
        if isTopRefreshGeometryLocked
            || refreshControl.isRefreshing
            || isTabBarScrollFrozenForRefresh
            || viewModel.isLoadingMore
            || isTabBarScrollFrozenForLoadMore {
            return true
        }
        // 上滑接近底部时提前冻结：loadMore 真正开始前 footer/contentSize 已可能变化。
        // 没更多页就别冻，否则触底附近会把「下滑显示」也堵死。
        if AppSettings.shared.bottomBarAutoHideEnabled,
           viewModel.canLoadMore,
           isNearTopicListBottomForPagination,
           (tableView.isDragging || tableView.isDecelerating) {
            return true
        }
        return false
    }
}
