import CookedHTML
import UIKit

final class BoostStripView: UIView {
    private static let emojiShortcodeRegex = try! NSRegularExpression(pattern: ":([^\\s:]+(?::t\\d)?):")

    private let groups: [BoostGroup]
    private let baseURL: String

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        return scrollView
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    init?(boosts: [DiscourseTopicDetail.Boost], baseURL: String) {
        let groups = Self.makeGroups(from: boosts)
        guard !groups.isEmpty else { return nil }
        self.groups = groups
        self.baseURL = baseURL
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),

            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        for group in groups {
            stackView.addArrangedSubview(makeBubble(for: group))
        }
    }

    private func makeBubble(for group: BoostGroup) -> UIView {
        let accentColor = AppSettings.shared.themeStyle.accentColor
        let container = UIView()
        container.backgroundColor = .tertiarySystemGroupedBackground
        container.layer.cornerRadius = 13
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1.0 / UIScreen.main.scale
        container.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let avatarView = UIImageView()
        avatarView.contentMode = .scaleAspectFill
        avatarView.clipsToBounds = true
        avatarView.layer.cornerRadius = 10
        avatarView.backgroundColor = .secondarySystemFill
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        AvatarImageLoader.setImage(
            on: avatarView,
            url: avatarURL(for: group.boosts.first?.user.avatarTemplate),
            placeholder: UIImage(systemName: "person.crop.circle.fill")
        )

        let titleFont = TopicDetailTypography.interfaceFont(ofSize: 12, weight: .regular)
        let titleText = attributedDisplayText(for: group, font: titleFont)
        let titleLabel = UILabel()
        titleLabel.attributedText = titleText
        titleLabel.font = titleFont
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let countLabel = UILabel()
        countLabel.text = "\(group.boosts.count)"
        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        countLabel.backgroundColor = accentColor
        countLabel.layer.cornerRadius = 8
        countLabel.clipsToBounds = true
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(avatarView)
        container.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 28),

            avatarView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 5),
            avatarView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 20),
            avatarView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 6),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
        ])

        if group.boosts.count > 1 {
            container.addSubview(countLabel)
            NSLayoutConstraint.activate([
                countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
                countLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -7),
                countLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
                countLabel.heightAnchor.constraint(equalToConstant: 18),
            ])
        } else {
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8).isActive = true
        }

        loadInlineImages(in: titleLabel, attributedString: titleText)
        return container
    }

    private func avatarURL(for template: String?) -> URL? {
        AvatarImageLoader.url(from: template, baseURL: baseURL, size: 48)
    }

    private func attributedDisplayText(for group: BoostGroup, font: UIFont) -> NSMutableAttributedString {
        let fallbackText = group.displayText.isEmpty ? String(localized: "post.boost") : group.displayText
        let inlines = Self.displayInlines(from: group.cookedHTML, baseURL: baseURL)
        let attributed: NSMutableAttributedString
        if inlines.isEmpty {
            attributed = NSMutableAttributedString(string: fallbackText, attributes: [
                .font: font,
                .foregroundColor: UIColor.label,
            ])
        } else {
            attributed = NSMutableAttributedString(attributedString: inlines.attributedString(config: AttributedStringConfig(
                baseFont: font,
                baseColor: .label,
                linkColor: AppSettings.shared.themeStyle.accentColor,
                codeFont: .monospacedSystemFont(ofSize: max(font.pointSize - 1, 1), weight: .regular),
                codeBackgroundColor: .clear
            )))
        }
        return Self.replacingEmojiShortcodes(in: attributed, font: font, textColor: .label)
    }

    private func loadInlineImages(in label: UILabel, attributedString: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: attributedString.length)
        guard fullRange.length > 0 else { return }

        var entries: [(attachment: NSTextAttachment, url: URL)] = []
        attributedString.enumerateAttributes(in: fullRange) { attributes, _, _ in
            guard let attachment = attributes[.attachment] as? NSTextAttachment else { return }

            if let emojiAttachment = attachment as? EmojiTextAttachment,
               let url = emojiAttachment.emojiURL {
                entries.append((attachment, url))
                return
            }

            guard let urlString = attributes[.cookedHTMLImageURL] as? String,
                  let url = URL(string: urlString)
            else { return }
            entries.append((attachment, url))
        }

        for entry in entries {
            ForumImageLoader.loadImage(with: entry.url) { [weak label, attributedString] image in
                guard let image else { return }
                DispatchQueue.main.async {
                    entry.attachment.image = image
                    label?.attributedText = attributedString
                    label?.setNeedsDisplay()
                }
            }
        }
    }

    private static func makeGroups(from boosts: [DiscourseTopicDetail.Boost]) -> [BoostGroup] {
        var seenIds = Set<Int>()
        var order: [String] = []
        var grouped: [String: [DiscourseTopicDetail.Boost]] = [:]
        var displayTextByKey: [String: String] = [:]
        var cookedHTMLByKey: [String: String] = [:]

        for boost in boosts {
            guard seenIds.insert(boost.id).inserted else { continue }
            let displayText = plainText(from: boost.cooked)
            let key = displayText.isEmpty
                ? boost.cooked.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                : displayText.lowercased()
            guard !key.isEmpty else { continue }
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = []
                displayTextByKey[key] = displayText
                cookedHTMLByKey[key] = boost.cooked
            }
            grouped[key]?.append(boost)
        }

        return order.compactMap { key in
            guard let boosts = grouped[key], !boosts.isEmpty else { return nil }
            return BoostGroup(displayText: displayTextByKey[key] ?? "", cookedHTML: cookedHTMLByKey[key] ?? "", boosts: boosts)
        }
    }

    private static func displayInlines(from html: String, baseURL: String) -> [InlineNode] {
        let chunks = CookedHTMLParser.parse(html: html, baseURL: baseURL).map(displayInlines(from:))
        return joinedInlines(chunks).trimmedWhitespace()
    }

    private static func displayInlines(from block: ContentBlock) -> [InlineNode] {
        switch block {
        case .paragraph(let inlines), .heading(_, let inlines):
            return normalizedDisplayInlines(inlines)
        case .blockquote(let blocks), .spoiler(let blocks):
            return joinedInlines(blocks.map(displayInlines(from:)))
        case .discourseQuote(_, _, _, _, _, _, _, let content):
            return joinedInlines(content.map(displayInlines(from:)))
        case .list(_, let items):
            return joinedInlines(items.map { item in
                normalizedDisplayInlines(item.content) + joinedInlines(item.children.map(displayInlines(from:)))
            })
        case .poll(let poll):
            return joinedInlines(poll.options.map { [.text($0.text)] })
        case .details(let summary, let content):
            return normalizedDisplayInlines(summary) + joinedInlines(content.map(displayInlines(from:)))
        case .image(let src, let alt, let width, let height, _):
            if isLikelyEmojiImage(src: src, width: width, height: height) {
                return [.image(src: src, alt: alt, width: width, height: height, isEmoji: true)]
            }
            return alt.flatMap { $0.isEmpty ? nil : [.text($0)] } ?? []
        case .onebox(_, let title, let description, _, _, _, _):
            return [title, description]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { InlineNode.text($0) }
        case .video(_, _, let title, _, _, _, _):
            return title.flatMap { $0.isEmpty ? nil : [.text($0)] } ?? []
        case .codeBlock(_, let code):
            return code.isEmpty ? [] : [.text(code)]
        case .table(let headers, let rows):
            let headerInlines = headers.flatMap { $0.map(displayInlines(from:)) }
            let rowInlines = rows.flatMap { row in row.flatMap { $0.map(displayInlines(from:)) } }
            return joinedInlines(headerInlines + rowInlines)
        case .divider:
            return []
        case .rawHTML(let html):
            let text = plainText(from: html)
            return text.isEmpty ? [] : [.text(text)]
        }
    }

    private static func isLikelyEmojiImage(src: String, width: Int?, height: Int?) -> Bool {
        let lowercasedSource = src.lowercased()
        if lowercasedSource.contains("/emoji") || lowercasedSource.contains("emoji/") {
            return true
        }
        guard let width, let height, width > 0, height > 0 else {
            return false
        }
        return width <= 32 && height <= 32
    }

    private static func normalizedDisplayInlines(_ inlines: [InlineNode]) -> [InlineNode] {
        inlines.map { inline in
            switch inline {
            case .lineBreak:
                return .text(" ")
            case .link(let href, let children):
                return .link(href: href, children: normalizedDisplayInlines(children))
            case .spoiler(let children):
                return .spoiler(children: normalizedDisplayInlines(children))
            default:
                return inline
            }
        }
    }

    private static func joinedInlines(_ chunks: [[InlineNode]]) -> [InlineNode] {
        var result: [InlineNode] = []
        for chunk in chunks where !chunk.isEmpty {
            if !result.isEmpty {
                result.append(.text(" "))
            }
            result.append(contentsOf: chunk)
        }
        return result
    }

    private static func replacingEmojiShortcodes(
        in attributed: NSAttributedString,
        font: UIFont,
        textColor: UIColor
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return result }

        attributed.enumerateAttributes(in: fullRange) { attributes, range, _ in
            if attributes[.attachment] != nil {
                result.append(attributed.attributedSubstring(from: range))
                return
            }

            let text = attributed.attributedSubstring(from: range).string
            guard text.contains(":") else {
                result.append(attributed.attributedSubstring(from: range))
                return
            }

            var textAttributes = attributes
            textAttributes[.font] = textAttributes[.font] ?? font
            textAttributes[.foregroundColor] = textAttributes[.foregroundColor] ?? textColor
            result.append(emojiAttributedString(from: text, attributes: textAttributes, font: font))
        }
        return result
    }

    private static func emojiAttributedString(
        from text: String,
        attributes: [NSAttributedString.Key: Any],
        font: UIFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = emojiShortcodeRegex.matches(in: text, range: fullRange)
        var lastLocation = 0

        for match in matches {
            let plainLength = match.range.location - lastLocation
            if plainLength > 0 {
                result.append(NSAttributedString(
                    string: nsText.substring(with: NSRange(location: lastLocation, length: plainLength)),
                    attributes: attributes
                ))
            }

            let shortcode = nsText.substring(with: match.range)
            let code = nsText.substring(with: match.range(at: 1))
            if let urlString = EmojiStore.url(for: code), let url = URL(string: urlString) {
                let emojiSize = font.pointSize
                let attachment = EmojiTextAttachment()
                attachment.emojiURL = url
                attachment.shortcode = shortcode
                attachment.image = UIImage()
                attachment.bounds = CGRect(
                    x: 0,
                    y: (font.capHeight - emojiSize) / 2,
                    width: emojiSize,
                    height: emojiSize
                )
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(string: shortcode, attributes: attributes))
            }

            lastLocation = match.range.location + match.range.length
        }

        if lastLocation < nsText.length {
            result.append(NSAttributedString(
                string: nsText.substring(from: lastLocation),
                attributes: attributes
            ))
        }
        return result
    }

    private static func plainText(from html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<img[^>]*(?:title|alt)=\"([^\"]+)\"[^>]*>",
            with: " $1 ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "</(p|div|li|blockquote)>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let decoded: String
        if let data = text.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           ) {
            decoded = attributed.string
        } else {
            decoded = text
        }

        return decoded.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct BoostGroup {
    let displayText: String
    let cookedHTML: String
    let boosts: [DiscourseTopicDetail.Boost]
}
