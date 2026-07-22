import CookedHTML
import UIKit

/// A UITextView subclass that preserves link tap interaction and system text selection/copy.
/// Also handles tap-to-reveal for inline spoiler text ranges (`<span class="spoiler">`).
final class LinkTextView: UITextView {
    var preferredMeasurementWidth: CGFloat = 0 {
        didSet {
            guard abs(preferredMeasurementWidth - oldValue) > 0.5 else { return }
            invalidateIntrinsicContentSize()
        }
    }

    private var hasSpoiler = false
    private var spoilerRevealed = false
    private var spoilerRanges: [NSRange] = []
    private var blurOverlays: [UIVisualEffectView] = []
    private var blurAnimators: [UIViewPropertyAnimator] = []
    private var needsBlurLayout = false
    private var lastIntrinsicWidth: CGFloat = 0

    /// Blur intensity for inline spoiler (0 = none, 1 = full).
    private static let blurFraction: CGFloat = 0.7

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        // Prevent underestimated height from painting text into the next block (covers/masks next line).
        clipsToBounds = true
        isScrollEnabled = false
        textContainer.lineFragmentPadding = 0
        textContainerInset = .zero
    }

    override var intrinsicContentSize: CGSize {
        let measurementWidth = bounds.width > 1 ? bounds.width : preferredMeasurementWidth
        guard !isScrollEnabled, measurementWidth > 1 else {
            return super.intrinsicContentSize
        }
        // Ensure layout manager uses the measurement width before first layout pass.
        let usableWidth = max(measurementWidth - textContainerInset.left - textContainerInset.right, 1)
        textContainer.size = CGSize(width: usableWidth, height: .greatestFiniteMagnitude)
        let fittingSize = CGSize(width: measurementWidth, height: .greatestFiniteMagnitude)
        let measured = sizeThatFits(fittingSize)
        // Extra padding avoids first-line clip when UIStackView compresses UITextView height.
        return CGSize(width: UIView.noIntrinsicMetric, height: ceil(measured.height + 4))
    }

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
        if bounds.width > 1 {
            let usableWidth = max(bounds.width - textContainerInset.left - textContainerInset.right, 1)
            if abs(textContainer.size.width - usableWidth) > 0.5 {
                textContainer.size = CGSize(width: usableWidth, height: .greatestFiniteMagnitude)
            }
        }
        if abs(bounds.width - lastIntrinsicWidth) > 0.5 {
            lastIntrinsicWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
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
