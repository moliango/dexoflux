import UIKit

enum TopicDetailRadialAction: CaseIterable {
    case timeline
    case scrollToTop
    case reply
    case bookmark
    case share

    var title: String {
        switch self {
        case .timeline:
            return String(localized: "topic_detail.action.timeline")
        case .scrollToTop:
            return String(localized: "topic_detail.action.top")
        case .reply:
            return String(localized: "topic_detail.action.reply")
        case .bookmark:
            return String(localized: "topic_detail.action.bookmark")
        case .share:
            return String(localized: "topic_detail.action.share")
        }
    }

    var symbolName: String {
        switch self {
        case .timeline:
            return "list.bullet.rectangle"
        case .scrollToTop:
            return "arrow.up.to.line"
        case .reply:
            return "arrowshape.turn.up.left"
        case .bookmark:
            return "bookmark"
        case .share:
            return "link"
        }
    }
}

protocol TopicDetailBottomBarDelegate: AnyObject {
    func bottomBarDidTapTimeline()
    func bottomBarDidSelectRadialAction(_ action: TopicDetailRadialAction)
}

final class TopicDetailBottomBar: UIControl {
    weak var delegate: TopicDetailBottomBarDelegate?

    private enum Metrics {
        static let height: CGFloat = 40
        static let width: CGFloat = 120
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
    private var highlightedAction: TopicDetailRadialAction?
    private var isPresentingRadialMenu = false
    private var progressFraction: CGFloat = 0
    private var progressFillWidthConstraint: NSLayoutConstraint?
    private let feedback = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedback = UISelectionFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        backgroundColor = .clear
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 14

        addSubview(surfaceView)
        surfaceView.addSubview(progressFillView)
        addSubview(labelStack)
        layer.addSublayer(pressProgressLayer)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.2
        longPress.cancelsTouchesInView = false
        addGestureRecognizer(longPress)

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

    func configure(currentFloor: Int, totalFloors: Int) {
        applyThemeStyle()
        let safeTotal = max(totalFloors, 0)
        let safeCurrent = safeTotal == 0 ? 0 : min(max(currentFloor, 1), safeTotal)
        currentLabel.text = "\(safeCurrent)"
        totalLabel.text = "\(safeTotal)"
        progressFraction = safeTotal > 0 ? CGFloat(safeCurrent) / CGFloat(safeTotal) : 0
        setNeedsLayout()
        accessibilityLabel = String(localized: "topic_detail.progress.accessibility \(safeCurrent) \(safeTotal)")
    }

    private func applyThemeStyle() {
        let accentColor = AppSettings.shared.themeStyle.accentColor
        progressFillView.backgroundColor = accentColor.withAlphaComponent(0.12)
        currentLabel.textColor = accentColor
        pressProgressLayer.strokeColor = accentColor.cgColor
    }

    // MARK: - Actions

    @objc private func tapped() {
        guard !isPresentingRadialMenu else { return }
        delegate?.bottomBarDidTapTimeline()
    }

    @objc private func touchDown() {
        animatePressProgress()
    }

    @objc private func touchEnded() {
        if !isPresentingRadialMenu {
            retractPressProgress()
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = window.map { gesture.location(in: $0) } ?? gesture.location(in: nil)
        switch gesture.state {
        case .began:
            presentRadialMenu(at: location)
        case .changed:
            updateRadialHighlight(at: location)
        case .ended:
            finishRadialMenu()
        case .cancelled, .failed:
            dismissRadialMenu(trigger: false)
        default:
            break
        }
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
        guard radialOverlay == nil, let window else { return }
        isPresentingRadialMenu = true
        feedback.prepare()
        selectionFeedback.prepare()

        let center = convert(CGPoint(x: bounds.midX, y: bounds.minY), to: window)
        let pressRect = convert(bounds, to: window)
        let overlay = TopicDetailRadialMenuOverlay(
            frame: window.bounds,
            center: center,
            pressRect: pressRect,
            actions: TopicDetailRadialAction.allCases
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
            delegate?.bottomBarDidSelectRadialAction(action)
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

private final class TopicDetailRadialMenuOverlay: UIView {
    private struct Item {
        let action: TopicDetailRadialAction
        let view: TopicDetailRadialMenuItemView
        let center: CGPoint
    }

    private let centerPoint: CGPoint
    private let pressRect: CGRect
    private let actions: [TopicDetailRadialAction]
    private let deadZoneRadius: CGFloat = 26
    private let radius: CGFloat
    private var items: [Item] = []
    private var highlightedAction: TopicDetailRadialAction?

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
        actions: [TopicDetailRadialAction]
    ) {
        centerPoint = center
        self.pressRect = pressRect
        self.actions = actions
        radius = actions.count <= 4 ? 92 : 110
        super.init(frame: frame)
        isUserInteractionEnabled = false
        setupViews()
        animateIn()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateHighlight(at point: CGPoint) -> TopicDetailRadialAction? {
        let dx = point.x - centerPoint.x
        let dy = point.y - centerPoint.y
        let distance = sqrt(dx * dx + dy * dy)
        let newAction: TopicDetailRadialAction?
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
        DexoMotion.animate(
            duration: DexoMotion.quick,
            timingParameters: DexoMotion.easeInCubic,
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
        DexoMotion.animate(duration: DexoMotion.quick) {
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
        static let iconSize: CGFloat = 50
        static let labelTop: CGFloat = 4
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
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.35
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = CGSize(width: 0, height: 1)
        return label
    }()

    init(action: TopicDetailRadialAction) {
        super.init(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
        isUserInteractionEnabled = false
        imageView.image = UIImage(
            systemName: action.symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
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
        imageView.frame = iconContainer.bounds.insetBy(dx: 14, dy: 14)
        titleLabel.frame = CGRect(
            x: 0,
            y: iconContainer.frame.maxY + Metrics.labelTop,
            width: bounds.width,
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
        DexoMotion.animate(duration: DexoMotion.quick, animations: changes)
    }
}
