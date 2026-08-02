import Combine
import Network
import UIKit

// MARK: - SearchMorph
extension HomeViewController {
    func setSearchRowCollapsed(_ collapsed: Bool, animated: Bool) {
        guard isSearchRowCollapsed != collapsed else {
            // State matches but a cancelled animator may have left chrome wrong
            // (icon gone while collapsed). Heal without flipping state.
            if searchChromeNeedsHeal() {
                updateHeaderHeight(animated: animated)
            }
            return
        }
        isSearchRowCollapsed = collapsed
        updateHeaderHeight(animated: animated)
    }

    /// True when visual chrome drifted from `isSearchRowCollapsed` (race / interrupt).
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
        if !collapsed, !compactSearchButton.isHidden, compactSearchButton.alpha > 0.05 { return true }
        return false
    }

    /// FluxDo-style continuous morph: full search bar shrinks/fades while the
    /// trailing search icon scales/fades in. Uses a soft spring so fast flicks
    /// don't "teleport" the chrome.
    func updateHeaderHeight(animated: Bool) {
        let collapsed = isSearchRowCollapsed
        let targetSearchHeight = collapsed ? 0 : Self.searchRowExpandedHeight
        let targetHeaderHeight = collapsed ? collapsedHeaderHeight : expandedHeaderHeight
        let targetBarAlpha: CGFloat = collapsed ? 0 : 1
        let targetIconAlpha: CGFloat = collapsed ? 1 : 0
        let targetIconScale: CGFloat = collapsed ? 1 : 0.72

        // Bump generation + stop any in-flight morph. Stale completions must not
        // run `isHidden = true` after a newer collapse has already started.
        searchRowMorphGeneration += 1
        let generation = searchRowMorphGeneration
        if let running = searchRowMorphAnimator {
            running.stopAnimation(true)
            searchRowMorphAnimator = nil
        }

        // Keep the icon in the hierarchy so alpha/transform can animate.
        // Hiding mid-flight causes an instant layout jump (not FluxDo-smooth).
        if collapsed {
            compactSearchButton.isHidden = false
            compactSearchButton.isUserInteractionEnabled = true
            if compactSearchButton.alpha < 0.01 {
                compactSearchButton.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
            }
        } else {
            compactSearchButton.isUserInteractionEnabled = false
        }

        let updates = {
            self.searchRowHeightConstraint?.constant = targetSearchHeight
            self.headerHeightConstraint?.constant = targetHeaderHeight
            self.searchRowStackView.alpha = targetBarAlpha
            // Slight upward drift as the bar collapses — reads as "morphing into" the icon cluster.
            self.searchRowStackView.transform = collapsed
                ? CGAffineTransform(translationX: 0, y: -6).scaledBy(x: 0.96, y: 0.92)
                : .identity
            self.compactSearchButton.alpha = targetIconAlpha
            self.compactSearchButton.transform = CGAffineTransform(scaleX: targetIconScale, y: targetIconScale)
            self.view.layoutIfNeeded()
            self.updateTableInsets()
        }

        /// Always snap final chrome to **current** collapse flag, never the
        /// value captured when this animator was created.
        let finish: (UIViewAnimatingPosition) -> Void = { [weak self] position in
            guard let self else { return }
            guard generation == self.searchRowMorphGeneration else { return }
            guard position == .end else { return }
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

    /// Idempotent end-state for search morph (safe to call after races).
    func applySearchRowChromeFinalState() {
        let collapsed = isSearchRowCollapsed
        searchRowHeightConstraint?.constant = collapsed ? 0 : Self.searchRowExpandedHeight
        headerHeightConstraint?.constant = collapsed ? collapsedHeaderHeight : expandedHeaderHeight
        searchRowStackView.alpha = collapsed ? 0 : 1
        searchRowStackView.transform = .identity
        searchRowStackView.isUserInteractionEnabled = !collapsed
        compactSearchButton.isHidden = !collapsed
        compactSearchButton.alpha = collapsed ? 1 : 0
        compactSearchButton.transform = .identity
        compactSearchButton.isUserInteractionEnabled = collapsed
        view.layoutIfNeeded()
        updateTableInsets()
    }

    /// Sync compact search chrome without a full header re-layout (theme / setup).
    func updateCompactSearchChrome(animated: Bool) {
        // Theme/setup path: cancel morph and snap to the authoritative state.
        searchRowMorphGeneration += 1
        if let running = searchRowMorphAnimator {
            running.stopAnimation(true)
            searchRowMorphAnimator = nil
        }
        let apply = { self.applySearchRowChromeFinalState() }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            DexoMotion.animate(
                duration: DexoMotion.standard,
                timingParameters: DexoMotion.easeInOutCubic,
                animations: apply
            )
        } else {
            apply()
        }
    }
}
