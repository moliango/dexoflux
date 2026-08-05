import CookedHTML
import SafariServices
import UIKit

// MARK: - TopicDetailBottomBarDelegate

extension TopicDetailViewController: TopicDetailBottomBarDelegate {
    func bottomBarDidTapTimeline() {
        showTimelineSheet()
    }

    func bottomBarDidSelectProgressAction(_ action: ProgressGestureAction) {
        performProgressGestureAction(action)
    }

    func performProgressGestureAction(_ action: ProgressGestureAction) {
        switch action {
        case .none:
            break
        case .openTimeline:
            showTimelineSheet()
        case .scrollToTop:
            scrollToTop()
        case .jumpToUnread:
            jumpToUnreadOrFirst()
        case .nextPost:
            jumpRelativeFloor(+1)
        case .previousPost:
            jumpRelativeFloor(-1)
        case .reply:
            replyButtonTapped()
        case .share:
            shareTopicLink(sourceView: bottomBar)
        case .shareImage:
            shareTopicImage()
        case .exportArticle:
            presentExportMenuFromProgressBar()
        case .openInBrowser:
            openTopicInBrowser()
        case .bookmark:
            bookmarkTopic()
        case .readLater:
            TopicReadLaterStore.shared.toggle(
                topicId: topicId,
                baseURL: api.baseURL,
                username: AuthManager.shared.username(for: api.baseURL)
            )
            configureTopicActions()
        case .notification:
            presentNotificationLevelPicker()
        case .filter:
            viewModel.setFilteringByOP(!viewModel.isFilteringByOP)
            configureTopicActions()
        case .toggleNestedView:
            AppSettings.shared.nestedReplyViewEnabled.toggle()
            Task { await viewModel.loadTopic(id: topicId, containerWidth: view.bounds.width) }
        case .aiAssistant:
            aiAssistantTapped()
        case .readingSettings:
            navigationController?.pushViewController(ReadingSettingsViewController(), animated: true)
        case .search:
            showTimelineSheet()
        case .refresh:
            Task { await viewModel.loadTopic(id: topicId, containerWidth: view.bounds.width) }
        case .goBack:
            if canNavigateBack {
                navigationController?.popViewController(animated: true)
            } else {
                dismiss(animated: true)
            }
        }
    }

    func scrollToTop() {
        guard tableView.numberOfRows(inSection: 0) > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
    }

    func jumpRelativeFloor(_ delta: Int) {
        let total = viewModel.totalFloors
        guard total > 0 else { return }
        let target = min(max(currentVisibleFloor() + delta, 1), total)
        jumpToFloor(target)
    }

    func jumpToUnreadOrFirst() {
        let total = viewModel.totalFloors
        guard total > 0 else { return }
        // Real unread: last_read + 1 (from list or detail). Fallback: next floor / top.
        if let unread = resumeUnreadFloor() {
            jumpToFloor(unread)
            return
        }
        let current = currentVisibleFloor()
        if current < total {
            jumpToFloor(current + 1)
        } else {
            jumpToFloor(1)
        }
    }

    /// First unread floor from `lastReadPostNumber`, clamped to total floors.
    func resumeUnreadFloor() -> Int? {
        let total = viewModel.totalFloors
        guard total > 0 else { return nil }
        let lastRead = lastReadPostNumber ?? viewModel.topic?.lastReadPostNumber ?? 0
        guard lastRead > 0, lastRead < total else { return nil }
        return min(lastRead + 1, total)
    }

    func openTopicInBrowser() {
        guard let url = URL(string: "\(baseURL)/t/\(topicId)") else { return }
        let browser = InAppBrowserViewController(
            api: api,
            username: AuthManager.shared.username(for: api.baseURL),
            initialURL: url
        )
        navigationController?.pushViewController(browser, animated: true)
    }

    func presentExportMenuFromProgressBar() {
        let sheet = UIAlertController(
            title: String(localized: "topic.export", defaultValue: "导出话题"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for range in TopicExportRange.allCases {
            sheet.addAction(UIAlertAction(title: range.title, style: .default) { [weak self] _ in
                self?.exportTopic(format: .markdown, range: range)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = bottomBar
        sheet.popoverPresentationController?.sourceRect = bottomBar.bounds
        present(sheet, animated: true)
    }

    func presentNotificationLevelPicker() {
        let sheet = UIAlertController(
            title: String(localized: "topic.notifications", defaultValue: "通知级别"),
            message: nil,
            preferredStyle: .actionSheet
        )
        for level in DiscourseTopicDetail.NotificationLevel.allCases.reversed() {
            sheet.addAction(UIAlertAction(title: title(for: level), style: .default) { [weak self] _ in
                self?.setNotificationLevel(level)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = bottomBar
        sheet.popoverPresentationController?.sourceRect = bottomBar.bounds
        present(sheet, animated: true)
    }

    func showTimelineSheet() {
        let stream = viewModel.allPostIds
        guard !stream.isEmpty else { return }

        let timeline = TopicTimelineSheetViewController(
            currentIndex: currentVisibleFloor(),
            stream: stream,
            title: TitleEmojiRenderer.plainTitle(fancyTitle: viewModel.topic?.fancyTitle, title: viewModel.topic?.title ?? "")
        )
        timeline.onJumpToPostId = { [weak self] postId in
            self?.jumpToPostId(postId)
        }
        timeline.onDismiss = { [weak self] in
            self?.syncOwningTabBarVisibility()
        }
        timeline.modalPresentationStyle = .pageSheet
        timeline.isModalInPresentation = true
        if let sheet = timeline.sheetPresentationController {
            // Fit the compact timeline content; avoid a tall empty band under buttons.
            if #available(iOS 16.0, *) {
                let timelineDetent = UISheetPresentationController.Detent.custom(
                    identifier: .init("topic.timeline")
                ) { context in
                    // preferred content + home-indicator reserve.
                    let fitted = TopicTimelineSheetViewController.preferredSheetHeight + 34
                    return min(fitted, context.maximumDetentValue)
                }
                sheet.detents = [timelineDetent]
                sheet.selectedDetentIdentifier = timelineDetent.identifier
            } else {
                sheet.detents = [.medium()]
            }
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(timeline, animated: true)
    }

    func showFloorJumpPrompt() {
        let total = viewModel.totalFloors
        guard total > 0 else { return }

        let alert = UIAlertController(
            title: String(localized: "topic_detail.bar.jump_to_floor"),
            message: String(localized: "topic_detail.jump.message \(total)"),
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "1-\(total)"
            textField.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: String(localized: "action.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "topic_detail.jump.confirm"), style: .default) { [weak self] _ in
            guard let self,
                  let text = alert.textFields?.first?.text,
                  let floor = Int(text),
                  floor >= 1, floor <= total
            else { return }

            self.jumpToFloor(floor)
        })
        present(alert, animated: true)
    }

    func jumpToPostId(_ postId: Int) {
        if scrollToPostIdIfVisible(postId, animated: true) {
            return
        }
        guard let targetIndex = viewModel.allPostIds.firstIndex(of: postId) else { return }
        jumpToFloor(targetIndex + 1)
    }

    /// Jump using Discourse `post_number` (as in `/t/:id/:post_number` and notifications).
    /// Resolves to stream position so deleted-post gaps do not land on the wrong reply.
    func jumpToPostNumber(_ postNumber: Int) async {
        guard postNumber > 0 else { return }

        if let post = viewModel.posts.first(where: { $0.postNumber == postNumber }) {
            jumpToPostId(post.id)
            return
        }

        do {
            let post = try await api.fetchPostByNumber(topicId: topicId, postNumber: postNumber)
            if viewModel.allPostIds.contains(post.id) {
                jumpToPostId(post.id)
                return
            }
        } catch {
            #if DEBUG
            print("[TopicDetail] resolve post_number=\(postNumber) failed: \(error)")
            #endif
        }

        // Last resort: historical behavior treated post_number ≈ stream floor.
        jumpToFloor(postNumber)
    }

    /// Stream floor is 1-based index into `allPostIds` (not Discourse `post_number`).
    func jumpToFloor(_ floor: Int) {
        let total = viewModel.totalFloors
        guard floor >= 1, floor <= total else { return }

        let postId = viewModel.allPostIds[floor - 1]
        if scrollToPostIdIfVisible(postId, animated: true) {
            return
        }

        // Loaded posts may still be parsing — only the Diffable snapshot is safe to scroll.
        // Defer until the target id appears in the table rather than using visiblePosts indices
        // (those can exceed table row count when some cells lack parsed blocks).
        if viewModel.isFloorLoaded(floor) {
            pendingScrollToFloor = floor
            view.setNeedsLayout()
            return
        }

        // Scroll is finalized in viewDidLayoutSubviews after the target batch has cells.
        showJumpOverlay()
        hasTitleHeader = false
        suppressLoadEarlier = true
        Task {
            await viewModel.jumpToFloor(floor, containerWidth: view.bounds.width)
            hideJumpOverlay()
        }
    }

    /// Scroll using Diffable item identity + live table row count.
    /// Never trust `visiblePosts` indices — the snapshot only lists parsed-ready posts
    /// (and may reorder under nested-reply mode), so raw indices can be out of bounds.
    @discardableResult
    func scrollToPostIdIfVisible(_ postId: Int, animated: Bool) -> Bool {
        // scrollToRow during Diffable apply / self-sizing beginUpdates desyncs
        // _visibleRows vs _visibleCells.
        guard !isApplyingPostSnapshot, !tableView.dexo_isMutatingData else { return false }
        guard tableView.numberOfSections > 0,
              let indexPath = dataSource.indexPath(for: postId)
        else { return false }
        let rowCount = tableView.numberOfRows(inSection: indexPath.section)
        guard rowCount > 0, indexPath.row >= 0, indexPath.row < rowCount else { return false }
        tableView.scrollToRow(at: indexPath, at: .top, animated: animated)
        return true
    }

    func showJumpOverlay() {
        if jumpOverlay.superview == nil {
            view.addSubview(jumpOverlay)
            NSLayoutConstraint.activate([
                jumpOverlay.topAnchor.constraint(equalTo: tableView.topAnchor),
                jumpOverlay.leadingAnchor.constraint(equalTo: tableView.leadingAnchor),
                jumpOverlay.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
                jumpOverlay.bottomAnchor.constraint(equalTo: tableView.bottomAnchor),
            ])
        }
        jumpOverlay.isHidden = false
        // Keep progress capsule interactive above the jump dimming layer.
        view.bringSubviewToFront(floatingReplyButton)
        view.bringSubviewToFront(bottomBar)
    }

    func hideJumpOverlay() {
        jumpOverlay.isHidden = true
    }

    var canNavigateBack: Bool {
        guard let navigationController else { return false }
        return navigationController.viewControllers.count > 1
            && navigationController.viewControllers.first !== self
    }

    func installBackSwipeFallbackGesture() {
        guard let hostView = navigationController?.view else { return }
        if backSwipeFallbackHostView !== hostView {
            backSwipeFallbackGesture.view?.removeGestureRecognizer(backSwipeFallbackGesture)
            hostView.addGestureRecognizer(backSwipeFallbackGesture)
            backSwipeFallbackHostView = hostView
        }
        backSwipeFallbackGesture.isEnabled = canNavigateBack
    }

    func uninstallBackSwipeFallbackGesture() {
        backSwipeFallbackGesture.view?.removeGestureRecognizer(backSwipeFallbackGesture)
        backSwipeFallbackHostView = nil
        backSwipeFallbackGesture.isEnabled = false
    }

    var backSwipeCoordinateView: UIView {
        backSwipeFallbackGesture.view ?? view
    }

    func shouldCompleteBackSwipe(translation: CGPoint, velocity: CGPoint) -> Bool {
        guard translation.x > 0 else { return false }
        return translation.x > BackSwipeFallbackMetrics.minimumCompletionTranslation
            || velocity.x > BackSwipeFallbackMetrics.minimumCompletionVelocity
    }

    @objc func handleBackSwipeFallback(_ gesture: UIPanGestureRecognizer) {
        guard canNavigateBack, presentedViewController == nil else { return }

        switch gesture.state {
        case .began:
            isHandlingBackSwipeFallback = false
        case .ended:
            let coordinateView = backSwipeCoordinateView
            let translation = gesture.translation(in: coordinateView)
            let velocity = gesture.velocity(in: coordinateView)
            guard shouldCompleteBackSwipe(translation: translation, velocity: velocity),
                  !isHandlingBackSwipeFallback
            else { return }
            isHandlingBackSwipeFallback = true
            navigationController?.popViewController(animated: true)
        case .cancelled, .failed:
            isHandlingBackSwipeFallback = false
        default:
            break
        }
    }

}

