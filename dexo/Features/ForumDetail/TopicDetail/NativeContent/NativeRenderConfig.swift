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
    let postId: Int?
    let galleryImageURLs: [URL]
    let topicTagNames: Set<String>
    let topicCategoryPresentation: TopicCategoryBadgePresentation?
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
        postId: Int? = nil,
        galleryImageURLs: [URL] = [],
        topicTagNames: Set<String> = [],
        topicCategoryPresentation: TopicCategoryBadgePresentation? = nil,
        defaultLineSpacing: CGFloat = 4,
        defaultParagraphSpacing: CGFloat = 5
    ) {
        self.baseFont = baseFont
        self.baseColor = baseColor
        self.linkColor = linkColor
        self.codeFont = codeFont
        self.codeBackgroundColor = codeBackgroundColor
        self.contentWidth = contentWidth
        self.baseURL = baseURL
        self.postId = postId
        self.galleryImageURLs = galleryImageURLs
        self.topicTagNames = topicTagNames
        self.topicCategoryPresentation = topicCategoryPresentation
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

    static func `default`(
        contentWidth: CGFloat,
        baseURL: String? = nil,
        postId: Int? = nil,
        galleryImageURLs: [URL] = [],
        topicTagNames: Set<String> = [],
        topicCategoryPresentation: TopicCategoryBadgePresentation? = nil
    ) -> NativeRenderConfig {
        let settings = AppSettings.shared
        let comfortMode = settings.readingComfortMode
        let themeStyle = settings.themeStyle
        let comfortFontDelta: CGFloat = comfortMode ? 1 : 0
        let basePointSize = settings.effectiveContentPointSize(
            for: settings.contentFontSize.basePointSize + comfortFontDelta
        )
        let bodyFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: settings.contentFont(ofSize: basePointSize)
        )
        let codeFont = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: settings.contentMonospacedFont(ofSize: max(basePointSize - 1, 1))
        )
        return NativeRenderConfig(
            baseFont: bodyFont,
            baseColor: .label,
            linkColor: themeStyle.accentColor,
            codeFont: codeFont,
            codeBackgroundColor: themeStyle.mutedContentBackgroundColor,
            contentWidth: contentWidth,
            baseURL: baseURL,
            postId: postId,
            galleryImageURLs: galleryImageURLs,
            topicTagNames: topicTagNames,
            topicCategoryPresentation: topicCategoryPresentation,
            defaultLineSpacing: comfortMode ? 3 : 2,
            defaultParagraphSpacing: comfortMode ? 5 : 3
        )
    }

    func styledAttributedString(
        from inlines: [InlineNode],
        lineSpacing: CGFloat? = nil,
        paragraphSpacing: CGFloat? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for inline in inlines {
            result.append(attributedString(for: inline))
        }
        guard result.length > 0 else { return result }

        let lineSpacing = lineSpacing ?? defaultLineSpacing
        let paragraphSpacing = paragraphSpacing ?? defaultParagraphSpacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.paragraphSpacing = paragraphSpacing
        result.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private func attributedString(for inline: InlineNode) -> NSAttributedString {
        let taxonomy: (text: String, href: String, type: String?)?
        switch inline {
        case .hashtag(let text, let href, let type):
            taxonomy = (text, href, type)
        case .link(let href, let children):
            let linkedText = plainText(from: children).trimmingCharacters(in: .whitespacesAndNewlines)
            guard linkedText.hasPrefix("#"), linkedText.count > 1 else {
                return inline.attributedString(config: attributedStringConfig)
            }
            let text = String(linkedText.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            let path = URL(string: href)?.path.lowercased() ?? href.lowercased()
            let type = path.contains("/c/") ? "category" : (path.contains("/tag/") ? "tag" : nil)
            taxonomy = (text, href, type)
        default:
            taxonomy = nil
        }
        guard let taxonomy else {
            return inline.attributedString(config: attributedStringConfig)
        }
        let (text, href, type) = taxonomy

        if HeadingPresentationPolicy.shouldRenderTagBadge(
            level: 1,
            text: text,
            topicTagNames: topicTagNames
        ) {
            let tagPresentation = TopicTagIconCatalog.presentation(for: text)
            return inlineTaxonomyString(
                text: text,
                href: href,
                iconName: tagPresentation?.iconName,
                textColor: TopicTagVisualStyle.color(for: text),
                iconColor: tagPresentation
                    .flatMap { TopicTaxonomyColor.resolve(hex: $0.colorHex) }
                    ?? TopicTagVisualStyle.color(for: text)
            )
        }

        if type?.lowercased() == "category",
           let category = topicCategoryPresentation,
           HeadingPresentationPolicy.shouldRenderCategoryBadge(
               level: 1,
               text: text,
               categoryName: category.name
           ) {
            let iconName: String?
            switch category.iconSource {
            case .fontAwesome(let name): iconName = name
            case .lock: iconName = "lock"
            case .logo, .dot: iconName = nil
            }
            return inlineTaxonomyString(
                text: text,
                href: href,
                iconName: iconName,
                textColor: linkColor,
                iconColor: linkColor
            )
        }

        return inline.attributedString(config: attributedStringConfig)
    }

    private func plainText(from inlines: [InlineNode]) -> String {
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
        }.joined()
    }

    private func inlineTaxonomyString(
        text: String,
        href: String,
        iconName: String?,
        textColor: UIColor,
        iconColor: UIColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        // Only emit FA PUA glyphs when the icon font actually loads.
        // Falling back to the body font turns private-use codepoints into
        // random CJK tofu that sits on top of the post body ("掩盖").
        if let iconName,
           let glyph = DiscourseFontAwesomeIcon.glyph(for: iconName),
           let iconFont = UIFont(
               name: DiscourseFontAwesomeIcon.fontName,
               size: max(baseFont.pointSize - 1, 1)
           ) {
            result.append(NSAttributedString(
                string: "\(glyph) ",
                attributes: [
                    .font: iconFont,
                    .foregroundColor: iconColor,
                ]
            ))
        }
        let linkedTextStart = result.length
        result.append(NSAttributedString(
            string: text,
            attributes: [
                .font: baseFont.weighted(.semibold),
                .foregroundColor: textColor,
            ]
        ))
        result.addAttribute(
            .link,
            value: href,
            range: NSRange(location: linkedTextStart, length: result.length - linkedTextStart)
        )
        return result
    }
}

enum TopicDetailContentStyle {
    static var cardBackground: UIColor {
        AppSettings.shared.themeStyle.contentBackgroundColor
    }

    static var mutedBackground: UIColor {
        AppSettings.shared.themeStyle.mutedContentBackgroundColor
    }

    static var warmMutedBackground: UIColor {
        let style = AppSettings.shared.themeStyle
        if style != .systemDefault {
            return style.mutedContentBackgroundColor
        }
        return UIColor { trait in
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
        let style = AppSettings.shared.themeStyle
        guard style == .systemDefault else { return style.accentColor }
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
        PollRenderer.self,
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

enum PollRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .poll = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        guard case .poll(let poll) = block else { return UIView() }
        return PollBlockView(poll: poll, config: config, delegate: delegate)
    }
}

private final class PollBlockView: UIView {
    private let poll: PollBlock
    private let config: NativeRenderConfig
    private weak var delegate: PostCellDelegate?
    private var selectedOptionIds: Set<String>
    private var optionControls: [PollOptionControl] = []
    private weak var submitButton: UIButton?
    private var isSubmitting = false

    private var isOpen: Bool {
        let status = poll.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return status == nil || status == "open"
    }

    private var minSelections: Int {
        max(1, poll.minSelections ?? 1)
    }

    private var maxSelections: Int {
        max(minSelections, poll.maxSelections ?? 1)
    }

    private var canSubmitVote: Bool {
        isOpen && config.postId != nil && poll.name != nil && poll.options.contains { $0.id != nil }
    }

    init(poll: PollBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) {
        self.poll = poll
        self.config = config
        self.delegate = delegate
        self.selectedOptionIds = Set(poll.options.compactMap { option in
            option.isSelected ? option.id : nil
        })
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        TopicDetailContentStyle.applySurface(
            to: self,
            backgroundColor: TopicDetailContentStyle.mutedBackground,
            cornerRadius: 16,
            borderAlpha: 0.2
        )

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])

        stack.addArrangedSubview(makeHeader())
        for option in poll.options {
            let control = PollOptionControl(option: option, config: config)
            control.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            optionControls.append(control)
            stack.addArrangedSubview(control)
        }
        if let votersText = votersDisplayText() {
            stack.addArrangedSubview(makeVotersLabel(votersText))
        }
        if canSubmitVote {
            let button = makeSubmitButton()
            submitButton = button
            stack.addArrangedSubview(button)
        }
        updateOptionStates()

        accessibilityLabel = [String(localized: "post.poll"), votersDisplayText()]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    private func makeHeader() -> UIView {
        let accentColor = AppSettings.shared.themeStyle.accentColor

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: "chart.bar.fill"))
        iconView.tintColor = accentColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = String(localized: "post.poll")
        titleLabel.font = config.baseFont.weighted(.semibold)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let statusLabel = UILabel()
        statusLabel.text = headerStatusText()
        statusLabel.font = config.baseFont.withRelativeSize(-1).weighted(.semibold)
        statusLabel.textColor = accentColor
        statusLabel.textAlignment = .right
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -8),

            statusLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    private func makeVotersLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = config.baseFont.withRelativeSize(-1).weighted(.medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeSubmitButton() -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = selectedOptionIds.isEmpty ? String(localized: "post.poll.submit") : String(localized: "post.poll.update")
        configuration.baseBackgroundColor = AppSettings.shared.themeStyle.accentColor
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16)

        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = TopicDetailTypography.interfaceFont(ofSize: 14, weight: .semibold)
        button.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func headerStatusText() -> String? {
        if isOpen {
            return votersDisplayText()
        }
        return String(localized: "post.poll.closed")
    }

    private func votersDisplayText() -> String? {
        if let count = poll.votersCount {
            return String(format: String(localized: "post.poll.voters_count"), count)
        }
        return poll.votersText
    }

    private func updateOptionStates() {
        let accentColor = AppSettings.shared.themeStyle.accentColor
        for control in optionControls {
            let optionId = control.option.id
            let isSelected = optionId.map { selectedOptionIds.contains($0) } ?? false
            control.apply(isSelected: isSelected, canVote: canSubmitVote && !isSubmitting, accentColor: accentColor)
        }

        guard var configuration = submitButton?.configuration else { return }
        configuration.title = selectedOptionIds.isEmpty ? String(localized: "post.poll.submit") : String(localized: "post.poll.update")
        submitButton?.configuration = configuration
        submitButton?.isEnabled = canSubmitVote && !isSubmitting && selectedOptionIds.count >= minSelections
    }

    @objc private func optionTapped(_ sender: UIControl) {
        guard canSubmitVote,
              !isSubmitting,
              let control = sender as? PollOptionControl,
              let optionId = control.option.id
        else { return }

        if selectedOptionIds.contains(optionId) {
            if maxSelections > 1 {
                selectedOptionIds.remove(optionId)
            }
        } else if maxSelections <= 1 {
            selectedOptionIds = [optionId]
        } else if selectedOptionIds.count < maxSelections {
            selectedOptionIds.insert(optionId)
        }
        updateOptionStates()
    }

    @objc private func submitTapped() {
        guard canSubmitVote,
              !isSubmitting,
              selectedOptionIds.count >= minSelections,
              let postId = config.postId,
              let pollName = poll.name
        else { return }

        isSubmitting = true
        updateOptionStates()
        let optionIds = poll.options.compactMap { option -> String? in
            guard let id = option.id, selectedOptionIds.contains(id) else { return nil }
            return id
        }
        delegate?.postCell(didSubmitPollVoteForPostId: postId, pollName: pollName, optionIds: optionIds)
    }
}

private final class PollOptionControl: UIControl {
    let option: PollOption

    private let indicatorView = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .bar)

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.72 : 1
        }
    }

    init(option: PollOption, config: NativeRenderConfig) {
        self.option = option
        super.init(frame: .zero)
        setupUI(config: config)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(isSelected: Bool, canVote: Bool, accentColor: UIColor) {
        isEnabled = canVote && option.id != nil
        backgroundColor = isSelected ? accentColor.withAlphaComponent(0.12) : TopicDetailContentStyle.cardBackground
        layer.borderColor = (isSelected ? accentColor : UIColor.separator.withAlphaComponent(0.18)).cgColor
        indicatorView.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        indicatorView.tintColor = isSelected ? accentColor : .tertiaryLabel
        progressView.progressTintColor = accentColor.withAlphaComponent(isSelected ? 0.7 : 0.45)

        var traits: UIAccessibilityTraits = isEnabled ? [.button] : [.staticText]
        if isSelected {
            traits.insert(.selected)
        }
        accessibilityTraits = traits
        accessibilityLabel = [option.text, metaLabel.text].compactMap { $0 }.joined(separator: "，")
    }

    private func setupUI(config: NativeRenderConfig) {
        backgroundColor = TopicDetailContentStyle.cardBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.0 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.withAlphaComponent(0.18).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true

        indicatorView.image = UIImage(systemName: "circle")
        indicatorView.tintColor = .tertiaryLabel
        indicatorView.contentMode = .scaleAspectFit
        indicatorView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = option.text
        titleLabel.font = config.baseFont
        titleLabel.textColor = config.baseColor
        titleLabel.numberOfLines = 0

        metaLabel.text = metaText()
        metaLabel.font = config.baseFont.withRelativeSize(-1).weighted(.medium)
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 1
        metaLabel.isHidden = metaLabel.text == nil

        progressView.trackTintColor = UIColor.separator.withAlphaComponent(0.16)
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true
        progressView.isHidden = progressValue() == nil
        if let value = progressValue() {
            progressView.setProgress(value, animated: false)
        }
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.heightAnchor.constraint(equalToConstant: 4).isActive = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, metaLabel, progressView])
        textStack.axis = .vertical
        textStack.spacing = 5
        textStack.alignment = .fill
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(indicatorView)
        addSubview(textStack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),

            indicatorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            indicatorView.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicatorView.widthAnchor.constraint(equalToConstant: 18),
            indicatorView.heightAnchor.constraint(equalToConstant: 18),

            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textStack.leadingAnchor.constraint(equalTo: indicatorView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    private func metaText() -> String? {
        var pieces: [String] = []
        if let percentageText = option.percentageText {
            pieces.append(percentageText)
        }
        if let voteCount = option.voteCount {
            pieces.append(String(format: String(localized: "post.poll.vote_count"), voteCount))
        }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " · ")
    }

    private func progressValue() -> Float? {
        guard let percentageText = option.percentageText else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789.")
        let number = String(percentageText.unicodeScalars.filter { allowed.contains($0) })
        guard let value = Float(number) else { return nil }
        return min(max(value / 100, 0), 1)
    }
}

private extension UIFont {
    func withRelativeSize(_ offset: CGFloat) -> UIFont {
        withSize(max(pointSize + offset, 1))
    }

    func weighted(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
