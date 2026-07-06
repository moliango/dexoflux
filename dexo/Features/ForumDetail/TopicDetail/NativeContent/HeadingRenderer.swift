import UIKit
import CookedHTML

enum HeadingRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .heading = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .heading(let level, let inlines) = block else { return UIView() }

        if level == 1, let tagText = tagLikeHeadingText(from: inlines) {
            return HeadingTagBadgeView(text: tagText, color: TopicTagVisualStyle.color(for: tagText))
        }

        let baseSize = config.baseFont.pointSize
        let fontSize: CGFloat
        let weight: UIFont.Weight
        switch level {
        case 1: fontSize = baseSize + 6; weight = .bold
        case 2: fontSize = baseSize + 5; weight = .bold
        case 3: fontSize = baseSize + 4; weight = .semibold
        case 4: fontSize = baseSize + 2; weight = .semibold
        case 5: fontSize = baseSize + 1; weight = .semibold
        default: fontSize = baseSize; weight = .medium
        }

        let headingConfig = NativeRenderConfig(
            baseFont: .systemFont(ofSize: fontSize, weight: weight),
            baseColor: config.baseColor,
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: config.contentWidth,
            baseURL: config.baseURL
        )

        let attributedText = headingConfig.styledAttributedString(
            from: inlines,
            lineSpacing: 2,
            paragraphSpacing: 8
        )
        let textView = makeTextView(attributedText: attributedText, config: config)
        return HeadingBlockView(level: level, textView: textView)
    }

    private static func makeTextView(attributedText: NSAttributedString, config: NativeRenderConfig) -> LinkTextView {
        let textView = LinkTextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.dataDetectorTypes = []
        textView.attributedText = attributedText
        textView.linkTextAttributes = [
            .foregroundColor: config.linkColor,
        ]
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }

    private static func tagLikeHeadingText(from inlines: [InlineNode]) -> String? {
        let text = plainText(from: inlines)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        guard !text.isEmpty, text.count <= 18 else { return nil }
        guard text.rangeOfCharacter(from: CharacterSet.newlines) == nil else { return nil }
        let punctuation = CharacterSet(charactersIn: ".,;:!?，。；：！？、()（）[]【】")
        guard text.rangeOfCharacter(from: punctuation) == nil else { return nil }
        return text
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
                return text
            case .image(_, let alt, _, _, _):
                return alt ?? ""
            case .lineBreak:
                return "\n"
            }
        }
        .joined()
    }
}

private final class HeadingBlockView: UIView {
    init(level: Int, textView: UIView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        TopicDetailContentStyle.applySurface(
            to: self,
            backgroundColor: level <= 2 ? TopicDetailContentStyle.mutedBackground : .clear,
            cornerRadius: level <= 2 ? 14 : 0,
            borderAlpha: level <= 2 ? 0.20 : 0
        )

        let accent = UIView()
        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.backgroundColor = TopicDetailContentStyle.headingAccentColor(for: level)
        accent.layer.cornerRadius = 2
        accent.layer.cornerCurve = .continuous

        addSubview(accent)
        addSubview(textView)

        let topPadding: CGFloat = level <= 2 ? 10 : 4
        let bottomPadding: CGFloat = level <= 2 ? 10 : 4
        let sidePadding: CGFloat = level <= 2 ? 12 : 0

        NSLayoutConstraint.activate([
            accent.leadingAnchor.constraint(equalTo: leadingAnchor, constant: sidePadding),
            accent.topAnchor.constraint(equalTo: topAnchor, constant: topPadding + 2),
            accent.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(bottomPadding + 2)),
            accent.widthAnchor.constraint(equalToConstant: 4),

            textView.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
            textView.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 10),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(sidePadding == 0 ? 0 : sidePadding)),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -bottomPadding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class HeadingTagBadgeView: UIView {
    init(text: String, color: UIColor) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = color.withAlphaComponent(0.10)
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = color.withAlphaComponent(0.22).cgColor

        let iconView = UIImageView(image: UIImage(systemName: "tag.fill"))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = color
        iconView.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = color
        label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 14, weight: .semibold)
        )
        label.adjustsFontForContentSizeCategory = true

        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
