import UIKit
import CookedHTML

enum BlockquoteRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        guard case .blockquote(let inner) = block else { return false }
        return NativeContentRenderer.canRenderNatively(inner)
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .blockquote(let inner) = block else { return UIView() }

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        TopicDetailContentStyle.applySurface(
            to: container,
            backgroundColor: TopicDetailContentStyle.warmMutedBackground,
            cornerRadius: 14,
            borderAlpha: 0.22
        )
        container.clipsToBounds = true

        let bar = UIView()
        bar.backgroundColor = AppSettings.shared.themeStyle.hotTopicColor.withAlphaComponent(0.70)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.layer.cornerRadius = 2
        container.addSubview(bar)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let quoteConfig = NativeRenderConfig(
            baseFont: config.baseFont,
            baseColor: UIColor.label.withAlphaComponent(0.82),
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: config.contentWidth - 32,
            baseURL: config.baseURL
        )

        let views = NativeContentRenderer.renderBlocks(inner, config: quoteConfig, delegate: delegate)
        for view in views {
            stack.addArrangedSubview(view)
        }

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            bar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            bar.widthAnchor.constraint(equalToConstant: 4),

            stack.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }
}
