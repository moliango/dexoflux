import UIKit

final class TopicTimelineSheetViewController: UIViewController {
    var onJumpToPostId: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    private let initialIndex: Int
    private let stream: [Int]
    private let titleText: String?
    private var selectedIndex: Int
    private let feedback = UISelectionFeedbackGenerator()
    private var totalCount: Int { stream.count }

    private let grabberView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .tertiaryLabel.withAlphaComponent(0.35)
        view.layer.cornerRadius = 2
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textAlignment = .center
        return label
    }()

    private let currentFloorCaptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "topic_detail.timeline.current_floor")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var floorTextField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.keyboardType = .numberPad
        field.textAlignment = .left
        field.font = .monospacedDigitSystemFont(ofSize: 52, weight: .black)
        field.textColor = .tintColor
        field.tintColor = .tintColor
        field.borderStyle = .none
        field.delegate = self
        field.addTarget(self, action: #selector(floorTextChanged), for: .editingChanged)
        return field
    }()

    private let totalLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 21, weight: .semibold)
        label.textColor = .tertiaryLabel
        return label
    }()

    private let editIconView: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "pencil"))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .tertiaryLabel
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .label
        label.backgroundColor = UIColor.tintColor.withAlphaComponent(0.12)
        label.layer.cornerRadius = 8
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.textAlignment = .center
        return label
    }()

    private lazy var trackView: TopicTimelineTrackView = {
        let view = TopicTimelineTrackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.totalCount = totalCount
        view.selectedIndex = selectedIndex
        view.addTarget(self, action: #selector(trackValueChanged(_:)), for: .valueChanged)
        return view
    }()

    /// Vertical scrubber height inside the sheet (must match the track constraint).
    static let trackHeight: CGFloat = 220

    /// Content-fitted sheet height used by the presenter detent (excludes home indicator).
    /// Keep in sync with viewDidLoad vertical chain so the sheet does not leave a tall
    /// empty band under the cancel/jump row.
    /// Do not pin action buttons to the sheet bottom — after app switch the sheet
    /// container can grow taller than the visible detent and bottom-pinned controls sink off-screen.
    static var preferredSheetHeight: CGFloat {
        // grabber(8+4) + title gap+line(12+22) + content(14+track) + actions(16+48) + bottom(8)
        8 + 4 + 12 + 22 + 14 + trackHeight + 16 + 48 + 8
    }

    private var buttonRow: UIStackView?
    private var foregroundObserver: NSObjectProtocol?

    init(currentIndex: Int, stream: [Int], title: String?) {

        self.stream = stream
        let safeTotal = max(stream.count, 1)
        self.initialIndex = min(max(currentIndex, 1), safeTotal)
        self.selectedIndex = min(max(currentIndex, 1), safeTotal)
        self.titleText = title
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let floorRow = UIStackView(arrangedSubviews: [floorTextField, totalLabel, editIconView])
        floorRow.translatesAutoresizingMaskIntoConstraints = false
        floorRow.axis = .horizontal
        floorRow.alignment = .bottom
        floorRow.spacing = 8

        let infoStack = UIStackView(arrangedSubviews: [currentFloorCaptionLabel, floorRow, statusLabel])
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoStack.axis = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 10

        let contentRow = UIStackView(arrangedSubviews: [infoStack, trackView])
        contentRow.translatesAutoresizingMaskIntoConstraints = false
        contentRow.axis = .horizontal
        contentRow.alignment = .center
        contentRow.spacing = 20

        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle(String(localized: "action.cancel"), for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let jumpButton = UIButton(type: .system)
        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        var jumpConfig = UIButton.Configuration.filled()
        jumpConfig.title = String(localized: "topic_detail.jump.confirm")
        jumpConfig.cornerStyle = .large
        jumpConfig.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        jumpButton.configuration = jumpConfig
        jumpButton.addTarget(self, action: #selector(jumpTapped), for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [cancelButton, jumpButton])
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.axis = .horizontal
        buttonRow.distribution = .fillEqually
        buttonRow.spacing = 16
        self.buttonRow = buttonRow

        titleLabel.text = titleText
        totalLabel.text = "/ \(totalCount)"

        view.addSubview(grabberView)
        view.addSubview(titleLabel)
        view.addSubview(contentRow)
        view.addSubview(buttonRow)

        // Keep cancel/jump directly under the floor controls.
        // Pinning to safeArea.bottom fails when the sheet container grows taller than the
        // visible detent (common after background→foreground): buttons sink below the fold.
        NSLayoutConstraint.activate([
            grabberView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            grabberView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabberView.widthAnchor.constraint(equalToConstant: 36),
            grabberView.heightAnchor.constraint(equalToConstant: 4),

            titleLabel.topAnchor.constraint(equalTo: grabberView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            contentRow.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: titleText == nil ? 6 : 14),
            contentRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            contentRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),

            floorTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            floorTextField.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            editIconView.widthAnchor.constraint(equalToConstant: 16),
            editIconView.heightAnchor.constraint(equalToConstant: 16),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 86),
            trackView.widthAnchor.constraint(equalToConstant: 56),
            trackView.heightAnchor.constraint(equalToConstant: Self.trackHeight),

            buttonRow.topAnchor.constraint(equalTo: contentRow.bottomAnchor, constant: 16),
            buttonRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttonRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonRow.heightAnchor.constraint(equalToConstant: 48),
            // Soft ceiling only — never require bottom equality against a growing sheet.
            // Keep a tight 8pt reserve so the detent does not leave a tall empty strip.
            buttonRow.bottomAnchor.constraint(
                lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -8
            ),
        ])

        if titleText == nil {
            titleLabel.isHidden = true
        }
        feedback.prepare()
        updateFloorDisplay()
        observeForegroundReturn()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        relayoutSheetChrome()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Second pass after the sheet finishes its presentation / foreground animation.
        relayoutSheetChrome()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil {
            tearDownForegroundObserver()
            onDismiss?()
        }
    }

    deinit {
        tearDownForegroundObserver()
    }

    private func observeForegroundReturn() {
        guard foregroundObserver == nil else { return }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.relayoutSheetChrome()
        }
    }

    private func tearDownForegroundObserver() {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
    }

    /// Re-fit detents and keep the action row on-screen after background/foreground.
    private func relayoutSheetChrome() {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        if let buttonRow {
            view.bringSubviewToFront(buttonRow)
            buttonRow.isHidden = false
            buttonRow.alpha = 1
        }
        if #available(iOS 16.0, *), let sheet = sheetPresentationController {
            sheet.invalidateDetents()
            // Re-select the compact timeline detent in case the system expanded the sheet.
            if let identifier = sheet.detents.first?.identifier {
                sheet.selectedDetentIdentifier = identifier
            }
        }
    }

    @objc private func trackValueChanged(_ sender: TopicTimelineTrackView) {
        setSelectedIndex(sender.selectedIndex, haptic: true)
    }

    @objc private func floorTextChanged() {
        guard let text = floorTextField.text,
              let value = Int(text)
        else { return }
        setSelectedIndex(min(max(value, 1), totalCount), haptic: true, updateText: false)
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func jumpTapped() {
        view.endEditing(true)
        normalizeInputFloor()
        let index = selectedIndex - 1
        guard stream.indices.contains(index) else {
            dismiss(animated: true)
            return
        }
        let selectedPostId = stream[index]
        dismiss(animated: true) { [onJumpToPostId] in
            onJumpToPostId?(selectedPostId)
        }
    }

    private func setSelectedIndex(_ index: Int, haptic: Bool, updateText: Bool = true) {
        let next = min(max(index, 1), totalCount)
        guard next != selectedIndex else {
            updateFloorDisplay(updateText: updateText)
            return
        }
        selectedIndex = next
        trackView.selectedIndex = next
        if haptic {
            feedback.selectionChanged()
            feedback.prepare()
        }
        updateFloorDisplay(updateText: updateText)
    }

    private func updateFloorDisplay(updateText: Bool = true) {
        if updateText {
            floorTextField.text = "\(selectedIndex)"
        }
        statusLabel.text = selectedIndex == initialIndex
            ? String(localized: "topic_detail.timeline.current")
            : String(localized: "topic_detail.timeline.ready")
    }

    private func normalizeInputFloor() {
        guard let text = floorTextField.text,
              let value = Int(text)
        else {
            updateFloorDisplay()
            return
        }
        setSelectedIndex(value, haptic: false)
    }
}

extension TopicTimelineSheetViewController: UITextFieldDelegate {
    func textFieldDidEndEditing(_ textField: UITextField) {
        normalizeInputFloor()
    }
}

final class TopicTimelineTrackView: UIControl, UIGestureRecognizerDelegate {
    var totalCount: Int {
        get { totalCountValue }
        set {
            totalCountValue = max(newValue, 1)
            selectedIndexValue = clampedIndex(selectedIndexValue)
            setNeedsDisplay()
        }
    }

    var selectedIndex: Int {
        get { selectedIndexValue }
        set {
            let next = clampedIndex(newValue)
            guard next != selectedIndexValue else { return }
            selectedIndexValue = next
            setNeedsDisplay()
        }
    }

    private var totalCountValue = 1
    private var selectedIndexValue = 1
    private let trackInset: CGFloat = 24
    private let handleSize: CGFloat = 36

    override var intrinsicContentSize: CGSize {
        CGSize(width: 64, height: TopicTimelineSheetViewController.trackHeight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        accessibilityTraits = [.adjustable]

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let trackWidth: CGFloat = 5
        let top = trackInset
        let bottom = bounds.height - trackInset
        let height = max(bottom - top, 1)
        let x = bounds.midX - trackWidth / 2
        let trackRect = CGRect(x: x, y: top, width: trackWidth, height: height)
        let handleY = yPosition(for: selectedIndex)
        let activeRect = CGRect(x: x, y: top, width: trackWidth, height: max(handleY - top, 0))

        UIColor.tertiarySystemFill.setFill()
        UIBezierPath(roundedRect: trackRect, cornerRadius: trackWidth / 2).fill()

        tintColor.withAlphaComponent(0.45).setFill()
        UIBezierPath(roundedRect: activeRect, cornerRadius: trackWidth / 2).fill()

        drawEndpointMark(center: CGPoint(x: bounds.midX, y: top), filled: true)
        drawEndpointMark(center: CGPoint(x: bounds.midX, y: bottom), filled: false)

        let handleRect = CGRect(
            x: bounds.midX - handleSize / 2,
            y: handleY - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        UIColor.black.withAlphaComponent(0.10).setFill()
        UIBezierPath(ovalIn: handleRect.offsetBy(dx: 0, dy: 3)).fill()
        tintColor.setFill()
        UIBezierPath(ovalIn: handleRect).fill()

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        let image = UIImage(systemName: "arrow.up.arrow.down", withConfiguration: symbolConfig)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let imageSize = CGSize(width: 18, height: 18)
        image?.draw(in: CGRect(
            x: handleRect.midX - imageSize.width / 2,
            y: handleRect.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        ))
    }

    override func accessibilityIncrement() {
        selectedIndex = clampedIndex(selectedIndex + 1)
        sendActions(for: .valueChanged)
    }

    override func accessibilityDecrement() {
        selectedIndex = clampedIndex(selectedIndex - 1)
        sendActions(for: .valueChanged)
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSelection(for: touch)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        updateSelection(for: touch)
        return true
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            updateSelection(at: gesture.location(in: self).y)
        default:
            break
        }
    }

    private func updateSelection(for touch: UITouch) {
        updateSelection(at: touch.location(in: self).y)
    }

    private func updateSelection(at y: CGFloat) {
        let index = indexForY(y)
        guard index != selectedIndex else { return }
        selectedIndex = index
        sendActions(for: .valueChanged)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.y) >= abs(velocity.x)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard otherGestureRecognizer is UIPanGestureRecognizer else { return false }
        return otherGestureRecognizer.view !== self
    }

    private func clampedIndex(_ index: Int) -> Int {
        min(max(index, 1), max(totalCount, 1))
    }

    private func yPosition(for index: Int) -> CGFloat {
        let top = trackInset
        let bottom = bounds.height - trackInset
        guard totalCount > 1 else { return top }
        let percent = CGFloat(index - 1) / CGFloat(totalCount - 1)
        return top + (bottom - top) * percent
    }

    private func indexForY(_ y: CGFloat) -> Int {
        let top = trackInset
        let bottom = bounds.height - trackInset
        guard totalCount > 1 else { return 1 }
        let percent = min(max((y - top) / max(bottom - top, 1), 0), 1)
        return Int(round(percent * CGFloat(totalCount - 1))) + 1
    }

    private func drawEndpointMark(center: CGPoint, filled: Bool) {
        let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        if filled {
            tintColor.setFill()
            UIBezierPath(ovalIn: rect).fill()
        } else {
            UIColor.systemBackground.setFill()
            UIBezierPath(ovalIn: rect).fill()
        }
        tintColor.setStroke()
        let path = UIBezierPath(ovalIn: rect)
        path.lineWidth = 2
        path.stroke()
    }
}
