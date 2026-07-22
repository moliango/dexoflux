import UIKit
import CookedHTML

enum BlockquoteRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        guard case .blockquote(let inner) = block else { return false }
        return NativeContentRenderer.canRenderNatively(inner)
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .blockquote(let inner) = block else { return UIView() }

        if let callout = ObsidianCallout.parse(from: inner) {
            return ObsidianCalloutView(callout: callout, config: config, delegate: delegate)
        }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = TopicDetailContentStyle.warmMutedBackground.withAlphaComponent(0.42)
        container.layer.cornerRadius = 0
        container.layer.borderWidth = 0
        container.clipsToBounds = true

        let bar = UIView()
        bar.backgroundColor = AppSettings.shared.themeStyle.hotTopicColor.withAlphaComponent(0.82)
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let quoteConfig = NativeRenderConfig(
            baseFont: config.baseFont,
            baseColor: UIColor.label.withAlphaComponent(0.82),
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: max(config.contentWidth - 18, 0),
            baseURL: config.baseURL,
            postId: config.postId,
            galleryImageURLs: config.galleryImageURLs,
            topicTagNames: config.topicTagNames,
            topicCategoryPresentation: config.topicCategoryPresentation
        )

        let views = NativeContentRenderer.renderBlocks(inner, config: quoteConfig, delegate: delegate)
        for view in views {
            stack.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 4),

            stack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        return container
    }
}

// MARK: - Obsidian Callout

private struct ObsidianCallout {
    let kind: String
    let title: String
    let content: [ContentBlock]
    let defaultExpanded: Bool

    static func parse(from blocks: [ContentBlock]) -> ObsidianCallout? {
        guard let first = blocks.first, case .paragraph(let inlines) = first else { return nil }

        let split = splitFirstLine(inlines)
        let markerLine = plainText(from: split.firstLine).trimmingCharacters(in: .whitespacesAndNewlines)
        guard markerLine.hasPrefix("[!") else { return nil }
        guard let closeIndex = markerLine.firstIndex(of: "]") else { return nil }

        let kindStart = markerLine.index(markerLine.startIndex, offsetBy: 2)
        let rawKind = String(markerLine[kindStart..<closeIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !rawKind.isEmpty else { return nil }

        var remainder = String(markerLine[markerLine.index(after: closeIndex)...])
        let marker = remainder.first
        let defaultExpanded: Bool
        if marker == "-" {
            defaultExpanded = false
            remainder.removeFirst()
        } else if marker == "+" {
            defaultExpanded = true
            remainder.removeFirst()
        } else {
            defaultExpanded = true
        }

        let title = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        var content = Array(blocks.dropFirst())
        let tail = split.remainingLines.trimmedWhitespace()
        if !tail.isEmpty {
            content.insert(.paragraph(tail), at: 0)
        }

        return ObsidianCallout(
            kind: rawKind,
            title: title.isEmpty ? rawKind.uppercased() : title,
            content: content,
            defaultExpanded: defaultExpanded
        )
    }

    var iconName: String {
        switch kind {
        case "note": return "pencil.and.outline"
        case "abstract", "summary", "tldr": return "text.justify.left"
        case "info": return "info.circle.fill"
        case "todo": return "checkmark.circle.fill"
        case "tip", "hint", "important": return "lightbulb.fill"
        case "success", "check", "done": return "checkmark.seal.fill"
        case "question", "help", "faq": return "questionmark.circle.fill"
        case "warning", "caution", "attention": return "exclamationmark.triangle.fill"
        case "failure", "fail", "missing": return "xmark.octagon.fill"
        case "danger", "error": return "flame.fill"
        case "bug": return "ladybug.fill"
        case "example": return "square.stack.3d.up.fill"
        case "quote", "cite": return "quote.opening"
        default: return "note.text"
        }
    }

    var accentColor: UIColor {
        switch kind {
        case "note": return AppSettings.shared.themeStyle.accentColor
        case "abstract", "summary", "tldr": return .systemTeal
        case "info": return .systemBlue
        case "todo", "success", "check", "done": return .systemGreen
        case "tip", "hint", "important": return .systemYellow
        case "question", "help", "faq": return .systemPurple
        case "warning", "caution", "attention": return .systemOrange
        case "failure", "fail", "missing", "danger", "error", "bug": return .systemRed
        case "example": return .systemIndigo
        case "quote", "cite": return .secondaryLabel
        default: return AppSettings.shared.themeStyle.hotTopicColor
        }
    }

    private static func splitFirstLine(_ inlines: [InlineNode]) -> (firstLine: [InlineNode], remainingLines: [InlineNode]) {
        guard let lineBreakIndex = inlines.firstIndex(where: {
            if case .lineBreak = $0 { return true }
            return false
        }) else {
            return (inlines, [])
        }

        let firstLine = Array(inlines[..<lineBreakIndex])
        let remainingStart = inlines.index(after: lineBreakIndex)
        return (firstLine, Array(inlines[remainingStart...]))
    }

    private static func plainText(from inlines: [InlineNode]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let text), .styledText(let text, _), .code(let text):
                return text
            case .link(_, let children), .spoiler(let children):
                return plainText(from: children)
            case .mention(let username, _):
                return "@\(username)"
            case .mentionGroup(let name, _):
                return "@\(name)"
            case .hashtag(let text, _, _):
                return "#\(text)"
            case .image(_, let alt, _, _, _):
                return alt ?? ""
            case .lineBreak:
                return "\n"
            }
        }
        .joined()
    }
}

private final class ObsidianCalloutView: UIView {
    private let callout: ObsidianCallout
    private let innerConfig: NativeRenderConfig
    private weak var delegate: PostCellDelegate?

    private let headerView = UIView()
    private let chevron = UIImageView()
    private let dividerView = UIView()
    private var contentStack: UIStackView?
    private var headerBottomConstraint: NSLayoutConstraint!
    private var contentBottomConstraint: NSLayoutConstraint?
    private var isExpanded: Bool

    init(callout: ObsidianCallout, config: NativeRenderConfig, delegate: PostCellDelegate?) {
        self.callout = callout
        self.delegate = delegate
        self.isExpanded = callout.defaultExpanded
        self.innerConfig = NativeRenderConfig(
            baseFont: config.baseFont,
            baseColor: config.baseColor,
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: max(config.contentWidth - 16, 0),
            baseURL: config.baseURL,
            postId: config.postId,
            galleryImageURLs: config.galleryImageURLs,
            topicTagNames: config.topicTagNames,
            topicCategoryPresentation: config.topicCategoryPresentation
        )
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        clipsToBounds = true

        let accentColor = callout.accentColor
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = accentColor.withAlphaComponent(0.12)
        headerView.layer.cornerRadius = 10
        headerView.layer.cornerCurve = .continuous
        addSubview(headerView)

        let accentBar = UIView()
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.backgroundColor = accentColor.withAlphaComponent(0.92)
        headerView.addSubview(accentBar)

        let iconView = UIImageView(image: UIImage(systemName: callout.iconName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = accentColor
        iconView.contentMode = .scaleAspectFit
        headerView.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 0
        titleLabel.text = callout.title
        titleLabel.textColor = config.baseColor
        titleLabel.font = config.baseFont.bold()
        headerView.addSubview(titleLabel)

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = accentColor
        chevron.contentMode = .scaleAspectFit
        headerView.addSubview(chevron)

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.backgroundColor = UIColor.separator.withAlphaComponent(0.20)
        dividerView.isHidden = !isExpanded
        addSubview(dividerView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleExpanded))
        headerView.addGestureRecognizer(tap)
        headerView.isAccessibilityElement = true
        headerView.accessibilityTraits = .button
        headerView.accessibilityLabel = callout.title

        headerBottomConstraint = headerView.bottomAnchor.constraint(equalTo: bottomAnchor)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            dividerView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dividerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dividerView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            accentBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: headerView.topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 4),

            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),
            iconView.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -10),

            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
            chevron.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])

        setExpanded(isExpanded, updateTable: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleExpanded() {
        setExpanded(!isExpanded, updateTable: true)
    }

    private func setExpanded(_ expanded: Bool, updateTable: Bool) {
        isExpanded = expanded

        if expanded, contentStack == nil, !callout.content.isEmpty {
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)

            let views = NativeContentRenderer.renderBlocks(callout.content, config: innerConfig, delegate: delegate)
            for view in views {
                stack.addArrangedSubview(view)
            }

            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: dividerView.bottomAnchor, constant: 8),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            ])

            contentBottomConstraint = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
            contentStack = stack
        }

        let hasContent = !(contentStack?.arrangedSubviews.isEmpty ?? true)
        contentStack?.isHidden = !expanded
        dividerView.isHidden = !expanded || !hasContent
        headerBottomConstraint.isActive = !expanded || !hasContent
        contentBottomConstraint?.isActive = expanded && hasContent
        chevron.isHidden = !hasContent
        chevron.transform = expanded && hasContent ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
        headerView.accessibilityValue = expanded && hasContent ? String(localized: "已展开") : String(localized: "已折叠")

        invalidateIntrinsicContentSize()
        guard updateTable, let tableView = findTableView() else { return }
        tableView.beginUpdates()
        tableView.endUpdates()
    }

    private func findTableView() -> UITableView? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let tableView = next as? UITableView { return tableView }
            responder = next
        }
        return nil
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
