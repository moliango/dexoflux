import CookedHTML
import UIKit

enum DetailsRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        guard case .details(_, let content) = block else { return false }
        return NativeContentRenderer.canRenderNatively(content)
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .details(let summary, let content) = block else { return UIView() }
        return DetailsCardView(summary: summary, content: content, config: config, delegate: delegate)
    }
}

// MARK: - DetailsCardView

private class DetailsCardView: UIView {
    private let chevron = UIImageView()
    private let headerView = UIView()
    private let dividerView = UIView()
    private var contentStack: UIStackView?
    private var isExpanded = false
    private var headerBottomConstraint: NSLayoutConstraint!
    private var contentBottomConstraint: NSLayoutConstraint?

    private var contentBlocks: [ContentBlock] = []
    private var innerConfig: NativeRenderConfig!
    private weak var delegate: PostCellDelegate?

    init(summary: [InlineNode], content: [ContentBlock], config: NativeRenderConfig, delegate: PostCellDelegate?) {
        self.contentBlocks = content
        self.delegate = delegate
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.cornerRadius = 0
        layer.borderWidth = 0
        clipsToBounds = true

        innerConfig = NativeRenderConfig(
            baseFont: config.baseFont,
            baseColor: config.baseColor,
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor,
            contentWidth: max(config.contentWidth - 16, 0),
            baseURL: config.baseURL,
            postId: config.postId,
            galleryImageURLs: config.galleryImageURLs
        )

        // MARK: Header

        chevron.image = UIImage(systemName: "chevron.right")
        chevron.tintColor = AppSettings.shared.themeStyle.accentColor
        chevron.contentMode = .scaleAspectFit
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let summaryLabel = UILabel()
        summaryLabel.numberOfLines = 0
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        let summaryConfig = AttributedStringConfig(
            baseFont: config.baseFont.bold(),
            baseColor: config.baseColor,
            linkColor: config.linkColor,
            codeFont: config.codeFont,
            codeBackgroundColor: config.codeBackgroundColor
        )
        let summaryText = NSMutableAttributedString(attributedString: summary.attributedString(config: summaryConfig))
        if summaryText.length > 0 {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            summaryText.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: summaryText.length))
        }
        summaryLabel.attributedText = summaryText

        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.backgroundColor = TopicDetailContentStyle.warmMutedBackground.withAlphaComponent(0.52)
        headerView.layer.cornerRadius = 10
        headerView.layer.cornerCurve = .continuous

        let accentBar = UIView()
        accentBar.backgroundColor = AppSettings.shared.themeStyle.hotTopicColor.withAlphaComponent(0.90)
        accentBar.layer.cornerRadius = 1.5
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(chevron)
        headerView.addSubview(summaryLabel)
        headerView.addSubview(accentBar)
        addSubview(headerView)

        dividerView.translatesAutoresizingMaskIntoConstraints = false
        dividerView.backgroundColor = UIColor.separator.withAlphaComponent(0.22)
        dividerView.isHidden = true
        addSubview(dividerView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleExpanded))
        headerView.addGestureRecognizer(tap)

        headerBottomConstraint = headerView.bottomAnchor.constraint(equalTo: bottomAnchor)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBottomConstraint,

            dividerView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            dividerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dividerView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

            accentBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            accentBar.topAnchor.constraint(equalTo: headerView.topAnchor),
            accentBar.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
            accentBar.widthAnchor.constraint(equalToConstant: 4),

            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
            chevron.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 12),
            chevron.centerYAnchor.constraint(equalTo: summaryLabel.centerYAnchor),

            summaryLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            summaryLabel.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 8),
            summaryLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            summaryLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()

        if isExpanded {
            // Lazily create and add the content stack
            if contentStack == nil {
                let stack = UIStackView()
                stack.axis = .vertical
                stack.spacing = 6
                stack.translatesAutoresizingMaskIntoConstraints = false
                addSubview(stack)

                let views = NativeContentRenderer.renderBlocks(contentBlocks, config: innerConfig, delegate: delegate)
                for view in views {
                    stack.addArrangedSubview(view)
                }

                NSLayoutConstraint.activate([
                    stack.topAnchor.constraint(equalTo: dividerView.bottomAnchor, constant: 10),
                    stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                    stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                ])

                contentBottomConstraint = stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
                contentStack = stack
            }

            contentStack?.isHidden = false
            dividerView.isHidden = false
            headerBottomConstraint.isActive = false
            contentBottomConstraint?.isActive = true
        } else {
            contentBottomConstraint?.isActive = false
            headerBottomConstraint.isActive = true
            contentStack?.isHidden = true
            dividerView.isHidden = true
        }

        chevron.transform = isExpanded ? CGAffineTransform(rotationAngle: .pi / 2) : .identity

        invalidateIntrinsicContentSize()
        if let tableView = findTableView() {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    private func findTableView() -> UITableView? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let tv = next as? UITableView { return tv }
            responder = next
        }
        return nil
    }
}

// MARK: - UIFont + Bold Helper

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
