import UIKit
import CookedHTML

enum ParagraphRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .paragraph = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .paragraph(let inlines) = block else { return UIView() }

        // Safety net: sole image/badge link that escaped parser promotion still becomes media.
        if let mediaView = renderSoleMediaIfNeeded(inlines: inlines, config: config, delegate: delegate) {
            return mediaView
        }

        let textView = LinkTextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.dataDetectorTypes = []
        textView.attributedText = config.styledAttributedString(from: inlines, paragraphSpacing: 0)
        // Inline taxonomy links carry their own server-derived color.
        textView.linkTextAttributes = [:]
        textView.preferredMeasurementWidth = config.contentWidth
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }

    private static func renderSoleMediaIfNeeded(
        inlines: [InlineNode],
        config: NativeRenderConfig,
        delegate: PostCellDelegate?
    ) -> UIView? {
        let trimmed = inlines.trimmedWhitespace()

        if trimmed.count == 1, case .link(let href, _) = trimmed[0] {
            return mediaView(for: href, config: config, delegate: delegate)
        }

        if let plainURL = ImageURLDetector.soleImageURL(fromPlainInlines: trimmed) {
            return mediaView(for: plainURL, config: config, delegate: delegate)
        }

        return nil
    }

    private static func mediaView(
        for href: String,
        config: NativeRenderConfig,
        delegate: PostCellDelegate?
    ) -> UIView? {
        guard ImageURLDetector.isImageURL(href) else { return nil }
        guard let url = URL(string: href) ?? URL(string: href.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? href) else {
            return nil
        }

        if let model = BadgeCardModel.parse(url: url) {
            let card = BadgeCardView(model: model, containerWidth: config.contentWidth)
            card.delegate = delegate
            return card
        }

        let container = TappableImageContainer(
            url: url,
            width: nil,
            height: nil,
            containerWidth: config.contentWidth,
            href: url,
            galleryImageURLs: config.galleryImageURLs,
            refererBaseURL: config.baseURL
        )
        container.delegate = delegate
        return container
    }
}
