import SDWebImage
import UIKit

/// FluxDo `BadgeUIUtils` port — medal chrome + theme surfaces.
enum BadgeUIStyle {
    static var pageBackground: UIColor {
        AppSettings.shared.themeStyle.topicListBackgroundColor
    }

    static var cardSurface: UIColor {
        AppSettings.shared.themeStyle.topicCardBackgroundColor
    }

    static var chromeAccent: UIColor {
        AppSettings.shared.themeStyle.accentColor
    }

    static func medalColor(for type: DiscourseBadge.BadgeType) -> UIColor {
        type.color
    }

    static func cardBackgroundColor(for type: DiscourseBadge.BadgeType, trait: UITraitCollection) -> UIColor {
        let medal = type.color.resolvedColor(with: trait)
        let surface = cardSurface.resolvedColor(with: trait)
        let isDark = trait.userInterfaceStyle == .dark
        return blend(surface, onto: medal, alpha: isDark ? 0.18 : 0.10)
    }

    static func cardBorderColor(for type: DiscourseBadge.BadgeType, trait: UITraitCollection) -> UIColor {
        let medal = type.color.resolvedColor(with: trait)
        let isDark = trait.userInterfaceStyle == .dark
        return medal.withAlphaComponent(isDark ? 0.30 : 0.20)
    }

    static func applyCardChrome(to view: UIView, type: DiscourseBadge.BadgeType) {
        let trait = view.traitCollection
        view.backgroundColor = cardBackgroundColor(for: type, trait: trait)
        view.layer.cornerRadius = 20
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1.5
        view.layer.borderColor = cardBorderColor(for: type, trait: trait).cgColor
        let medal = type.color.resolvedColor(with: trait)
        let isDark = trait.userInterfaceStyle == .dark
        view.layer.shadowColor = medal.cgColor
        view.layer.shadowOpacity = isDark ? 0.10 : 0.08
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.layer.masksToBounds = false
    }

    static func iconWellBackground(trait: UITraitCollection) -> UIColor {
        let surface = cardSurface.resolvedColor(with: trait)
        if trait.userInterfaceStyle == .dark {
            return surface.withAlphaComponent(0.92)
        }
        return UIColor.white
    }

    static func resolveImageURL(_ raw: String?, baseURL: String) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        let base = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/")
        return URL(string: raw, relativeTo: base)?.absoluteURL
    }

    static func medalSymbolImage(color: UIColor, pointSize: CGFloat = 22) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        return UIImage(systemName: "medal.fill", withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }

    static func badgeIconImage(
        icon: String?,
        imageURL: String?,
        type: DiscourseBadge.BadgeType,
        baseURL: String,
        pointSize: CGFloat,
        into imageView: UIImageView
    ) {
        let color = type.color
        imageView.tintColor = color
        imageView.contentMode = .scaleAspectFit

        if let url = resolveImageURL(imageURL, baseURL: baseURL) {
            ForumImageLoader.setImage(
                on: imageView,
                url: url,
                placeholder: medalSymbolImage(color: color, pointSize: pointSize),
                cloudflareBaseURL: baseURL
            )
            return
        }
        imageView.sd_cancelCurrentImageLoad()
        imageView.image = iconFallback(icon: icon, color: color, pointSize: pointSize)
    }

    static func iconFallback(icon: String?, color: UIColor, pointSize: CGFloat) -> UIImage? {
        if let icon,
           let fa = DiscourseFontAwesomeIcon.image(for: icon, color: color, size: pointSize) {
            return fa
        }
        return medalSymbolImage(color: color, pointSize: pointSize)
    }

    static func plainText(fromHTML html: String?) -> String {
        guard let html, !html.isEmpty else { return "" }
        if let data = html.data(using: .utf8),
           let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
           ) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func blend(_ base: UIColor, onto tint: UIColor, alpha: CGFloat) -> UIColor {
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        tint.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let a = max(0, min(1, alpha))
        return UIColor(
            red: br * (1 - a) + tr * a,
            green: bg * (1 - a) + tg * a,
            blue: bb * (1 - a) + tb * a,
            alpha: 1
        )
    }
}
