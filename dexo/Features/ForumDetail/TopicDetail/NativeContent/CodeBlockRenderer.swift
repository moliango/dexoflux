import UIKit
import CookedHTML

enum CodeBlockRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .codeBlock = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .codeBlock(let language, let code) = block else { return UIView() }
        if let diagram = MermaidFlowchartParser.parse(language: language, code: code) {
            return MermaidFlowchartView(diagram: diagram, config: config)
        }
        return MacStyleCodeBlockView(language: language, code: code, config: config)
    }
}

struct CodeBlockThemePalette {
    let background: UIColor
    let foreground: UIColor
    let border: UIColor
    let string: UIColor
    let comment: UIColor
    let keyword: UIColor
    let number: UIColor
    let function: UIColor
    let property: UIColor

    static func palette(for interfaceStyle: UIUserInterfaceStyle) -> CodeBlockThemePalette {
        if interfaceStyle == .dark {
            return CodeBlockThemePalette(
                background: .black,
                foreground: UIColor(red: 0.86, green: 0.88, blue: 0.92, alpha: 1),
                border: UIColor.white.withAlphaComponent(0.16),
                string: UIColor(red: 0.95, green: 0.73, blue: 0.38, alpha: 1),
                comment: UIColor(red: 0.55, green: 0.60, blue: 0.67, alpha: 1),
                keyword: UIColor(red: 0.98, green: 0.42, blue: 0.63, alpha: 1),
                number: UIColor(red: 1.00, green: 0.62, blue: 0.30, alpha: 1),
                function: UIColor(red: 0.38, green: 0.72, blue: 1.00, alpha: 1),
                property: UIColor(red: 0.39, green: 0.81, blue: 0.64, alpha: 1)
            )
        }

        return CodeBlockThemePalette(
            background: .white,
            foreground: UIColor(red: 0.17, green: 0.20, blue: 0.26, alpha: 1),
            border: UIColor.separator.withAlphaComponent(0.38),
            string: UIColor(red: 0.55, green: 0.38, blue: 0.05, alpha: 1),
            comment: UIColor(red: 0.42, green: 0.47, blue: 0.53, alpha: 1),
            keyword: UIColor(red: 0.68, green: 0.18, blue: 0.36, alpha: 1),
            number: UIColor(red: 0.72, green: 0.34, blue: 0.08, alpha: 1),
            function: UIColor(red: 0.06, green: 0.39, blue: 0.67, alpha: 1),
            property: UIColor(red: 0.14, green: 0.46, blue: 0.34, alpha: 1)
        )
    }

    static var dynamic: CodeBlockThemePalette {
        CodeBlockThemePalette(
            background: dynamicColor(\.background),
            foreground: dynamicColor(\.foreground),
            border: dynamicColor(\.border),
            string: dynamicColor(\.string),
            comment: dynamicColor(\.comment),
            keyword: dynamicColor(\.keyword),
            number: dynamicColor(\.number),
            function: dynamicColor(\.function),
            property: dynamicColor(\.property)
        )
    }

    private static func dynamicColor(_ keyPath: KeyPath<CodeBlockThemePalette, UIColor>) -> UIColor {
        UIColor { traitCollection in
            palette(for: traitCollection.userInterfaceStyle)[keyPath: keyPath]
        }
    }
}

private struct MermaidFlowchartDiagram {
    enum Direction {
        case topDown
        case leftRight
    }

    struct Node {
        let id: String
        var label: String
    }

    struct Edge {
        let from: String
        let to: String
        let label: String?
    }

    let direction: Direction
    let nodes: [Node]
    let edges: [Edge]
}

private enum MermaidFlowchartParser {
    private static let nodeIdPattern = #"[A-Za-z0-9_][A-Za-z0-9_.:-]*"#
    private static let shapePattern = #"\[\[.*?\]\]|\[\(.*?\)\]|\(\(.*?\)\)|\{.*?\}|\[.*?\]|\(.*?\)"#
    private static let edgePattern = #"-->|---|==>|-.->|--"#

    static func parse(language: String?, code: String) -> MermaidFlowchartDiagram? {
        let normalizedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let statements = code
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ";") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { statement in
                let lowercased = statement.lowercased()
                return !statement.isEmpty
                    && !statement.hasPrefix("%%")
                    && lowercased != "end"
                    && !lowercased.hasPrefix("subgraph ")
            }

        guard let header = statements.first?.lowercased() else { return nil }
        let isMermaid = normalizedLanguage == "mermaid" || normalizedLanguage == "mmd"
        let isFlowchart = header.hasPrefix("flowchart ") || header.hasPrefix("graph ")
        guard isMermaid || isFlowchart else { return nil }
        guard isFlowchart else { return nil }

        var nodes: [String: MermaidFlowchartDiagram.Node] = [:]
        var order: [String] = []
        var edges: [MermaidFlowchartDiagram.Edge] = []

        func upsertNode(id: String, label: String? = nil) {
            let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanId.isEmpty else { return }
            let cleanLabel = label.map(cleanLabel) ?? cleanId
            if var existing = nodes[cleanId] {
                if existing.label == existing.id, cleanLabel != cleanId {
                    existing.label = cleanLabel
                    nodes[cleanId] = existing
                }
                return
            }
            nodes[cleanId] = MermaidFlowchartDiagram.Node(id: cleanId, label: cleanLabel)
            order.append(cleanId)
        }

        for statement in statements.dropFirst() {
            let nodeDefs = nodeDefinitions(in: statement)
            for def in nodeDefs {
                upsertNode(id: def.id, label: def.label)
            }

            let parsedEdges = edgeDefinitions(in: statement)
            for edge in parsedEdges {
                upsertNode(id: edge.from)
                upsertNode(id: edge.to)
                edges.append(edge)
            }
        }

        let orderedNodes = order.compactMap { nodes[$0] }
        guard !orderedNodes.isEmpty else { return nil }

        let direction: MermaidFlowchartDiagram.Direction = header.contains(" lr") || header.contains(" rl") ? .leftRight : .topDown
        return MermaidFlowchartDiagram(direction: direction, nodes: orderedNodes, edges: edges)
    }

    private static func nodeDefinitions(in statement: String) -> [(id: String, label: String)] {
        let pattern = #"(\#(nodeIdPattern))\s*(\#(shapePattern))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = statement as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: statement, range: range).compactMap { match in
            guard match.numberOfRanges >= 3 else { return nil }
            let id = ns.substring(with: match.range(at: 1))
            let wrapped = ns.substring(with: match.range(at: 2))
            return (id, unwrapLabel(wrapped))
        }
    }

    private static func edgeDefinitions(in statement: String) -> [MermaidFlowchartDiagram.Edge] {
        let pattern = #"(\#(nodeIdPattern))\s*(?:\#(shapePattern))?\s*(?:\#(edgePattern))\s*(?:(?:\|([^|]+)\|)|(?:([^->.=|]+?)\s*(?:\#(edgePattern))))?\s*(\#(nodeIdPattern))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = statement as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: statement, range: range).compactMap { match in
            guard match.numberOfRanges >= 5 else { return nil }
            let from = ns.substring(with: match.range(at: 1))
            let to = ns.substring(with: match.range(at: 4))
            let pipeLabelRange = match.range(at: 2)
            let inlineLabelRange = match.range(at: 3)
            let label: String?
            if pipeLabelRange.location != NSNotFound {
                label = cleanLabel(ns.substring(with: pipeLabelRange))
            } else if inlineLabelRange.location != NSNotFound {
                label = cleanLabel(ns.substring(with: inlineLabelRange))
            } else {
                label = nil
            }
            return MermaidFlowchartDiagram.Edge(from: from, to: to, label: label)
        }
    }

    private static func unwrapLabel(_ value: String) -> String {
        let pairs: [(String, String)] = [
            ("[[", "]]"),
            ("[(", ")]"),
            ("((", "))"),
            ("{", "}"),
            ("[", "]"),
            ("(", ")"),
        ]
        for (prefix, suffix) in pairs where value.hasPrefix(prefix) && value.hasSuffix(suffix) {
            let start = value.index(value.startIndex, offsetBy: prefix.count)
            let end = value.index(value.endIndex, offsetBy: -suffix.count)
            return cleanLabel(String(value[start ..< end]))
        }
        return cleanLabel(value)
    }

    private static func cleanLabel(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class MermaidFlowchartView: UIView {
    private enum Metrics {
        static let maxViewportHeight: CGFloat = 520
        static let minViewportHeight: CGFloat = 118
        static let nodeHorizontalPadding: CGFloat = 14
        static let nodeVerticalPadding: CGFloat = 11
    }

    init(diagram: MermaidFlowchartDiagram, config: NativeRenderConfig) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.withAlphaComponent(0.30).cgColor
        clipsToBounds = true

        let trafficStack = UIStackView(arrangedSubviews: [
            MacStyleCodeBlockView.makeTrafficDot(color: .systemRed),
            MacStyleCodeBlockView.makeTrafficDot(color: .systemYellow),
            MacStyleCodeBlockView.makeTrafficDot(color: .systemGreen),
        ])
        trafficStack.translatesAutoresizingMaskIntoConstraints = false
        trafficStack.axis = .horizontal
        trafficStack.spacing = 6
        trafficStack.alignment = .center

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Mermaid Flowchart"
        titleLabel.font = TopicDetailTypography.interfaceFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabel

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = diagram.direction == .leftRight
        scrollView.alwaysBounceVertical = false
        scrollView.backgroundColor = .clear

        let stack = diagram.direction == .leftRight
            ? makeHorizontalStack(diagram: diagram, config: config)
            : makeVerticalStack(diagram: diagram, config: config)
        scrollView.addSubview(stack)

        addSubview(trafficStack)
        addSubview(titleLabel)
        addSubview(scrollView)

        let estimatedHeight = estimateHeight(for: diagram)
        let viewportHeight = min(max(estimatedHeight, Metrics.minViewportHeight), Metrics.maxViewportHeight)

        NSLayoutConstraint.activate([
            trafficStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            trafficStack.topAnchor.constraint(equalTo: topAnchor, constant: 13),

            titleLabel.centerYAnchor.constraint(equalTo: trafficStack.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: trafficStack.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

            scrollView.topAnchor.constraint(equalTo: trafficStack.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            scrollView.heightAnchor.constraint(equalToConstant: viewportHeight),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        ])

        if diagram.direction == .topDown {
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor).isActive = true
        } else {
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeVerticalStack(diagram: MermaidFlowchartDiagram, config: NativeRenderConfig) -> UIStackView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill

        let orderedNodes = orderedNodes(for: diagram)
        for (index, node) in orderedNodes.enumerated() {
            stack.addArrangedSubview(makeNodeView(node, config: config))
            if index < orderedNodes.count - 1 {
                let edge = edgeBetween(orderedNodes[index], orderedNodes[index + 1], in: diagram)
                stack.addArrangedSubview(makeArrowView(symbol: "arrow.down", label: edge?.label, config: config))
            }
        }
        return stack
    }

    private func makeHorizontalStack(diagram: MermaidFlowchartDiagram, config: NativeRenderConfig) -> UIStackView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        let orderedNodes = orderedNodes(for: diagram)
        for (index, node) in orderedNodes.enumerated() {
            stack.addArrangedSubview(makeNodeView(node, config: config))
            if index < orderedNodes.count - 1 {
                let edge = edgeBetween(orderedNodes[index], orderedNodes[index + 1], in: diagram)
                stack.addArrangedSubview(makeArrowView(symbol: "arrow.right", label: edge?.label, config: config))
            }
        }
        return stack
    }

    private func makeNodeView(_ node: MermaidFlowchartDiagram.Node, config: NativeRenderConfig) -> UIView {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = config.baseFont
        label.textColor = .label
        label.text = node.label.isEmpty ? node.id : node.label

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = AppSettings.shared.themeStyle.topicChipBackgroundColor.withAlphaComponent(0.92)
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1.0 / UIScreen.main.scale
        container.layer.borderColor = AppSettings.shared.themeStyle.accentColor.withAlphaComponent(0.20).cgColor
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.nodeVerticalPadding),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.nodeHorizontalPadding),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.nodeHorizontalPadding),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Metrics.nodeVerticalPadding),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),
        ])
        return container
    }

    private func makeArrowView(symbol: String, label: String?, config: NativeRenderConfig) -> UIView {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center

        let imageView = UIImageView(image: UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)))
        imageView.tintColor = AppSettings.shared.themeStyle.accentColor.withAlphaComponent(0.78)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(imageView)

        if let label, !label.isEmpty {
            let textLabel = UILabel()
            textLabel.font = TopicDetailTypography.interfaceFont(ofSize: max(config.baseFont.pointSize - 3, 10), weight: .medium)
            textLabel.textColor = .secondaryLabel
            textLabel.text = label
            textLabel.numberOfLines = 0
            textLabel.textAlignment = .center
            stack.addArrangedSubview(textLabel)
        }
        return stack
    }

    private func orderedNodes(for diagram: MermaidFlowchartDiagram) -> [MermaidFlowchartDiagram.Node] {
        guard let firstEdge = diagram.edges.first else { return diagram.nodes }
        var orderedIds: [String] = [firstEdge.from]
        var current = firstEdge.from
        var usedEdges = Set<Int>()

        while let next = diagram.edges.enumerated().first(where: { index, edge in
            edge.from == current && !usedEdges.contains(index)
        }) {
            usedEdges.insert(next.offset)
            orderedIds.append(next.element.to)
            current = next.element.to
        }

        for node in diagram.nodes where !orderedIds.contains(node.id) {
            orderedIds.append(node.id)
        }
        return orderedIds.compactMap { id in diagram.nodes.first(where: { $0.id == id }) }
    }

    private func edgeBetween(
        _ from: MermaidFlowchartDiagram.Node,
        _ to: MermaidFlowchartDiagram.Node,
        in diagram: MermaidFlowchartDiagram
    ) -> MermaidFlowchartDiagram.Edge? {
        diagram.edges.first { $0.from == from.id && $0.to == to.id }
    }

    private func estimateHeight(for diagram: MermaidFlowchartDiagram) -> CGFloat {
        guard diagram.direction == .topDown else { return 180 }
        let nodeCount = CGFloat(max(diagram.nodes.count, 1))
        let arrowCount = CGFloat(max(diagram.nodes.count - 1, 0))
        return nodeCount * 72 + arrowCount * 28
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
    private let scrollView = UIScrollView()
    private var resetCopyIconWorkItem: DispatchWorkItem?
    private var hideCopyButtonWorkItem: DispatchWorkItem?

    init(language: String?, code: String, config: NativeRenderConfig) {
        self.code = code
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let palette = CodeBlockThemePalette.dynamic
        backgroundColor = palette.background
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.borderColor = palette.border.resolvedColor(with: traitCollection).cgColor
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

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.backgroundColor = .clear
        updateTraitDependentColors()

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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.hasDifferentColorAppearance(comparedTo: traitCollection) != false else { return }
        updateTraitDependentColors()
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

    private func updateTraitDependentColors() {
        let palette = CodeBlockThemePalette.palette(for: traitCollection.userInterfaceStyle)
        layer.borderColor = palette.border.cgColor
        scrollView.indicatorStyle = traitCollection.userInterfaceStyle == .dark ? .white : .default
    }

    fileprivate static func makeTrafficDot(color: UIColor) -> UIView {
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
        let palette = CodeBlockThemePalette.dynamic
        let result = NSMutableAttributedString(string: code.isEmpty ? " " : code)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = max(3, config.defaultLineSpacing - 2)
        paragraphStyle.minimumLineHeight = config.codeFont.lineHeight + paragraphStyle.lineSpacing
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes([
            .font: config.codeFont,
            .foregroundColor: palette.foreground,
            .paragraphStyle: paragraphStyle,
        ], range: fullRange)
        applySyntaxHighlighting(to: result, in: fullRange, palette: palette)
        return result
    }

    private static func applySyntaxHighlighting(
        to text: NSMutableAttributedString,
        in fullRange: NSRange,
        palette: CodeBlockThemePalette
    ) {
        let source = text.string
        let patterns: [(String, UIColor)] = [
            (#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, palette.string),
            (#"//.*|/\*[\s\S]*?\*/"#, palette.comment),
            (#"\b(const|let|var|func|function|return|if|else|for|while|switch|case|struct|class|enum|import|using|namespace|int|void|true|false|null|nil|try|catch|throw|throws|async|await|public|private|static|final)\b"#, palette.keyword),
            (#"\b\d+(?:\.\d+)?\b"#, palette.number),
            (#"\b([A-Za-z_][A-Za-z0-9_]*)\s*(?=\()"#, palette.function),
            (#"\.([A-Za-z_][A-Za-z0-9_]*)\b"#, palette.property),
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
