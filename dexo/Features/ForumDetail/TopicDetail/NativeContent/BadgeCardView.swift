import UIKit

/// FluxDo-style status/music badge card for `prompt.iwooji.com/badge?...` links.
///
/// Discourse often leaves these as bare auto-links. FluxDo parses query params and
/// draws a dual-tone card instead of showing the raw URL.
struct BadgeCardModel: Equatable {
    let sourceURL: URL
    let title: String
    let subtitle: String?
    let leftBackground: UIColor
    let rightBackground: UIColor
    let titleColor: UIColor
    let subtitleColor: UIColor
    let leftFontSize: CGFloat
    let rightFontSize: CGFloat
    let showsPlayButton: Bool

    static func parse(url: URL) -> BadgeCardModel? {
        let absolute = url.absoluteString
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
        let normalized = URL(string: absolute) ?? url

        let host = (normalized.host ?? "").lowercased()
        let path = normalized.path.lowercased()
        let looksLikeBadgeHost = host == "prompt.iwooji.com" || host.hasSuffix(".iwooji.com") || host.contains("iwooji")
        let looksLikeBadgePath = path == "/badge" || path.hasSuffix("/badge") || path.contains("/badge")
        // Also accept absolute string marker when path parsing is weird.
        let looksLikeBadgeText = absolute.lowercased().contains("iwooji.com/badge")
        guard looksLikeBadgeHost || looksLikeBadgeText else { return nil }
        guard looksLikeBadgePath || looksLikeBadgeText else { return nil }

        let items = URLComponents(url: normalized, resolvingAgainstBaseURL: false)?.queryItems
            ?? URLComponents(string: absolute)?.queryItems
            ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let title = value("t").flatMap { $0.isEmpty ? nil : $0 } ?? "Badge"
        let subtitle = value("w").flatMap { $0.isEmpty ? nil : $0 }
        let leftBackground = color(
            from: value("l") ?? value("tc"),
            fallback: UIColor(red: 0x69 / 255, green: 0x66 / 255, blue: 0xEA / 255, alpha: 1)
        )
        let rightBackground = color(
            from: value("dc"),
            fallback: UIColor(red: 0x34 / 255, green: 0x49 / 255, blue: 0x5E / 255, alpha: 1)
        )
        let titleColor = color(from: value("tfc"), fallback: .white)
        let subtitleColor = color(from: value("dfc"), fallback: .white)
        let leftFontSize = CGFloat(Int(value("lfs") ?? "") ?? 15)
        let rightFontSize = CGFloat(Int(value("rfs") ?? "") ?? 15)
        // `k=none` means no special icon key; still show the FluxDo-style play affordance.
        let showsPlayButton = true

        return BadgeCardModel(
            sourceURL: normalized,
            title: title,
            subtitle: subtitle,
            leftBackground: leftBackground,
            rightBackground: rightBackground,
            titleColor: titleColor,
            subtitleColor: subtitleColor,
            leftFontSize: max(leftFontSize, 11),
            rightFontSize: max(rightFontSize, 11),
            showsPlayButton: showsPlayButton
        )
    }

    private static func color(from raw: String?, fallback: UIColor) -> UIColor {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return fallback
        }
        if value.hasPrefix("%23") {
            value = "#" + value.dropFirst(3)
        }
        if !value.hasPrefix("#") {
            // query often omits '#' (e.g. l=afe6ba7a, tc=6966ea)
            let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            if (value.count == 6 || value.count == 8),
               value.unicodeScalars.allSatisfy({ hexChars.contains($0) }) {
                value = "#\(value)"
            } else {
                return fallback
            }
        }
        return UIColor(dexoHex: value) ?? fallback
    }
}

final class BadgeCardView: UIView {
    weak var delegate: PostCellDelegate?
    private let model: BadgeCardModel

    init(model: BadgeCardModel, containerWidth: CGFloat) {
        self.model = model
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup(containerWidth: containerWidth)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(containerWidth: CGFloat) {
        let height: CGFloat = 52
        heightAnchor.constraint(equalToConstant: height).isActive = true

        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let left = UIView()
        left.translatesAutoresizingMaskIntoConstraints = false
        left.backgroundColor = model.leftBackground

        let right = UIView()
        right.translatesAutoresizingMaskIntoConstraints = false
        right.backgroundColor = model.rightBackground

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = model.title
        titleLabel.textColor = model.titleColor
        titleLabel.font = .systemFont(ofSize: model.leftFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = model.subtitle
        subtitleLabel.textColor = model.subtitleColor.withAlphaComponent(0.92)
        subtitleLabel.font = .systemFont(ofSize: model.rightFontSize, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.numberOfLines = 1
        subtitleLabel.isHidden = (model.subtitle ?? "").isEmpty

        let playButton = UIImageView(image: UIImage(systemName: "play.circle.fill"))
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.tintColor = UIColor.white.withAlphaComponent(0.92)
        playButton.contentMode = .scaleAspectFit
        playButton.isHidden = !model.showsPlayButton

        addSubview(left)
        addSubview(right)
        left.addSubview(titleLabel)
        right.addSubview(subtitleLabel)
        right.addSubview(playButton)

        // Left pane ~38%, matching FluxDo badge proportions.
        let leftWidth = max(min(containerWidth * 0.38, 180), 120)

        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: leadingAnchor),
            left.topAnchor.constraint(equalTo: topAnchor),
            left.bottomAnchor.constraint(equalTo: bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: leftWidth),

            right.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor),
            right.topAnchor.constraint(equalTo: topAnchor),
            right.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: left.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: left.trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: left.centerYAnchor),

            playButton.trailingAnchor.constraint(equalTo: right.trailingAnchor, constant: -12),
            playButton.centerYAnchor.constraint(equalTo: right.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 22),
            playButton.heightAnchor.constraint(equalToConstant: 22),

            subtitleLabel.leadingAnchor.constraint(equalTo: right.leadingAnchor, constant: 12),
            subtitleLabel.trailingAnchor.constraint(equalTo: playButton.leadingAnchor, constant: -8),
            subtitleLabel.centerYAnchor.constraint(equalTo: right.centerYAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
        accessibilityTraits = .link
        accessibilityLabel = [model.title, model.subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
    }

    @objc private func tapped() {
        delegate?.postCell(didTapLinkURL: model.sourceURL)
    }
}

private extension UIColor {
    convenience init?(dexoHex: String) {
        var hex = dexoHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }

        let a, r, g, b: UInt64
        if hex.count == 8 {
            a = (value & 0xFF00_0000) >> 24
            r = (value & 0x00FF_0000) >> 16
            g = (value & 0x0000_FF00) >> 8
            b = value & 0x0000_00FF
        } else {
            a = 255
            r = (value & 0xFF0000) >> 16
            g = (value & 0x00FF00) >> 8
            b = value & 0x0000FF
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
