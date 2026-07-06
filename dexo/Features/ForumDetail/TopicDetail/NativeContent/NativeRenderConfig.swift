import CookedHTML
import UIKit

struct NativeRenderConfig {
    let baseFont: UIFont
    let baseColor: UIColor
    let linkColor: UIColor
    let codeFont: UIFont
    let codeBackgroundColor: UIColor
    let contentWidth: CGFloat
    let baseURL: String?
    let defaultLineSpacing: CGFloat
    let defaultParagraphSpacing: CGFloat

    init(
        baseFont: UIFont,
        baseColor: UIColor,
        linkColor: UIColor,
        codeFont: UIFont,
        codeBackgroundColor: UIColor,
        contentWidth: CGFloat,
        baseURL: String?,
        defaultLineSpacing: CGFloat = 3,
        defaultParagraphSpacing: CGFloat = 6
    ) {
        self.baseFont = baseFont
        self.baseColor = baseColor
        self.linkColor = linkColor
        self.codeFont = codeFont
        self.codeBackgroundColor = codeBackgroundColor
        self.contentWidth = contentWidth
        self.baseURL = baseURL
        self.defaultLineSpacing = defaultLineSpacing
        self.defaultParagraphSpacing = defaultParagraphSpacing
    }

    var attributedStringConfig: AttributedStringConfig {
        AttributedStringConfig(
            baseFont: baseFont,
            baseColor: baseColor,
            linkColor: linkColor,
            codeFont: codeFont,
            codeBackgroundColor: codeBackgroundColor
        )
    }

    static func `default`(contentWidth: CGFloat, baseURL: String? = nil) -> NativeRenderConfig {
        let comfortMode = AppSettings.shared.readingComfortMode
        let bodyFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: comfortMode ? 19 : 18)
        )
        let codeFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(ofSize: comfortMode ? 18 : 17, weight: .regular)
        )
        return NativeRenderConfig(
            baseFont: bodyFont,
            baseColor: .label,
            linkColor: .link,
            codeFont: codeFont,
            codeBackgroundColor: .secondarySystemBackground,
            contentWidth: contentWidth,
            baseURL: baseURL,
            defaultLineSpacing: comfortMode ? 6 : 5,
            defaultParagraphSpacing: comfortMode ? 12 : 9
        )
    }

    func styledAttributedString(
        from inlines: [InlineNode],
        lineSpacing: CGFloat? = nil,
        paragraphSpacing: CGFloat? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: inlines.attributedString(config: attributedStringConfig))
        guard result.length > 0 else { return result }

        let lineSpacing = lineSpacing ?? defaultLineSpacing
        let paragraphSpacing = paragraphSpacing ?? defaultParagraphSpacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.minimumLineHeight = baseFont.lineHeight + lineSpacing
        result.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }
}

enum TopicDetailContentStyle {
    static var cardBackground: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor.white
        }
    }

    static var mutedBackground: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.tertiarySystemGroupedBackground
                : UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1)
        }
    }

    static var warmMutedBackground: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.tertiarySystemGroupedBackground
                : UIColor(red: 1.0, green: 0.98, blue: 0.94, alpha: 1)
        }
    }

    static func applySurface(
        to view: UIView,
        backgroundColor: UIColor? = nil,
        cornerRadius: CGFloat = 14,
        borderAlpha: CGFloat = 0.28
    ) {
        view.backgroundColor = backgroundColor ?? cardBackground
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.layer.borderColor = UIColor.separator.withAlphaComponent(borderAlpha).cgColor
    }

    static func headingAccentColor(for level: Int) -> UIColor {
        switch level {
        case 1:
            return .systemBlue
        case 2:
            return .systemIndigo
        case 3:
            return .systemTeal
        default:
            return .secondaryLabel
        }
    }
}

// MARK: - BlockRenderer Protocol

protocol BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool
    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView
}

// MARK: - NativeContentRenderer

enum NativeContentRenderer {
    static let renderers: [BlockRenderer.Type] = [
        ParagraphRenderer.self,
        HeadingRenderer.self,
        DividerRenderer.self,
        ListRenderer.self,
        BlockquoteRenderer.self,
        ImageRenderer.self,
        CodeBlockRenderer.self,
        DiscourseQuoteRenderer.self,
        DetailsRenderer.self,
        SpoilerRenderer.self,
        OneboxRenderer.self,
        VideoRenderer.self,
        TableRenderer.self,
    ]

    static func canRenderNatively(_ blocks: [ContentBlock]) -> Bool {
        blocks.allSatisfy { block in
            renderers.contains { $0.canRender(block) }
        }
    }

    static func renderBlocks(
        _ blocks: [ContentBlock],
        config: NativeRenderConfig,
        delegate: PostCellDelegate?
    ) -> [UIView] {
        blocks.compactMap { block in
            for renderer in renderers where renderer.canRender(block) {
                return renderer.render(block, config: config, delegate: delegate)
            }
            return nil
        }
    }

    static func renderBlocks(
        _ annotatedBlocks: [AnnotatedBlock],
        config: NativeRenderConfig,
        delegate: PostCellDelegate?
    ) -> [UIView] {
        annotatedBlocks.compactMap { annotated in
            for renderer in renderers where renderer.canRender(annotated.block) {
                return renderer.render(annotated.block, config: config, delegate: delegate)
            }
            // No native renderer — fall back to WebView snapshot
            return FallbackBlockView(
                html: annotated.sourceHTML,
                containerWidth: config.contentWidth,
                baseURL: config.baseURL ?? ""
            )
        }
    }
}
