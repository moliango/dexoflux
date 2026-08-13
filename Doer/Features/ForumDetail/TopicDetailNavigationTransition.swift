import UIKit

enum TopicDetailTransitionGeometry {
    static let pushInitialTransform = CGAffineTransform.identity

    static func normalize(_ view: UIView) {
        view.layer.removeAllAnimations()
        view.alpha = 1
        view.transform = .identity
    }
}

final class TopicDetailNavigationAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let operation: UINavigationController.Operation
    private let detailOffset: CGFloat = 34
    private let listParallaxOffset: CGFloat = 12
    private var runningAnimator: UIViewPropertyAnimator?

    init(operation: UINavigationController.Operation) {
        self.operation = operation
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        DoerMotion.emphasized
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let animator = interruptibleAnimator(using: transitionContext)
        animator.startAnimation()
    }

    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        if let runningAnimator {
            return runningAnimator
        }

        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to)
        else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return DoerMotion.propertyAnimator(duration: 0)
        }

        let animator: UIViewPropertyAnimator
        switch operation {
        case .push:
            animator = makePushAnimator(fromView: fromView, toView: toView, context: transitionContext)
        case .pop:
            animator = makePopAnimator(fromView: fromView, toView: toView, context: transitionContext)
        default:
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            animator = DoerMotion.propertyAnimator(duration: 0)
        }

        runningAnimator = animator
        return animator
    }

    func animationEnded(_ transitionCompleted: Bool) {
        runningAnimator = nil
    }

    private func makePushAnimator(
        fromView: UIView,
        toView: UIView,
        context: UIViewControllerContextTransitioning
    ) -> UIViewPropertyAnimator {
        let container = context.containerView
        guard let toViewController = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            return DoerMotion.propertyAnimator(duration: 0)
        }
        TopicDetailTransitionGeometry.normalize(fromView)
        TopicDetailTransitionGeometry.normalize(toView)
        container.backgroundColor = AppSettings.shared.themeStyle.topicListBackgroundColor
        toView.frame = context.finalFrame(for: toViewController)
        toView.alpha = 0.97
        toView.transform = TopicDetailTransitionGeometry.pushInitialTransform
        container.addSubview(toView)

        let animator = DoerMotion.propertyAnimator(
            duration: transitionDuration(using: context),
            timingParameters: DoerMotion.softSpring
        )
        animator.addAnimations {
            fromView.alpha = 0.98
            fromView.transform = CGAffineTransform(translationX: -self.listParallaxOffset, y: 0)
                .scaledBy(x: 0.992, y: 0.992)
            toView.alpha = 1
            toView.transform = .identity
        }
        animator.addCompletion { [weak self] position in
            let completed = position == .end && !context.transitionWasCancelled
            TopicDetailTransitionGeometry.normalize(fromView)
            TopicDetailTransitionGeometry.normalize(toView)
            if !completed {
                toView.removeFromSuperview()
            }
            context.completeTransition(completed)
            self?.runningAnimator = nil
        }
        return animator
    }

    private func makePopAnimator(
        fromView: UIView,
        toView: UIView,
        context: UIViewControllerContextTransitioning
    ) -> UIViewPropertyAnimator {
        let container = context.containerView
        guard let toViewController = context.viewController(forKey: .to) else {
            context.completeTransition(false)
            return DoerMotion.propertyAnimator(duration: 0)
        }
        TopicDetailTransitionGeometry.normalize(fromView)
        TopicDetailTransitionGeometry.normalize(toView)
        toView.frame = context.finalFrame(for: toViewController)
        toView.alpha = 0.98
        toView.transform = CGAffineTransform(translationX: -listParallaxOffset, y: 0)
        container.insertSubview(toView, belowSubview: fromView)

        let animator = DoerMotion.propertyAnimator(
            duration: transitionDuration(using: context),
            timingParameters: DoerMotion.softSpring
        )
        animator.addAnimations {
            fromView.alpha = 0.96
            fromView.transform = CGAffineTransform(translationX: self.detailOffset, y: 0)
                .scaledBy(x: 0.992, y: 0.992)
            toView.alpha = 1
            toView.transform = .identity
        }
        animator.addCompletion { [weak self] position in
            let completed = position == .end && !context.transitionWasCancelled
            TopicDetailTransitionGeometry.normalize(fromView)
            TopicDetailTransitionGeometry.normalize(toView)
            context.completeTransition(completed)
            self?.runningAnimator = nil
        }
        return animator
    }
}
