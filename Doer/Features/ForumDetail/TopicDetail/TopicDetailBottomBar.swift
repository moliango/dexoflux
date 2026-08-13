import UIKit

protocol TopicDetailBottomBarDelegate: AnyObject {
    func bottomBarDidTapTimeline()
    func bottomBarDidSelectProgressAction(_ action: ProgressGestureAction)
}

/// Floating topic progress capsule with FluxDO-style gestures:
/// - tap → timeline
/// - swipe L/R/Up → configurable actions (settings)
/// - long-press → radial menu of configurable actions
///
/// Implemented as `UIView` (not `UIControl`) so UIControl touch-tracking cannot
/// starve pan / long-press recognizers on this small hit target.
final class TopicDetailBottomBar: UIView {
    weak var delegate: TopicDetailBottomBarDelegate?

    private enum Metrics {
        static let height: CGFloat = 40
        static let width: CGFloat = 120
        /// Distance from pan start before the bound action fires.
        static let swipeTriggerDistance: CGFloat = 40
        /// Ignore jitter below this when deciding swipe direction.
        static let swipeDeadZone: CGFloat = 8
        /// Expanded hit slop around the 120×40 capsule.
        static let hitSlop: CGFloat = 20
    }

    private enum SwipeDirection {
        case left, right, up
    }

    private let surfaceView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        return view
    }()

    private let progressFillView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.tintColor.withAlphaComponent(0.12)
        view.isUserInteractionEnabled = false
        return view
    }()

    private let currentLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .tintColor
        label.textAlignment = .center
        return label
    }()

    private let slashLabel: UILabel = {
        let label = UILabel()
        label.text = "/"
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        return label
    }()

    private let totalLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private lazy var labelStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [currentLabel, slashLabel, totalLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalCentering
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        return stack
    }()

    private let pressProgressLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = UIColor.clear.cgColor
        layer.strokeColor = UIColor.tintColor.cgColor
        layer.lineWidth = 2.5
        layer.lineCap = .round
        layer.strokeEnd = 0
        return layer
    }()

    private var radialOverlay: TopicDetailRadialMenuOverlay?
    private var highlightedAction: ProgressGestureAction?
    private var isPresentingRadialMenu = false
    private var progressFraction: CGFloat = 0
    private var progressFillWidthConstraint: NSLayoutConstraint?
    private let feedback = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    // Swipe preview
    private var swipeStart: CGPoint?
    private var swipeDirection: SwipeDirection?
    private var swipeAction: ProgressGestureAction?
    private var swipeTriggerable = false
    private var swipePill: UILabel?
    private var didConsumePanAsSwipe = false

    private lazy var longPressGesture: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        // FluxDO: 200ms long-press opens radial menu.
        gesture.minimumPressDuration = 0.2
        // Allow slight finger jitter without cancelling the long-press.
        gesture.allowableMovement = 16
        gesture.cancelsTouchesInView = true
        gesture.delegate = self
        return gesture
    }()

    private lazy var panGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        gesture.maximumNumberOfTouches = 1
        gesture.cancelsTouchesInView = true
        // Do not delay touches — otherwise the bar feels dead on first contact.
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        gesture.delegate = self
        return gesture
    }()

    private lazy var tapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
        gesture.cancelsTouchesInView = false
        gesture.delegate = self
        return gesture
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        backgroundColor = .clear
        isExclusiveTouch = true
        isMultipleTouchEnabled = false
        isUserInteractionEnabled = true
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 14

        addSubview(surfaceView)
        surfaceView.addSubview(progressFillView)
        addSubview(labelStack)
        layer.addSublayer(pressProgressLayer)

        // Movement → pan (swipe). Stillness 200ms → long-press menu.
        // Tap opens timeline only when pan/long-press did not consume the touch.
        // Do NOT make tap require(toFail: longPress) — that delays every tap by 200ms.
        addGestureRecognizer(panGesture)
        addGestureRecognizer(longPressGesture)
        addGestureRecognizer(tapGesture)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.height),
            widthAnchor.constraint(equalToConstant: Metrics.width),

            surfaceView.topAnchor.constraint(equalTo: topAnchor),
            surfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),

            progressFillView.topAnchor.constraint(equalTo: surfaceView.topAnchor),
            progressFillView.leadingAnchor.constraint(equalTo: surfaceView.leadingAnchor),
            progressFillView.bottomAnchor.constraint(equalTo: surfaceView.bottomAnchor),

            labelStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            labelStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let fillWidth = progressFillView.widthAnchor.constraint(equalToConstant: 0)
        fillWidth.isActive = true
        progressFillWidthConstraint = fillWidth
        applyThemeStyle()
        refreshGestureRecognizers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyThemeStyle()
        layer.cornerRadius = bounds.height / 2
        surfaceView.layer.cornerRadius = bounds.height / 2
        progressFillWidthConstraint?.constant = surfaceView.bounds.width * progressFraction
        pressProgressLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
            cornerRadius: max(0, bounds.height / 2 - 1.5)
        ).cgPath
    }

    /// Enlarge the hit target — the 120×40 capsule is easy to miss above the home indicator.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -Metrics.hitSlop, dy: -Metrics.hitSlop).contains(point)
    }

    /// Ensure expanded hit slop still wins against the full-screen table underneath.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        guard self.point(inside: point, with: event) else { return nil }
        // Children are non-interactive decorations; the bar itself owns all gestures.
        return self
    }

    func configure(currentFloor: Int, totalFloors: Int) {
        applyThemeStyle()
        let safeTotal = max(totalFloors, 0)
        let safeCurrent = safeTotal == 0 ? 0 : min(max(currentFloor, 1), safeTotal)
        currentLabel.text = "\(safeCurrent)"
        totalLabel.text = "\(safeTotal)"
        progressFraction = safeTotal > 0 ? CGFloat(safeCurrent) / CGFloat(safeTotal) : 0
        setNeedsLayout()
        accessibilityLabel = String(localized: "topic_detail.progress.accessibility \(safeCurrent) \(safeTotal)")
        refreshGestureRecognizers()
    }

    /// Re-read AppSettings so swipe/long-press stay in sync with Reading settings.
    func refreshGestureRecognizers() {
        let enabled = gesturesEnabled
        // Tap always stays on (timeline). Pan / long-press follow the master switch.
        panGesture.isEnabled = enabled
        longPressGesture.isEnabled = enabled
        tapGesture.isEnabled = true
    }

    private func applyThemeStyle() {
        let accentColor = AppSettings.shared.themeStyle.accentColor
        progressFillView.backgroundColor = accentColor.withAlphaComponent(0.12)
        currentLabel.textColor = accentColor
        pressProgressLayer.strokeColor = accentColor.cgColor
    }

    private var gesturesEnabled: Bool {
        AppSettings.shared.progressGesturesEnabled
    }

    private var menuActions: [ProgressGestureAction] {
        let actions = AppSettings.shared.progressGestureMenuActions.filter { $0 != .none }
        return actions.isEmpty ? ProgressGestureAction.defaultMenuActions : actions
    }

    // MARK: - Tap

    @objc private func tapped() {
        guard !isPresentingRadialMenu, !didConsumePanAsSwipe else {
            didConsumePanAsSwipe = false
            return
        }
        feedback.impactOccurred(intensity: 0.5)
        delegate?.bottomBarDidTapTimeline()
    }

    // MARK: - Long press radial menu

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesturesEnabled else { return }
        let location = gesture.location(in: window ?? self)
        switch gesture.state {
        case .began:
            // Suppress the trailing tap once this press lifts; cleared on end/cancel
            // so a later long-press can open the menu again.
            didConsumePanAsSwipe = true
            animatePressProgress()
            presentRadialMenu(at: location)
        case .changed:
            updateRadialHighlight(at: location)
        case .ended:
            finishRadialMenu()
            // Defer clear so the simultaneous tap (if any) still sees the flag this turn.
            DispatchQueue.main.async { [weak self] in
                self?.didConsumePanAsSwipe = false
            }
        case .cancelled, .failed:
            dismissRadialMenu(trigger: false)
            DispatchQueue.main.async { [weak self] in
                self?.didConsumePanAsSwipe = false
            }
        default:
            break
        }
    }

    // MARK: - Swipe gestures

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesturesEnabled else { return }
        // Prefer translation (stable) over absolute window points (can jump on rotation).
        let translation = gesture.translation(in: self)
        let location = gesture.location(in: window ?? self)
        switch gesture.state {
        case .began:
            swipeStart = .zero
            swipeDirection = nil
            swipeAction = nil
            swipeTriggerable = false
            didConsumePanAsSwipe = false
            retractPressProgress()
            ensureSwipePill()
            updateSwipe(translation: translation, finger: location)
        case .changed:
            updateSwipe(translation: translation, finger: location)
        case .ended:
            let shouldFire = swipeTriggerable
            let action = swipeAction
            let travel = max(abs(translation.x), abs(translation.y))
            clearSwipePreview()
            if shouldFire, let action, action != .none {
                didConsumePanAsSwipe = true
                feedback.impactOccurred()
                delegate?.bottomBarDidSelectProgressAction(action)
            } else if travel < Metrics.swipeDeadZone {
                // Barely moved — let tapGesture open the timeline (avoid double-fire).
                didConsumePanAsSwipe = false
            } else {
                // Moved enough to count as a swipe attempt but not to trigger:
                // suppress the trailing tap so we don't open timeline by accident.
                didConsumePanAsSwipe = true
            }
            // Clear flag after the runloop so tapGesture still sees it this turn.
            DispatchQueue.main.async { [weak self] in
                self?.didConsumePanAsSwipe = false
            }
        case .cancelled, .failed:
            clearSwipePreview()
            DispatchQueue.main.async { [weak self] in
                self?.didConsumePanAsSwipe = false
            }
        default:
            break
        }
    }

    private func updateSwipe(translation: CGPoint, finger: CGPoint) {
        let dx = translation.x
        let dy = translation.y
        let absDx = abs(dx)
        let absDy = abs(dy)
        let maxDelta = max(absDx, absDy)

        var direction: SwipeDirection?
        if maxDelta >= Metrics.swipeDeadZone {
            if absDx >= absDy {
                direction = dx < 0 ? .left : .right
            } else if dy < 0 {
                direction = .up
            }
            // Downward is not bound — ignore so vertical list scroll intent doesn't false-fire.
        }

        let settings = AppSettings.shared
        var action: ProgressGestureAction?
        switch direction {
        case .left: action = settings.progressGestureSwipeLeft
        case .right: action = settings.progressGestureSwipeRight
        case .up: action = settings.progressGestureSwipeUp
        case .none: action = nil
        }
        if action == ProgressGestureAction.none { action = nil }

        let triggerable = action != nil && maxDelta >= Metrics.swipeTriggerDistance
        if triggerable != swipeTriggerable, triggerable {
            selectionFeedback.selectionChanged()
        } else if direction != swipeDirection, direction != nil {
            selectionFeedback.selectionChanged()
        }

        swipeDirection = direction
        swipeAction = action
        swipeTriggerable = triggerable
        // Once the finger clearly swiped, suppress the trailing tap.
        if maxDelta >= Metrics.swipeDeadZone {
            didConsumePanAsSwipe = true
        }
        updateSwipePill(at: finger)
    }

    private func ensureSwipePill() {
        guard swipePill == nil, let window else { return }
        let pill = UILabel()
        pill.font = .systemFont(ofSize: 13, weight: .semibold)
        pill.textColor = .white
        pill.textAlignment = .center
        pill.backgroundColor = AppSettings.shared.themeStyle.accentColor
        pill.layer.cornerRadius = 14
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        pill.alpha = 0
        window.addSubview(pill)
        swipePill = pill
    }

    private func updateSwipePill(at point: CGPoint) {
        guard let pill = swipePill else { return }
        guard let action = swipeAction else {
            pill.alpha = 0
            return
        }
        let prefix: String
        switch swipeDirection {
        case .left: prefix = "← "
        case .right: prefix = "→ "
        case .up: prefix = "↑ "
        case .none: prefix = ""
        }
        pill.text = "  \(prefix)\(action.title)  "
        pill.sizeToFit()
        let size = CGSize(width: max(pill.bounds.width + 8, 72), height: 28)
        pill.bounds = CGRect(origin: .zero, size: size)
        pill.center = CGPoint(x: point.x, y: point.y - 36)
        pill.alpha = swipeTriggerable ? 1 : 0.55
        pill.backgroundColor = swipeTriggerable
            ? AppSettings.shared.themeStyle.accentColor
            : UIColor.secondaryLabel
    }

    private func clearSwipePreview() {
        swipeStart = nil
        swipeDirection = nil
        swipeAction = nil
        swipeTriggerable = false
        swipePill?.removeFromSuperview()
        swipePill = nil
    }

    private func animatePressProgress() {
        pressProgressLayer.removeAnimation(forKey: "strokeEnd")
        pressProgressLayer.strokeEnd = 0
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 0.52
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pressProgressLayer.strokeEnd = 1
        pressProgressLayer.add(animation, forKey: "strokeEnd")
    }

    private func retractPressProgress() {
        pressProgressLayer.removeAnimation(forKey: "strokeEnd")
        let current = pressProgressLayer.presentation()?.strokeEnd ?? pressProgressLayer.strokeEnd
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = current
        animation.toValue = 0
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        pressProgressLayer.strokeEnd = 0
        pressProgressLayer.add(animation, forKey: "strokeEnd")
    }

    private func presentRadialMenu(at location: CGPoint) {
        // Drop any stale overlay so re-press always works after a prior dismiss.
        if radialOverlay != nil {
            radialOverlay?.removeFromSuperview()
            radialOverlay = nil
            isPresentingRadialMenu = false
        }
        guard let window else { return }
        let actions = menuActions
        guard !actions.isEmpty else { return }
        isPresentingRadialMenu = true
        feedback.prepare()
        selectionFeedback.prepare()

        let center = convert(CGPoint(x: bounds.midX, y: bounds.minY), to: window)
        let pressRect = convert(bounds, to: window)
        let overlay = TopicDetailRadialMenuOverlay(
            frame: window.bounds,
            center: center,
            pressRect: pressRect,
            actions: actions
        )
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
        radialOverlay = overlay
        feedback.impactOccurred()
        updateRadialHighlight(at: location)
    }

    private func updateRadialHighlight(at location: CGPoint) {
        guard let overlay = radialOverlay else { return }
        let action = overlay.updateHighlight(at: location)
        if action != highlightedAction, action != nil {
            selectionFeedback.selectionChanged()
        }
        highlightedAction = action
    }

    private func finishRadialMenu() {
        let action = highlightedAction
        dismissRadialMenu(trigger: action != nil)
        if let action {
            delegate?.bottomBarDidSelectProgressAction(action)
        }
    }

    private func dismissRadialMenu(trigger: Bool) {
        if trigger {
            feedback.impactOccurred()
        }
        highlightedAction = nil
        isPresentingRadialMenu = false
        radialOverlay?.dismiss()
        radialOverlay = nil
        retractPressProgress()
    }
}

extension TopicDetailBottomBar: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Never share recognition with the table / nav back-swipe / other pans.
        // Pan vs long-press on this view also stay exclusive.
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        // Master switch off → only tap (timeline) remains.
        if gestureRecognizer === panGesture || gestureRecognizer === longPressGesture {
            return gesturesEnabled
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === tapGesture {
            return !isPresentingRadialMenu && !didConsumePanAsSwipe
        }
        if gestureRecognizer === longPressGesture {
            // Only gate on the master switch — do not require `!didConsumePanAsSwipe`,
            // otherwise a leftover flag after the first menu blocks every re-open.
            return gesturesEnabled
        }
        guard gestureRecognizer === panGesture else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        guard gesturesEnabled else { return false }

        // CRITICAL: do NOT gate on translation/velocity here.
        // When UIKit first asks shouldBegin, translation is often still ~0; returning
        // false fails the pan for the entire touch and swipe never fires.
        // Direction + distance are decided in handlePan(_:).
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Our pan/long-press must win over ancestor pans (nav back-swipe on
        // navigationController.view) and any sibling scroll pans that somehow
        // see the same touch.
        if gestureRecognizer === panGesture || gestureRecognizer === longPressGesture {
            if otherGestureRecognizer.view === self { return false }
            if otherGestureRecognizer is UIPanGestureRecognizer {
                return true
            }
            if otherGestureRecognizer is UISwipeGestureRecognizer {
                return true
            }
        }
        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // No failure dependencies: requiring long-press to fail delays every tap by
        // up to minimumPressDuration. Swipe/long-press suppress tap via
        // `didConsumePanAsSwipe` instead.
        false
    }
}

private final class TopicDetailRadialMenuOverlay: UIView {
    private struct Item {
        let action: ProgressGestureAction
        let view: TopicDetailRadialMenuItemView
        let center: CGPoint
    }

    private let centerPoint: CGPoint
    private let pressRect: CGRect
    private let actions: [ProgressGestureAction]
    private let deadZoneRadius: CGFloat = 30
    private let radius: CGFloat
    private var items: [Item] = []
    private var highlightedAction: ProgressGestureAction?

    private let blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: nil)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()

    private let dimView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0)
        view.isUserInteractionEnabled = false
        return view
    }()

    init(
        frame: CGRect,
        center: CGPoint,
        pressRect: CGRect,
        actions: [ProgressGestureAction]
    ) {
        centerPoint = center
        self.pressRect = pressRect
        self.actions = actions
        // ~130pt spreads 6 items without feeling sparse.
        switch actions.count {
        case ...3: radius = 100
        case 4: radius = 118
        case 5: radius = 126
        default: radius = 130
        }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        setupViews()
        animateIn()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateHighlight(at point: CGPoint) -> ProgressGestureAction? {
        let dx = point.x - centerPoint.x
        let dy = point.y - centerPoint.y
        let distance = sqrt(dx * dx + dy * dy)
        let newAction: ProgressGestureAction?
        if distance < deadZoneRadius || dy >= 8 {
            newAction = nil
        } else {
            newAction = items.min { lhs, rhs in
                hypot(lhs.center.x - point.x, lhs.center.y - point.y) < hypot(rhs.center.x - point.x, rhs.center.y - point.y)
            }?.action
        }

        guard newAction != highlightedAction else { return highlightedAction }
        highlightedAction = newAction
        for item in items {
            item.view.setHighlighted(item.action == newAction, animated: true)
        }
        return newAction
    }

    func dismiss() {
        DoerMotion.animate(
            duration: DoerMotion.quick,
            timingParameters: DoerMotion.easeInCubic,
            animations: {
                self.blurView.effect = nil
                self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0)
                for item in self.items {
                    item.view.center = self.emitterCenter
                    item.view.alpha = 0
                    item.view.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
                }
            },
            completion: { _ in
                self.removeFromSuperview()
            }
        )
    }

    private var emitterCenter: CGPoint {
        pressRect.isNull ? centerPoint : CGPoint(x: pressRect.midX, y: pressRect.midY)
    }

    private func setupViews() {
        addSubview(blurView)
        addSubview(dimView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            dimView.topAnchor.constraint(equalTo: topAnchor),
            dimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let count = actions.count
        let step = count <= 1 ? 0 : CGFloat.pi / CGFloat(count - 1)
        for (index, action) in actions.enumerated() {
            let angle = CGFloat.pi + step * CGFloat(index)
            let target = CGPoint(
                x: centerPoint.x + cos(angle) * radius,
                y: centerPoint.y + sin(angle) * radius
            )
            let itemView = TopicDetailRadialMenuItemView(action: action)
            itemView.center = emitterCenter
            itemView.alpha = 0
            itemView.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
            addSubview(itemView)
            items.append(Item(action: action, view: itemView, center: target))
        }
    }

    private func animateIn() {
        DoerMotion.animate(duration: DoerMotion.quick) {
            self.blurView.effect = UIBlurEffect(style: .systemThinMaterial)
            self.dimView.backgroundColor = UIColor.black.withAlphaComponent(0.20)
        }

        for (index, item) in items.enumerated() {
            UIView.animate(
                withDuration: 0.34,
                delay: 0.018 * Double(index),
                usingSpringWithDamping: 0.76,
                initialSpringVelocity: 0.7,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    item.view.center = item.center
                    item.view.alpha = 1
                    item.view.transform = .identity
                }
            )
        }
    }
}

private final class TopicDetailRadialMenuItemView: UIView {
    private enum Metrics {
        static let iconSize: CGFloat = 54
        static let labelTop: CGFloat = 6
        static let itemWidth: CGFloat = 80
        static let itemHeight: CGFloat = 80
    }

    private let iconContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = Metrics.iconSize / 2
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.16
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 10
        return view
    }()

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = .label
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.85
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.35
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        return label
    }()

    init(action: ProgressGestureAction) {
        super.init(frame: CGRect(x: 0, y: 0, width: Metrics.itemWidth, height: Metrics.itemHeight))
        isUserInteractionEnabled = false
        imageView.image = UIImage(
            systemName: action.symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        )
        titleLabel.text = action.title
        addSubview(iconContainer)
        iconContainer.addSubview(imageView)
        addSubview(titleLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        iconContainer.frame = CGRect(
            x: (bounds.width - Metrics.iconSize) / 2,
            y: 0,
            width: Metrics.iconSize,
            height: Metrics.iconSize
        )
        imageView.frame = iconContainer.bounds.insetBy(dx: 15, dy: 15)
        titleLabel.frame = CGRect(
            x: 2,
            y: iconContainer.frame.maxY + Metrics.labelTop,
            width: bounds.width - 4,
            height: 18
        )
    }

    func setHighlighted(_ highlighted: Bool, animated: Bool) {
        let changes = {
            self.iconContainer.backgroundColor = highlighted ? .tintColor : .secondarySystemBackground
            self.imageView.tintColor = highlighted ? .white : .label
            self.transform = highlighted ? CGAffineTransform(scaleX: 1.16, y: 1.16) : .identity
        }
        guard animated else {
            changes()
            return
        }
        DoerMotion.animate(duration: DoerMotion.quick, animations: changes)
    }
}
