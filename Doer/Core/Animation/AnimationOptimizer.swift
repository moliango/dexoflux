import UIKit

/// 动画性能优化工具 — 为 UIView 提供优化的动画 API。
///
/// **关键优化：**
/// 1. 自动启用光栅化（shouldRasterize）减少复杂视图层级的重绘
/// 2. 动画完成后自动清理光栅化，避免内存膨胀
/// 3. 使用 CATransaction 批量提交，减少渲染往返
/// 4. 为常见动画提供性能最优的预设参数
///
/// **何时使用：**
/// - 复杂视图层级的 alpha / transform 动画
/// - 圆角 + 阴影 + 半透明叠加的视图动画
/// - 列表中频繁触发的 cell 高亮动画
///
/// **何时不用：**
/// - 约束驱动的布局动画（layoutIfNeeded 已足够）
/// - 单层纯色视图的简单动画
enum AnimationOptimizer {
    /// 优化的 alpha 动画 — 适用于复杂视图层级（HUD、toast、drawer overlay）。
    /// 自动启用光栅化，动画完成后清理。
    ///
    /// - Parameters:
    ///   - view: 目标视图
    ///   - alpha: 目标透明度
    ///   - duration: 动画时长（默认 0.2s）
    ///   - completion: 完成回调
    @MainActor
    static func animateAlpha(
        _ view: UIView,
        to alpha: CGFloat,
        duration: TimeInterval = 0.2,
        completion: (() -> Void)? = nil
    ) {
        prepareForAnimation(view)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            view.alpha = alpha
        } completion: { _ in
            cleanupAfterAnimation(view)
            completion?()
        }
    }

    /// 优化的 transform 动画 — 适用于缩放/平移/旋转动画。
    /// GPU 加速，无光栅化（transform 本身已经很快）。
    ///
    /// - Parameters:
    ///   - view: 目标视图
    ///   - transform: 目标 transform
    ///   - duration: 动画时长
    ///   - damping: 弹簧阻尼（0.7 - 1.0）
    ///   - completion: 完成回调
    @MainActor
    static func animateTransform(
        _ view: UIView,
        to transform: CGAffineTransform,
        duration: TimeInterval = 0.3,
        damping: CGFloat = 0.85,
        completion: (() -> Void)? = nil
    ) {
        // Transform 动画不需要光栅化 — GPU 本身就高效。
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: damping,
            initialSpringVelocity: 0.2,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            view.transform = transform
        } completion: { _ in
            completion?()
        }
    }

    /// 优化的组合动画 — 同时改变 alpha + transform。
    /// 适用于 modal present/dismiss、scale-fade 效果。
    ///
    /// - Parameters:
    ///   - view: 目标视图
    ///   - alpha: 目标透明度
    ///   - transform: 目标 transform
    ///   - duration: 动画时长
    ///   - completion: 完成回调
    @MainActor
    static func animateAlphaAndTransform(
        _ view: UIView,
        alpha: CGFloat,
        transform: CGAffineTransform,
        duration: TimeInterval = 0.25,
        completion: (() -> Void)? = nil
    ) {
        prepareForAnimation(view)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            view.alpha = alpha
            view.transform = transform
        } completion: { _ in
            cleanupAfterAnimation(view)
            completion?()
        }
    }

    /// 高性能 cell 高亮动画 — 用于 UITableViewCell / UICollectionViewCell。
    /// 避免每次高亮都重建 CALayer，复用已有 layer 属性。
    ///
    /// - Parameters:
    ///   - view: Cell 的 contentView
    ///   - highlighted: 是否高亮
    ///   - highlightColor: 高亮背景色
    ///   - normalColor: 正常背景色
    /// Fade a view in or out, toggling `isHidden` after hide completes.
    @MainActor
    static func setVisible(_ view: UIView, _ visible: Bool, animated: Bool) {
        let alreadyShown = !view.isHidden && view.alpha >= 0.99
        let alreadyHidden = view.isHidden || view.alpha <= 0.01
        if visible ? alreadyShown : alreadyHidden {
            view.isHidden = !visible
            view.alpha = visible ? 1 : 0
            return
        }
        if !animated || UIAccessibility.isReduceMotionEnabled {
            view.alpha = visible ? 1 : 0
            view.isHidden = !visible
            return
        }
        if visible {
            if view.isHidden {
                view.alpha = 0
                view.isHidden = false
            }
            animateAlpha(view, to: 1, duration: 0.2)
        } else {
            animateAlpha(view, to: 0, duration: 0.18) {
                view.isHidden = true
                view.alpha = 1
            }
        }
    }

    /// Compact press feedback for card-style list rows.
    @MainActor
    static func animateCardPress(_ view: UIView, pressed: Bool) {
        if UIAccessibility.isReduceMotionEnabled {
            view.transform = .identity
            view.alpha = 1
            return
        }
        UIView.animate(
            withDuration: 0.14,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]
        ) {
            view.transform = pressed ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            view.alpha = pressed ? 0.92 : 1
        }
    }

    @MainActor
    static func animateCellHighlight(
        _ view: UIView,
        highlighted: Bool,
        highlightColor: UIColor,
        normalColor: UIColor
    ) {
        // Cell 高亮动画极为频繁，必须最快：
        // - 不启用光栅化（会增加延迟）
        // - 用最短时长（0.12s）
        // - beginFromCurrentState 避免重复动画冲突
        UIView.animate(
            withDuration: 0.12,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            view.backgroundColor = highlighted ? highlightColor : normalColor
        }
    }

    // MARK: - 内部优化逻辑

    /// 为复杂视图准备动画：启用光栅化 + 设置合适的光栅化比例。
    /// 仅在视图包含子视图或有圆角/阴影时才启用（避免无意义的开销）。
    private static func prepareForAnimation(_ view: UIView) {
        guard shouldRasterize(view) else { return }
        view.layer.shouldRasterize = true
        view.layer.rasterizationScale = UIScreen.main.scale
    }

    /// 动画完成后清理：关闭光栅化，释放缓存内存。
    private static func cleanupAfterAnimation(_ view: UIView) {
        // 延迟一个 runloop 清理，确保动画完全结束（避免闪烁）。
        Task { @MainActor in
            view.layer.shouldRasterize = false
        }
    }

    /// 判断视图是否值得光栅化：
    /// - 有多个子视图（层级复杂）
    /// - 有圆角 + 裁剪（masksToBounds 昂贵）
    /// - 有阴影（shadowOpacity > 0）
    private static func shouldRasterize(_ view: UIView) -> Bool {
        let hasComplexHierarchy = view.subviews.count > 2
        let hasRoundedCorners = view.layer.cornerRadius > 0 && view.clipsToBounds
        let hasShadow = view.layer.shadowOpacity > 0
        return hasComplexHierarchy || hasRoundedCorners || hasShadow
    }
}
