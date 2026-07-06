import CookedHTML
import UIKit

enum SpoilerRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        guard case .spoiler(let blocks) = block else { return false }
        return NativeContentRenderer.canRenderNatively(blocks)
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .spoiler(let blocks) = block else { return UIView() }
        return SpoilerBlockView(blocks: blocks, config: config, delegate: delegate)
    }
}

// MARK: - SpoilerOverlayView

/// Reusable blur overlay that wraps any content view with tap-to-reveal spoiler effect.
/// Used by SpoilerBlockView (block-level), TableRenderer (spoiler images in cells),
/// and any other context that needs to blur arbitrary content.
class SpoilerOverlayView: UIView {
    private let blurView: UIVisualEffectView
    private var blurAnimator: UIViewPropertyAnimator?
    private let contentView: UIView
    private var isRevealed = false

    /// How much of the blur to apply (0 = none, 1 = full).
    private let blurFraction: CGFloat

    init(contentView: UIView, cornerRadius: CGFloat = 0, blurFraction: CGFloat = 0.55) {
        self.contentView = contentView
        self.blurFraction = blurFraction
        blurView = UIVisualEffectView(effect: nil)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        layer.cornerRadius = cornerRadius

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.isUserInteractionEnabled = false
        addSubview(blurView)

        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),

            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        contentView.isUserInteractionEnabled = false
        applyPartialBlur()

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleReveal))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cleanUpAnimator()
    }

    private func cleanUpAnimator() {
        guard let animator = blurAnimator else { return }
        animator.stopAnimation(true)
        animator.finishAnimation(at: .current)
        blurAnimator = nil
    }

    private func applyPartialBlur() {
        cleanUpAnimator()
        blurView.effect = nil
        let fraction = blurFraction
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            self.blurView.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        animator.fractionComplete = fraction
        animator.pausesOnCompletion = true
        blurAnimator = animator
    }

    @objc private func toggleReveal() {
        isRevealed.toggle()
        cleanUpAnimator()

        if isRevealed {
            UIView.animate(withDuration: 0.3) {
                self.blurView.effect = nil
            }
            contentView.isUserInteractionEnabled = true
        } else {
            contentView.isUserInteractionEnabled = false
            UIView.animate(withDuration: 0.3) {
                self.blurView.effect = UIBlurEffect(style: .systemThinMaterial)
            } completion: { _ in
                self.blurView.effect = nil
                self.applyPartialBlur()
            }
        }
    }
}

// MARK: - SpoilerBlockView

private class SpoilerBlockView: UIView {
    private let overlay: SpoilerOverlayView

    init(blocks: [ContentBlock], config: NativeRenderConfig, delegate: PostCellDelegate?) {
        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.backgroundColor = .systemBackground
        contentStack.isLayoutMarginsRelativeArrangement = true
        contentStack.layoutMargins = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        let views = NativeContentRenderer.renderBlocks(blocks, config: config, delegate: delegate)
        for view in views {
            contentStack.addArrangedSubview(view)
        }

        overlay = SpoilerOverlayView(contentView: contentStack, cornerRadius: 6)

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
