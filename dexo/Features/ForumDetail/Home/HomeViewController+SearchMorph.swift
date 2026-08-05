import Combine
import Network
import UIKit

// MARK: - SearchMorph
extension HomeViewController {
    func setSearchRowCollapsed(_ collapsed: Bool, animated: Bool) {
        guard isSearchRowCollapsed != collapsed else {
            if searchRowMorphAnimator == nil, searchChromeNeedsHeal() {
                applySearchRowChromeFinalState()
            }
            return
        }
        isSearchRowCollapsed = collapsed
        updateHeaderHeight(animated: animated)
    }

    /// True when visual chrome drifted from `isSearchRowCollapsed`.
    func searchChromeNeedsHeal() -> Bool {
        let collapsed = isSearchRowCollapsed
        let targetSearchHeight = collapsed ? 0 : Self.searchRowExpandedHeight
        let targetHeaderHeight = collapsed ? collapsedHeaderHeight : expandedHeaderHeight
        let targetBarAlpha: CGFloat = collapsed ? 0 : 1
        let targetIconAlpha: CGFloat = collapsed ? 1 : 0
        if abs((searchRowHeightConstraint?.constant ?? -1) - targetSearchHeight) > 0.5 { return true }
        if abs((headerHeightConstraint?.constant ?? -1) - targetHeaderHeight) > 0.5 { return true }
        if abs(searchRowStackView.alpha - targetBarAlpha) > 0.05 { return true }
        if abs(compactSearchButton.alpha - targetIconAlpha) > 0.05 { return true }
        if collapsed, compactSearchButton.isHidden { return true }
        if collapsed, compactSearchButton.alpha < 0.95 { return true }
        if !collapsed, searchRowStackView.isHidden { return true }
        if !collapsed, !compactSearchButton.isHidden, compactSearchButton.alpha > 0.05 { return true }
        if searchRowStackView.transform != .identity { return true }
        if compactSearchButton.transform != .identity { return true }
        return false
    }

    /// Prepare compact search icon so UIStackView allocates space *before* alpha animates in.
    /// (Setting isHidden=false and animating alpha in one step often leaves the icon invisible.)
    private func prepareCompactSearchIconForCollapse() {
        compactSearchButton.transform = .identity
        compactSearchButton.isHidden = false
        compactSearchButton.isUserInteractionEnabled = true
        // Start transparent; animator fades in. Force stack to include the 36pt slot now.
        if compactSearchButton.alpha < 0.01 {
            compactSearchButton.alpha = 0.01
        }
        trailingChromeStack.setNeedsLayout()
        headerContainer.setNeedsLayout()
        trailingChromeStack.layoutIfNeeded()
    }

    /// FluxDo-style morph: full search bar height/alpha ↔ compact icon in trailing chrome.
    func updateHeaderHeight(animated: Bool) {
        let collapsed = isSearchRowCollapsed
        let targetSearchHeight = collapsed ? 0 : Self.searchRowExpandedHeight
        let targetHeaderHeight = collapsed ? collapsedHeaderHeight : expandedHeaderHeight
        let targetBarAlpha: CGFloat = collapsed ? 0 : 1
        let targetIconAlpha: CGFloat = collapsed ? 1 : 0

        searchRowMorphGeneration += 1
        let generation = searchRowMorphGeneration
        if let running = searchRowMorphAnimator {
            running.stopAnimation(true)
            searchRowMorphAnimator = nil
        }

        searchRowStackView.transform = .identity
        compactSearchButton.transform = .identity

        if collapsed {
            // Unhide + lay out icon slot before fading in.
            searchRowStackView.isHidden = false // keep until height hits 0 (clips)
            prepareCompactSearchIconForCollapse()
        } else {
            searchRowStackView.isHidden = false
            searchButton.isHidden = false
            searchButton.alpha = 1
            // Keep icon in hierarchy during expand fade-out; hide at end.
            compactSearchButton.isHidden = false
            compactSearchButton.isUserInteractionEnabled = false
        }

        let updates = {
            self.searchRowHeightConstraint?.constant = targetSearchHeight
            self.headerHeightConstraint?.constant = targetHeaderHeight
            self.searchRowStackView.alpha = targetBarAlpha
            self.compactSearchButton.alpha = targetIconAlpha
            self.view.layoutIfNeeded()
            self.updateTableInsets()
        }

        let finish: (UIViewAnimatingPosition) -> Void = { [weak self] position in
            guard let self else { return }
            guard generation == self.searchRowMorphGeneration else { return }
            // Accept .end and .current so interrupted springs still land cleanly.
            guard position == .end || position == .current else { return }
            self.searchRowMorphAnimator = nil
            self.applySearchRowChromeFinalState()
        }

        if animated, !UIAccessibility.isReduceMotionEnabled {
            let animator = DexoMotion.propertyAnimator(
                duration: DexoMotion.emphasized,
                timingParameters: DexoMotion.softSpring
            )
            animator.addAnimations(updates)
            animator.addCompletion(finish)
            searchRowMorphAnimator = animator
            animator.startAnimation()
        } else {
            updates()
            finish(.end)
        }
    }

    /// Idempotent end-state (safe after races / layout).
    func applySearchRowChromeFinalState() {
        let collapsed = isSearchRowCollapsed
        searchRowHeightConstraint?.constant = collapsed ? 0 : Self.searchRowExpandedHeight
        headerHeightConstraint?.constant = collapsed ? collapsedHeaderHeight : expandedHeaderHeight

        searchRowStackView.transform = .identity
        compactSearchButton.transform = .identity

        if collapsed {
            searchRowStackView.alpha = 0
            searchRowStackView.isUserInteractionEnabled = false
            searchRowStackView.isHidden = true
            searchButton.isUserInteractionEnabled = false

            compactSearchButton.isHidden = false
            compactSearchButton.alpha = 1
            compactSearchButton.isUserInteractionEnabled = true
            trailingChromeStack.setNeedsLayout()
            trailingChromeStack.layoutIfNeeded()
        } else {
            searchRowStackView.isHidden = false
            searchRowStackView.alpha = 1
            searchRowStackView.isUserInteractionEnabled = true
            searchButton.isHidden = false
            searchButton.alpha = 1
            searchButton.isUserInteractionEnabled = true

            compactSearchButton.alpha = 0
            compactSearchButton.isUserInteractionEnabled = false
            compactSearchButton.isHidden = true
        }

        view.layoutIfNeeded()
        updateTableInsets()
    }

    func updateCompactSearchChrome(animated: Bool) {
        searchRowMorphGeneration += 1
        if let running = searchRowMorphAnimator {
            running.stopAnimation(true)
            searchRowMorphAnimator = nil
        }
        applySearchRowChromeFinalState()
    }

    /// Layout-pass reassert. Never restarts an in-flight morph.
    func reassertHeaderHeightIfNeeded() {
        guard searchRowMorphAnimator == nil else { return }
        let target = isSearchRowCollapsed ? collapsedHeaderHeight : expandedHeaderHeight
        if abs((headerHeightConstraint?.constant ?? -1) - target) > 0.5 {
            headerHeightConstraint?.constant = target
        }
        let targetSearch = isSearchRowCollapsed ? 0 : Self.searchRowExpandedHeight
        if abs((searchRowHeightConstraint?.constant ?? -1) - targetSearch) > 0.5 {
            searchRowHeightConstraint?.constant = targetSearch
        }
        if searchChromeNeedsHeal() {
            applySearchRowChromeFinalState()
        }
    }
}
