import SDWebImage
import UIKit

extension PostNativeCell {
    // MARK: - Header Badges
    func configureHeaderBadges(for post: DiscourseTopicDetail.Post, baseURL: String) {
        resetHeaderBadgeStack(topBadgesStackView)
        resetHeaderBadgeStack(grantedBadgesStackView)

        if post.moderator || post.groupModerator || post.admin {
            let shieldView = makeFontAwesomeBadgeView(
                icon: "shield-alt",
                tintColor: .systemBlue,
                size: 13
            ) ?? makeHeaderBadgeImageView(
                image: UIImage(systemName: "shield.fill"),
                tintColor: .systemBlue,
                size: 13
            )
            topBadgesStackView.addArrangedSubview(shieldView)
        }
        topBadgesStackView.isHidden = topBadgesStackView.arrangedSubviews.isEmpty

        if let emoji = post.userStatus?.emoji,
           let urlString = EmojiStore.url(for: emoji) ?? EmojiStore.lookup(for: emoji),
           let url = URL(string: urlString) {
            topBadgesStackView.addArrangedSubview(makeHeaderBadgeImageView(url: url, size: 15))
        }
        topBadgesStackView.isHidden = topBadgesStackView.arrangedSubviews.isEmpty

        for badge in post.badgesGranted {
            guard let badgeView = makeGrantedBadgeView(for: badge, baseURL: baseURL) else {
                continue
            }
            grantedBadgesStackView.addArrangedSubview(badgeView)
        }
        grantedBadgesStackView.isHidden = grantedBadgesStackView.arrangedSubviews.isEmpty
    }

    func resetHeaderBadgeStack(_ stackView: UIStackView) {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            cancelImageLoads(in: view)
            view.removeFromSuperview()
        }
        stackView.isHidden = true
    }

    func cancelImageLoads(in view: UIView) {
        if let imageView = view as? UIImageView {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = nil
        }
        for subview in view.subviews {
            cancelImageLoads(in: subview)
        }
    }

    func cancelContentMediaLoads(in view: UIView) {
        if let container = view as? TappableImageContainer {
            container.cancelImageLoad()
        } else if let signature = view as? SignatureImageView {
            signature.cancelImageLoad()
        } else if let onebox = view as? OneboxCardView {
            onebox.cancelImageLoad()
        } else if let video = view as? VideoCardView {
            video.cancelImageLoad()
        } else if let fallback = view as? FallbackBlockView {
            fallback.cancelRender()
        } else if let badge = view as? BadgeCardView {
            // BadgeCardView owns a WKWebView; deinit stops loading.
            _ = badge
        }

        if let stack = view as? UIStackView {
            for arranged in stack.arrangedSubviews {
                cancelContentMediaLoads(in: arranged)
            }
        }
        for subview in view.subviews {
            cancelContentMediaLoads(in: subview)
        }
    }

    func makeGrantedBadgeView(for badge: DiscourseTopicDetail.GrantedBadge, baseURL: String) -> UIView? {
        let color = grantedBadgeColor(for: badge)
        if let imageUrl = badge.imageUrl,
           let url = resolveHeaderBadgeURL(imageUrl, baseURL: baseURL) {
            let imageView = makeHeaderBadgeImageView(
                url: url,
                placeholder: nil,
                placeholderTintColor: .clear,
                size: 14
            )
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = badge.name
            return imageView
        }

        if let badgeView = makeFontAwesomeBadgeView(icon: badge.icon, tintColor: color, size: 13) {
            badgeView.isAccessibilityElement = true
            badgeView.accessibilityLabel = badge.name
            return badgeView
        }

        return nil
    }

    func makeFontAwesomeBadgeView(icon: String?, tintColor: UIColor, size: CGFloat) -> UIView? {
        guard let glyph = DiscourseFontAwesomeIcon.glyph(for: icon),
              let font = UIFont(name: DiscourseFontAwesomeIcon.fontName, size: size)
        else { return nil }

        let label = UILabel()
        label.text = glyph
        label.font = font
        label.textColor = tintColor
        label.textAlignment = .center
        label.adjustsFontForContentSizeCategory = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: size + 1),
            label.heightAnchor.constraint(equalToConstant: size + 1),
        ])
        return label
    }

    func makeHeaderBadgeImageView(
        url: URL,
        placeholder: UIImage?,
        placeholderTintColor: UIColor,
        size: CGFloat
    ) -> UIImageView {
        let imageView = makeHeaderBadgeImageView(
            image: placeholder,
            tintColor: placeholderTintColor,
            size: size
        )
        imageView.isAccessibilityElement = false

        if let cacheKey = SDWebImageManager.shared.cacheKey(for: url),
           let cachedImage = SDImageCache.shared.imageFromCache(forKey: cacheKey) {
            imageView.image = cachedImage.withRenderingMode(.alwaysOriginal)
            imageView.tintColor = nil
            return imageView
        }

        ForumImageLoader.setImage(
            on: imageView,
            url: url,
            placeholder: placeholder?.withRenderingMode(.alwaysTemplate)
        ) { [weak imageView] image, _, _, _ in
            guard let image else { return }
            imageView?.image = image.withRenderingMode(.alwaysOriginal)
            imageView?.tintColor = nil
        }
        return imageView
    }

    func makeHeaderBadgeImageView(url: URL, size: CGFloat) -> UIImageView {
        makeHeaderBadgeImageView(url: url, placeholder: nil, placeholderTintColor: .clear, size: size)
    }

    func makeHeaderBadgeImageView(image: UIImage?, tintColor: UIColor?, size: CGFloat) -> UIImageView {
        let imageView = UIImageView(image: image?.withRenderingMode(tintColor == nil ? .alwaysOriginal : .alwaysTemplate))
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = tintColor
        imageView.isAccessibilityElement = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: size),
            imageView.heightAnchor.constraint(equalToConstant: size),
        ])
        return imageView
    }

    func resolveHeaderBadgeURL(_ rawURL: String, baseURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        var normalizedBaseURL = baseURL
        if normalizedBaseURL.hasSuffix("/") {
            normalizedBaseURL.removeLast()
        }
        let normalizedPath = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        return URL(string: normalizedBaseURL + normalizedPath)
    }

    func grantedBadgeColor(for badge: DiscourseTopicDetail.GrantedBadge) -> UIColor {
        switch badge.badgeTypeId {
        case 1:
            return UIColor(red: 0.90, green: 0.63, blue: 0.00, alpha: 1)
        case 2:
            return UIColor(red: 0.60, green: 0.60, blue: 0.60, alpha: 1)
        case 3:
            return UIColor(red: 0.80, green: 0.50, blue: 0.20, alpha: 1)
        default:
            return AppSettings.shared.themeStyle.accentColor
        }
    }

    func configureFlairBadge(for post: DiscourseTopicDetail.Post, baseURL: String) {
        flairImageView.sd_cancelCurrentImageLoad()
        flairImageView.image = nil
        flairImageView.layer.borderWidth = 0
        flairImageView.layer.borderColor = nil
        let explicitBadgeBackgroundColor = post.flairBgColor.flatMap(UIColor.init(hex:))
        let badgeBackgroundColor = explicitBadgeBackgroundColor
        let badgeForegroundColor = post.flairColor.flatMap(UIColor.init(hex:))
            ?? (badgeBackgroundColor == nil ? .label : .white)
        flairImageView.tintColor = badgeForegroundColor

        guard let flairUrl = post.flairUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !flairUrl.isEmpty
        else {
            flairBadgeView.backgroundColor = .clear
            flairBadgeView.isHidden = true
            return
        }

        flairBadgeView.isHidden = false

        if !isImageFlairURL(flairUrl) {
            guard let iconImage = makeFontAwesomeGlyphImage(
                icon: flairUrl,
                color: badgeForegroundColor,
                size: max((flairWidthConstraint?.constant ?? 18) * 0.72, 10)
            ) else {
                flairBadgeView.backgroundColor = .clear
                flairBadgeView.isHidden = true
                return
            }
            flairBadgeView.backgroundColor = badgeBackgroundColor ?? .clear
            flairImageView.tintColor = nil
            flairImageView.image = iconImage
            applyFlairImageScale(badgeBackgroundColor == nil ? 0.8 : 0.62)
            return
        }

        guard let url = resolveFlairURL(flairUrl, baseURL: baseURL) else {
            flairBadgeView.backgroundColor = .clear
            flairBadgeView.isHidden = true
            return
        }

        flairBadgeView.backgroundColor = badgeBackgroundColor ?? .clear
        applyFlairImageScale(badgeBackgroundColor == nil ? 1 : 0.7)
        ForumImageLoader.setImage(on: flairImageView, url: url)
    }

    func applyFlairImageScale(_ scale: CGFloat, badgeSize: CGFloat? = nil) {
        let resolvedBadgeSize = badgeSize ?? max(flairWidthConstraint?.constant ?? 18, 18)
        let imageSize = max(resolvedBadgeSize * scale, 1)
        flairImageWidthConstraint?.constant = imageSize
        flairImageHeightConstraint?.constant = imageSize
    }

    func resolveFlairURL(_ flairUrl: String, baseURL: String) -> URL? {
        guard isImageFlairURL(flairUrl) else {
            return nil
        }
        if flairUrl.hasPrefix(":") && flairUrl.hasSuffix(":") {
            let emojiName = String(flairUrl.dropFirst().dropLast())
            guard let emojiURLString = EmojiStore.url(for: emojiName) ?? EmojiStore.lookup(for: emojiName) else {
                return nil
            }
            return resolveHeaderBadgeURL(emojiURLString, baseURL: baseURL)
        }
        if flairUrl.hasPrefix("http") {
            return URL(string: flairUrl)
        }
        var normalizedBaseURL = baseURL
        if normalizedBaseURL.hasSuffix("/") {
            normalizedBaseURL.removeLast()
        }
        let normalizedPath = flairUrl.hasPrefix("/") ? flairUrl : "/\(flairUrl)"
        return URL(string: normalizedBaseURL + normalizedPath)
    }

    func isImageFlairURL(_ flairUrl: String) -> Bool {
        if flairUrl.hasPrefix("http://") || flairUrl.hasPrefix("https://") || flairUrl.hasPrefix("/") {
            return true
        }
        if flairUrl.hasPrefix(":") && flairUrl.hasSuffix(":") {
            return true
        }
        let lowercased = flairUrl.lowercased()
        return lowercased.contains(".png")
            || lowercased.contains(".jpg")
            || lowercased.contains(".jpeg")
            || lowercased.contains(".webp")
            || lowercased.contains(".gif")
            || lowercased.contains(".svg")
    }

    func makeFontAwesomeGlyphImage(icon: String?, color: UIColor, size: CGFloat) -> UIImage? {
        DiscourseFontAwesomeIcon.image(for: icon, color: color, size: size)
    }

}
