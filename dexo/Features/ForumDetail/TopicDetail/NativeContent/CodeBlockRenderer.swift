import UIKit
import CookedHTML

enum CodeBlockRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .codeBlock = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .codeBlock(let language, let code) = block else { return UIView() }
        return MacStyleCodeBlockView(language: language, code: code, config: config)
    }
}

private final class MacStyleCodeBlockView: UIView {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 18
        static let verticalPadding: CGFloat = 16
        static let topControlInset: CGFloat = 18
        static let maxCodeViewportHeight: CGFloat = 420
    }

    private let code: String
    private let copyButton = UIButton(type: .system)
    private let copyButtonBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private var resetCopyIconWorkItem: DispatchWorkItem?
    private var hideCopyButtonWorkItem: DispatchWorkItem?

    init(language: String?, code: String, config: NativeRenderConfig) {
        self.code = code
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.withAlphaComponent(0.38).cgColor
        clipsToBounds = true

        let trafficStack = UIStackView(arrangedSubviews: [
            Self.makeTrafficDot(color: .systemRed),
            Self.makeTrafficDot(color: .systemYellow),
            Self.makeTrafficDot(color: .systemGreen),
        ])
        trafficStack.translatesAutoresizingMaskIntoConstraints = false
        trafficStack.axis = .horizontal
        trafficStack.spacing = 6
        trafficStack.alignment = .center

        let copyConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        copyButtonBackground.translatesAutoresizingMaskIntoConstraints = false
        copyButtonBackground.layer.cornerRadius = 15
        copyButtonBackground.layer.cornerCurve = .continuous
        copyButtonBackground.clipsToBounds = true
        copyButtonBackground.alpha = 0

        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: copyConfig), for: .normal)
        copyButton.tintColor = .secondaryLabel
        copyButton.accessibilityLabel = String(localized: "code_block.copy")
        copyButton.isPointerInteractionEnabled = true

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.backgroundColor = .clear
        scrollView.indicatorStyle = .default

        let codeLabel = UILabel()
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        codeLabel.numberOfLines = 0
        codeLabel.lineBreakMode = .byClipping
        codeLabel.attributedText = Self.attributedCode(code, config: config)

        addSubview(scrollView)
        scrollView.addSubview(codeLabel)
        addSubview(trafficStack)
        addSubview(copyButtonBackground)
        copyButtonBackground.contentView.addSubview(copyButton)

        let measured = Self.measure(code: code, font: config.codeFont, config: config)
        let viewportHeight = min(measured.contentHeight, Metrics.maxCodeViewportHeight)
        scrollView.showsVerticalScrollIndicator = measured.contentHeight > Metrics.maxCodeViewportHeight

        NSLayoutConstraint.activate([
            trafficStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            trafficStack.topAnchor.constraint(equalTo: topAnchor, constant: 13),

            copyButtonBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            copyButtonBackground.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            copyButtonBackground.widthAnchor.constraint(equalToConstant: 30),
            copyButtonBackground.heightAnchor.constraint(equalToConstant: 30),

            copyButton.centerXAnchor.constraint(equalTo: copyButtonBackground.contentView.centerXAnchor),
            copyButton.centerYAnchor.constraint(equalTo: copyButtonBackground.contentView.centerYAnchor),
            copyButton.widthAnchor.constraint(equalToConstant: 30),
            copyButton.heightAnchor.constraint(equalToConstant: 30),

            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.topControlInset + 24),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: viewportHeight),

            codeLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Metrics.verticalPadding),
            codeLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Metrics.horizontalPadding),
            codeLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Metrics.horizontalPadding),
            codeLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Metrics.verticalPadding),
            codeLabel.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -Metrics.horizontalPadding * 2),
            codeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: measured.contentWidth),
        ])

        copyButton.addTarget(self, action: #selector(copyCodeTapped), for: .touchUpInside)
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleCodeBlockTap))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        resetCopyIconWorkItem?.cancel()
        hideCopyButtonWorkItem?.cancel()
    }

    @objc private func copyCodeTapped() {
        UIPasteboard.general.string = code
        showCopyButton(scheduleHide: false)
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        copyButton.setImage(UIImage(systemName: "checkmark", withConfiguration: symbolConfig), for: .normal)
        copyButton.tintColor = .systemGreen

        resetCopyIconWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.copyButton.setImage(UIImage(systemName: "doc.on.doc", withConfiguration: symbolConfig), for: .normal)
            self?.copyButton.tintColor = .secondaryLabel
            self?.scheduleCopyButtonHide()
        }
        resetCopyIconWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            showCopyButton(scheduleHide: false)
        case .ended, .cancelled, .failed:
            scheduleCopyButtonHide()
        default:
            break
        }
    }

    @objc private func handleCodeBlockTap() {
        showCopyButton(scheduleHide: true)
    }

    private func showCopyButton(scheduleHide: Bool) {
        hideCopyButtonWorkItem?.cancel()
        UIView.animate(
            withDuration: 0.16,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]
        ) {
            self.copyButtonBackground.alpha = 1
        }
        if scheduleHide {
            scheduleCopyButtonHide()
        }
    }

    private func scheduleCopyButtonHide() {
        hideCopyButtonWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self?.copyButtonBackground.alpha = 0
            }
        }
        hideCopyButtonWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: item)
    }

    private static func makeTrafficDot(color: UIColor) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = color
        view.layer.cornerRadius = 5
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 10),
            view.heightAnchor.constraint(equalToConstant: 10),
        ])
        return view
    }

    private static func attributedCode(_ code: String, config: NativeRenderConfig) -> NSAttributedString {
        let result = NSMutableAttributedString(string: code.isEmpty ? " " : code)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = max(3, config.defaultLineSpacing - 2)
        paragraphStyle.minimumLineHeight = config.codeFont.lineHeight + paragraphStyle.lineSpacing
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes([
            .font: config.codeFont,
            .foregroundColor: UIColor(red: 0.17, green: 0.20, blue: 0.26, alpha: 1),
            .paragraphStyle: paragraphStyle,
        ], range: fullRange)
        applySyntaxHighlighting(to: result, in: fullRange)
        return result
    }

    private static func applySyntaxHighlighting(to text: NSMutableAttributedString, in fullRange: NSRange) {
        let source = text.string
        let patterns: [(String, UIColor)] = [
            (#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, UIColor(red: 0.55, green: 0.38, blue: 0.05, alpha: 1)),
            (#"//.*|/\*[\s\S]*?\*/"#, UIColor(red: 0.42, green: 0.47, blue: 0.53, alpha: 1)),
            (#"\b(const|let|var|func|function|return|if|else|for|while|switch|case|struct|class|enum|import|using|namespace|int|void|true|false|null|nil|try|catch|throw|throws|async|await|public|private|static|final)\b"#, UIColor(red: 0.68, green: 0.18, blue: 0.36, alpha: 1)),
            (#"\b\d+(?:\.\d+)?\b"#, UIColor(red: 0.72, green: 0.34, blue: 0.08, alpha: 1)),
            (#"\b([A-Za-z_][A-Za-z0-9_]*)\s*(?=\()"#, UIColor(red: 0.06, green: 0.39, blue: 0.67, alpha: 1)),
            (#"\.([A-Za-z_][A-Za-z0-9_]*)\b"#, UIColor(red: 0.14, green: 0.46, blue: 0.34, alpha: 1)),
        ]

        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            regex.enumerateMatches(in: source, range: fullRange) { match, _, _ in
                guard let matchRange = match?.range, matchRange.location != NSNotFound else { return }
                text.addAttribute(.foregroundColor, value: color, range: matchRange)
            }
        }
    }

    private static func measure(code: String, font: UIFont, config: NativeRenderConfig) -> (contentWidth: CGFloat, contentHeight: CGFloat) {
        let lines = code.components(separatedBy: .newlines)
        let lineSpacing = max(3, config.defaultLineSpacing - 2)
        let lineHeight = ceil(font.lineHeight + lineSpacing)
        let lineCount = max(lines.count, 1)
        let maxLineWidth = lines
            .map { ($0.isEmpty ? " " : $0) as NSString }
            .map { $0.size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let contentWidth = ceil(maxLineWidth)
        let contentHeight = ceil(CGFloat(lineCount) * lineHeight) + Metrics.verticalPadding * 2
        return (contentWidth, max(contentHeight, 54))
    }
}
