import UIKit

// MARK: - UITableViewDelegate

extension TopicDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        if let postId = dataSource.itemIdentifier(for: indexPath),
           let cached = postRowHeightCache[postId],
           cached > 1 {
            return cached
        }
        // Tall first posts (code blocks) need a higher estimate so the table does not
        // park the next floor under unfinished content during the first layout pass.
        if indexPath.row == 0 {
            return 520
        }
        return 220
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        readingTracker.scrolled()
        updateVisibleReadingPosts()
        updateBottomBarProgress()

        guard let header = tableView.tableHeaderView else { return }
        let headerBottom = header.frame.maxY
        let offsetY = scrollView.contentOffset.y + scrollView.safeAreaInsets.top
        let shouldShowCollapsedTitle = offsetY >= headerBottom
        if shouldShowCollapsedTitle != isShowingCollapsedNavigationTitle {
            isShowingCollapsedNavigationTitle = shouldShowCollapsedTitle
            navigationItem.titleView = shouldShowCollapsedTitle ? navTitleLabel : nil
        }

        let currentOffset = scrollView.contentOffset.y
        let isScrollingUp = currentOffset < lastScrollOffset
        lastScrollOffset = currentOffset

        // Clear suppress flag once user scrolls down, meaning they've settled after a jump
        if !isScrollingUp {
            suppressLoadEarlier = false
        }

        // Only trigger load-earlier when user is actively scrolling UP
        // and within 200pt of the top — prevents false triggers after jump
        guard isScrollingUp,
              !suppressLoadEarlier,
              viewModel.canLoadEarlier,
              !isLoadingEarlierLocally
        else { return }
        let contentTop = -(scrollView.adjustedContentInset.top)
        if scrollView.contentOffset.y <= contentTop + 200 {
            // Capture anchor synchronously before any async work
            guard let anchorIndexPath = tableView.indexPathsForVisibleRows?.first,
                  let anchorId = dataSource.itemIdentifier(for: anchorIndexPath)
            else { return }
            let cellTopOffset = tableView.rectForRow(at: anchorIndexPath).minY - tableView.contentOffset.y
            earlierLoadAnchor = (postId: anchorId, cellTopOffset: cellTopOffset)
            isLoadingEarlierLocally = true
            Task {
                let didStart = await viewModel.loadEarlierPosts(containerWidth: view.bounds.width)
                if !didStart {
                    earlierLoadAnchor = nil
                    isLoadingEarlierLocally = false
                }
                // updateUI (triggered by DexoObservableObject) will handle position restoration
            }
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Nudge self-sizing once on screen — skip when we already have a solid measured height
        // so image/Web loads don't re-trigger beginUpdates on every reappearance.
        if let postId = dataSource.itemIdentifier(for: indexPath),
           let cached = postRowHeightCache[postId],
           cached > 1,
           abs(cell.frame.height - cached) < 3 {
            // Height stable; still warm nearby media.
        } else {
            (cell as? PostNativeCell)?.requestHeightReconciliation()
        }

        // Prefetch content images for this row + a few ahead (smoother first paint).
        if let postId = dataSource.itemIdentifier(for: indexPath) {
            var ahead: [Int] = [postId]
            let total = tableView.numberOfRows(inSection: 0)
            for offset in 1...3 {
                let next = indexPath.row + offset
                guard next < total,
                      let id = dataSource.itemIdentifier(for: IndexPath(row: next, section: 0))
                else { break }
                ahead.append(id)
            }
            prefetchContentImages(forPostIds: ahead)
        }

        DispatchQueue.main.async { [weak self] in
            self?.updateVisibleReadingPosts()
        }

        let totalRows = tableView.numberOfRows(inSection: 0)
        // Load more (forward)
        if indexPath.row >= totalRows - 3 {
            Task {
                await viewModel.loadMorePosts(containerWidth: view.bounds.width)
            }
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let postId = dataSource.itemIdentifier(for: indexPath) {
            let height = cell.frame.height
            if height > 1 {
                postRowHeightCache[postId] = height
            }
        }
        // Cancel off-screen fallback Web renders to cut dual-path jank / CPU.
        if let native = cell as? PostNativeCell {
            native.cancelOffscreenMediaWork()
        }
        DispatchQueue.main.async { [weak self] in
            self?.updateVisibleReadingPosts()
        }
    }
}

