import UIKit

/// 对齐 FluxDo `editor_tools.dart` 全量工具 + dexo 额外的 AI 预审。
enum ComposerMarkdownTool: CaseIterable {
    case image
    case attachment
    case media
    case heading
    case bold
    case italic
    case strikethrough
    case bulletList
    case numberedList
    case link
    case quote
    case callout
    case template
    case inlineCode
    case codeBlock
    case insertBlock
    case spoiler
    case imageGrid
    case aiReview

    var title: String {
        switch self {
        case .image: return String(localized: "reply.tool.image")
        case .attachment: return String(localized: "reply.tool.attachment")
        case .media: return "音视频"
        case .heading: return String(localized: "reply.tool.heading")
        case .bold: return String(localized: "reply.tool.bold")
        case .italic: return String(localized: "reply.tool.italic")
        case .strikethrough: return String(localized: "reply.tool.strikethrough")
        case .bulletList: return String(localized: "reply.tool.bullet_list")
        case .numberedList: return String(localized: "reply.tool.numbered_list")
        case .link: return String(localized: "reply.tool.link")
        case .quote: return String(localized: "reply.tool.quote")
        case .callout: return String(localized: "reply.tool.note")
        case .template: return String(localized: "reply.tool.template")
        case .inlineCode: return "行内代码"
        case .codeBlock: return "代码块"
        case .insertBlock: return "插入块"
        case .spoiler: return "剧透"
        case .imageGrid: return "图片网格"
        case .aiReview: return String(localized: "reply.tool.ai_review", defaultValue: "AI 预审")
        }
    }

    var symbolName: String {
        switch self {
        case .image: return "photo"
        case .attachment: return "paperclip"
        case .media: return "film"
        case .heading: return "textformat.size"
        case .bold: return "bold"
        case .italic: return "italic"
        case .strikethrough: return "strikethrough"
        case .bulletList: return "list.bullet"
        case .numberedList: return "list.number"
        case .link: return "link"
        case .quote: return "quote.closing"
        case .callout: return "note.text"
        case .template: return "doc.on.clipboard"
        case .inlineCode: return "chevron.left.forwardslash.chevron.right"
        case .codeBlock: return "curlybraces"
        case .insertBlock: return "square.plus"
        case .spoiler: return "eye.slash"
        case .imageGrid: return "rectangle.grid.2x2"
        case .aiReview: return "sparkles"
        }
    }

    var closesPanelAfterAction: Bool {
        switch self {
        case .image, .attachment, .media, .heading, .callout, .template, .insertBlock, .aiReview:
            return false
        default:
            return true
        }
    }
}

final class ComposerToolPanelView: UIView {
    var onToolSelected: ((ComposerMarkdownTool) -> Void)?

    var isUploading = false {
        didSet {
            toolButtons.forEach { button in
                guard let tool = toolByButton[button] else { return }
                let uploadTools: Set<ComposerMarkdownTool> = [.image, .attachment, .media]
                button.isEnabled = !isUploading || !uploadTools.contains(tool)
                button.alpha = button.isEnabled ? 1 : 0.45
            }
        }
    }

    private var isCustomizing = false
    private var toolButtons: [UIButton] = []
    private var toolByButton: [UIButton: ComposerMarkdownTool] = [:]

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .secondaryLabel
        label.text = String(localized: "reply.more_tools")
        return label
    }()

    private let customizeButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = String(localized: "reply.customize")
        config.baseForegroundColor = UIColor(red: 0.18, green: 0.42, blue: 0.62, alpha: 1)
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        return scroll
    }()

    private let gridStackView: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        addSubview(titleLabel)
        addSubview(customizeButton)
        addSubview(scrollView)
        scrollView.addSubview(gridStackView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),

            customizeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            customizeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -34),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            gridStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            gridStackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 28),
            gridStackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -28),
            gridStackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -4),
        ])

        customizeButton.addTarget(self, action: #selector(customizeTapped), for: .touchUpInside)
        buildGrid()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildGrid() {
        let tools = ComposerMarkdownTool.allCases
        let columns = 4
        let rowCount = Int(ceil(Double(tools.count) / Double(columns)))
        for rowIndex in 0 ..< rowCount {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .center
            row.distribution = .fillEqually
            row.spacing = 8
            gridStackView.addArrangedSubview(row)

            for column in 0 ..< columns {
                let index = rowIndex * columns + column
                if tools.indices.contains(index) {
                    row.addArrangedSubview(makeToolButton(tools[index]))
                } else {
                    let spacer = UIView()
                    spacer.isUserInteractionEnabled = false
                    row.addArrangedSubview(spacer)
                }
            }
        }
    }

    private func makeToolButton(_ tool: ComposerMarkdownTool) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: tool.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold))
        config.imagePlacement = .top
        config.imagePadding = 6
        config.title = tool.title
        config.baseForegroundColor = .label
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var updated = attrs
            updated.font = .systemFont(ofSize: 12, weight: .regular)
            return updated
        }
        config.background.backgroundColor = .clear

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 58).isActive = true
        button.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
        toolButtons.append(button)
        toolByButton[button] = tool
        return button
    }

    @objc private func toolTapped(_ sender: UIButton) {
        guard !isCustomizing, let tool = toolByButton[sender] else { return }
        onToolSelected?(tool)
    }

    @objc private func customizeTapped() {
        isCustomizing.toggle()
        var config = customizeButton.configuration
        config?.title = isCustomizing ? String(localized: "common.done") : String(localized: "reply.customize")
        customizeButton.configuration = config
        toolButtons.forEach { button in
            button.transform = isCustomizing ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            button.alpha = isCustomizing ? 0.7 : 1
        }
    }
}

final class ComposerMarkdownPreviewView: UIView {
    private let textView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isEditable = false
        tv.isScrollEnabled = true
        tv.backgroundColor = .systemBackground
        tv.textContainerInset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        tv.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 23, weight: .regular))
        tv.adjustsFontForContentSizeCategory = true
        return tv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(markdown: String) {
        textView.attributedText = Self.render(markdown)
    }

    private static func render(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 12

        let bodyFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 23, weight: .regular))
        let headingFont = UIFontMetrics(forTextStyle: .title2).scaledFont(for: .systemFont(ofSize: 30, weight: .bold))
        let monoFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 20, weight: .regular))

        var inCodeBlock = false
        for rawLine in markdown.components(separatedBy: .newlines) {
            var line = rawLine
            var attributes: [NSAttributedString.Key: Any] = [
                .font: bodyFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph,
            ]

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }

            if inCodeBlock {
                attributes[.font] = monoFont
                attributes[.foregroundColor] = UIColor.secondaryLabel
                attributes[.backgroundColor] = UIColor.secondarySystemGroupedBackground
            } else if line.hasPrefix("### ") {
                line.removeFirst(4)
                attributes[.font] = headingFont.withSize(24)
            } else if line.hasPrefix("## ") {
                line.removeFirst(3)
                attributes[.font] = headingFont.withSize(27)
            } else if line.hasPrefix("# ") {
                line.removeFirst(2)
                attributes[.font] = headingFont
            } else if line.hasPrefix("> ") {
                line.removeFirst(2)
                attributes[.foregroundColor] = UIColor.secondaryLabel
            } else if line.hasPrefix("- ") {
                line = "• " + String(line.dropFirst(2))
            }

            result.append(renderInline(line, attributes: attributes))
            result.append(NSAttributedString(string: "\n", attributes: attributes))
        }

        if result.length == 0 {
            return NSAttributedString(
                string: String(localized: "reply.preview.empty"),
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: UIColor.placeholderText,
                    .paragraphStyle: paragraph,
                ]
            )
        }
        return result
    }

    private static func renderInline(_ line: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: line, attributes: attributes)
        applyInline(regex: "\\*\\*(.+?)\\*\\*", in: attributed, fontWeight: .bold, markerLength: 2)
        applyInline(regex: "~~(.+?)~~", in: attributed, strikethrough: true, markerLength: 2)
        applyInline(regex: "`(.+?)`", in: attributed, monospace: true, markerLength: 1)
        return attributed
    }

    private static func applyInline(
        regex pattern: String,
        in attributed: NSMutableAttributedString,
        fontWeight: UIFont.Weight? = nil,
        strikethrough: Bool = false,
        monospace: Bool = false,
        markerLength: Int
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: attributed.string, range: NSRange(location: 0, length: attributed.length)).reversed()
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let contentRange = match.range(at: 1)
            let fullRange = match.range(at: 0)
            if let fontWeight {
                let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 23, weight: fontWeight))
                attributed.addAttribute(.font, value: font, range: contentRange)
            }
            if strikethrough {
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            }
            if monospace {
                let font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 20, weight: .regular))
                attributed.addAttribute(.font, value: font, range: contentRange)
            }
            attributed.deleteCharacters(in: NSRange(location: fullRange.location + fullRange.length - markerLength, length: markerLength))
            attributed.deleteCharacters(in: NSRange(location: fullRange.location, length: markerLength))
        }
    }
}
