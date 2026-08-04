import UIKit

// MARK: - Back Swipe Fallback

extension TopicDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard gestureRecognizer === backSwipeFallbackGesture else { return true }
        // Never steal touches that land on the progress capsule — those belong
        // to swipe/long-press progress gestures configured in Reading settings.
        guard !bottomBar.isHidden else { return true }
        let point = touch.location(in: bottomBar)
        if bottomBar.point(inside: point, with: nil) {
            return false
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === backSwipeFallbackGesture else { return true }
        guard canNavigateBack, presentedViewController == nil else { return false }

        let coordinateView = backSwipeCoordinateView
        let location = backSwipeFallbackGesture.location(in: coordinateView)
        guard location.x <= BackSwipeFallbackMetrics.edgeActivationWidth else { return false }

        // Also bail if the touch is still over the progress bar (hit slop).
        if !bottomBar.isHidden {
            let inBar = bottomBar.point(inside: backSwipeFallbackGesture.location(in: bottomBar), with: nil)
            if inBar { return false }
        }

        let velocity = backSwipeFallbackGesture.velocity(in: coordinateView)
        guard velocity.x >= 0 else { return false }
        if abs(velocity.y) > abs(velocity.x), abs(velocity.y) > 40 {
            return false
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === backSwipeFallbackGesture || otherGestureRecognizer === backSwipeFallbackGesture else {
            return false
        }
        // Progress-bar pan must not share recognition with the back-swipe fallback.
        if otherGestureRecognizer.view is TopicDetailBottomBar
            || gestureRecognizer.view is TopicDetailBottomBar {
            return false
        }
        return otherGestureRecognizer === tableView.panGestureRecognizer
            || gestureRecognizer === tableView.panGestureRecognizer
            || otherGestureRecognizer.view is UIScrollView
            || gestureRecognizer.view is UIScrollView
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // If the progress capsule pan is in play, back-swipe waits for it to fail.
        guard gestureRecognizer === backSwipeFallbackGesture else { return false }
        return otherGestureRecognizer.view is TopicDetailBottomBar
    }
}

