import CookedHTML
import UIKit

/// A UITextView subclass that preserves link tap interaction and system text selection/copy.
/// Also handles tap-to-reveal for inline spoiler text ranges (`<span class="spoiler">`).
final class LinkTextView: UITextView {
    private var hasSpoiler = false
    private var spoilerRevealed = false
    private var spoilerRanges: [NSRange] = []
    private var blurOverlays: [UIVisualEffectView] = []
    private var blurAnimators: [UIViewPropertyAnimator] = []
    private var needsBlurLayout = false

    /// Blur intensity for inline spoiler (0 = none, 1 = full).
    private static let blurFraction: CGFloat = 0.7

    deinit {
        cleanUpAnimators()
    }

    /// Call after setting attributedText to enable inline spoiler tap handling if needed.
    func configureSpoilerIfNeeded() {
        guard let attrText = attributedText, attrText.length > 0 else { return }
        let full = NSRange(location: 0, length: attrText.length)

        var ranges: [NSRange] = []
        attrText.enumerateAttribute(.cookedHTMLSpoiler, in: full) { value, range, _ in
            if value != nil { ranges.append(range) }
        }

        hasSpoiler = !ranges.isEmpty
        guard hasSpoiler else { return }
        spoilerRanges = ranges
        needsBlurLayout = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if needsBlurLayout, bounds.width > 0 {
            needsBlurLayout = false
            DispatchQueue.main.async { [weak self] in
                self?.createBlurOverlays()
            }
        }
    }

    // MARK: - Blur Overlays

    private func cleanUpAnimators() {
        for animator in blurAnimators {
            animator.stopAnimation(true)
            animator.finishAnimation(at: .current)
        }
        blurAnimators.removeAll()
    }

    private func createBlurOverlays() {
        cleanUpAnimators()
        blurOverlays.forEach { $0.removeFromSuperview() }
        blurOverlays.removeAll()

        for range in spoilerRanges {
            layoutManager.ensureLayout(forCharacterRange: range)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, lineGlyphRange, _ in
                let intersection = NSIntersectionRange(glyphRange, lineGlyphRange)
                guard intersection.length > 0 else { return }

                var rect = self.layoutManager.boundingRect(
                    forGlyphRange: intersection, in: self.textContainer
                )
                rect.origin.x += self.textContainerInset.left
                rect.origin.y += self.textContainerInset.top
                rect = rect.integral
                guard rect.width > 0, rect.height > 0 else { return }

                let overlay = UIVisualEffectView(effect: nil)
                overlay.frame = rect
                overlay.layer.cornerRadius = 3
                overlay.clipsToBounds = true
                overlay.isUserInteractionEnabled = false
                self.addSubview(overlay)
                self.blurOverlays.append(overlay)

                let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
                    overlay.effect = UIBlurEffect(style: .systemThinMaterial)
                }
                animator.fractionComplete = Self.blurFraction
                animator.pausesOnCompletion = true
                self.blurAnimators.append(animator)
            }
        }
    }

    // MARK: - Touch Handling

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if hasSpoiler, let touch = touches.first {
            let point = touch.location(in: self)
            let hitSpoiler = blurOverlays.contains { $0.frame.contains(point) }
            if hitSpoiler {
                toggleSpoiler()
                return
            }
        }
        super.touchesEnded(touches, with: event)
    }

    private func toggleSpoiler() {
        spoilerRevealed.toggle()
        cleanUpAnimators()

        if spoilerRevealed {
            UIView.animate(withDuration: 0.25) {
                self.blurOverlays.forEach { $0.effect = nil }
            }
        } else {
            for overlay in blurOverlays {
                overlay.effect = nil
                let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
                    overlay.effect = UIBlurEffect(style: .systemThinMaterial)
                }
                animator.fractionComplete = Self.blurFraction
                animator.pausesOnCompletion = true
                blurAnimators.append(animator)
            }
        }
    }
}
