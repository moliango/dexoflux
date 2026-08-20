import UIKit
import WebKit

/// FluxDo-style status/music badge for `prompt.iwooji.com/badge?...`.
///
/// The remote endpoint returns an **animated SVG** (SMIL snow/marquee effects).
/// A pure native dual-tone card loses all motion, so we load the real SVG in a
/// lightweight WKWebView (Safari-equivalent SMIL autoplay) and keep the native
/// card only as a loading / failure placeholder.
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

    /// Intrinsic badge canvas used by the SVG generator (width x height).
    static let intrinsicSize = CGSize(width: 458, height: 90)

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
        // `k=none` means no special icon key; still show the FluxDo-style play affordance on failure fallback.
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
        return UIColor(doerHex: value) ?? fallback
    }
}

final class BadgeCardView: UIView, WKNavigationDelegate {
    weak var delegate: PostCellDelegate?
    private let model: BadgeCardModel
    private let placeholderView = UIView()
    private var webView: WKWebView?
    private var didLoadSVG = false
    private var loadGeneration = 0

    init(model: BadgeCardModel, containerWidth: CGFloat) {
        self.model = model
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup(containerWidth: containerWidth)
        loadAnimatedSVG()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
    }

    private func setup(containerWidth: CGFloat) {
        // Match remote SVG canvas (458x90), scale to content width, never upscale beyond intrinsic.
        let displayWidth = min(max(containerWidth, 1), BadgeCardModel.intrinsicSize.width)
        let displayHeight = displayWidth * BadgeCardModel.intrinsicSize.height / BadgeCardModel.intrinsicSize.width
        heightAnchor.constraint(equalToConstant: ceil(displayHeight)).isActive = true
        widthAnchor.constraint(lessThanOrEqualToConstant: displayWidth).isActive = true

        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true
        backgroundColor = .clear

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderView)
        NSLayoutConstraint.activate([
            placeholderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        installPlaceholderContents()

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
        accessibilityTraits = .image
        accessibilityLabel = [model.title, model.subtitle]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "，")
    }

    private func installPlaceholderContents() {
        placeholderView.subviews.forEach { $0.removeFromSuperview() }
        placeholderView.layer.cornerRadius = 12
        placeholderView.layer.cornerCurve = .continuous
        placeholderView.clipsToBounds = true

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

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = model.subtitle
        subtitleLabel.textColor = model.subtitleColor
        subtitleLabel.font = .systemFont(ofSize: model.rightFontSize, weight: .medium)
        subtitleLabel.lineBreakMode = .byTruncatingTail

        let playButton = UIImageView(
            image: UIImage(systemName: "play.circle.fill")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        )
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.tintColor = model.subtitleColor.withAlphaComponent(0.9)
        playButton.isHidden = !model.showsPlayButton
        playButton.setContentHuggingPriority(.required, for: .horizontal)

        placeholderView.addSubview(left)
        placeholderView.addSubview(right)
        left.addSubview(titleLabel)
        right.addSubview(subtitleLabel)
        right.addSubview(playButton)

        let leftWidth = UIScreen.main.bounds.width * 0.28
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: placeholderView.leadingAnchor),
            left.topAnchor.constraint(equalTo: placeholderView.topAnchor),
            left.bottomAnchor.constraint(equalTo: placeholderView.bottomAnchor),
            left.widthAnchor.constraint(equalToConstant: max(min(leftWidth, 150), 110)),

            right.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            right.trailingAnchor.constraint(equalTo: placeholderView.trailingAnchor),
            right.topAnchor.constraint(equalTo: placeholderView.topAnchor),
            right.bottomAnchor.constraint(equalTo: placeholderView.bottomAnchor),

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
    }

    private func loadAnimatedSVG() {
        loadGeneration += 1
        let generation = loadGeneration

        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        // Badge SVG may include <audio> on some themes; allow inline autoplay.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0

        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.webView = webView

        // Fetch SVG bytes then inline them. Direct document load keeps SMIL running
        // (unlike <img> in some WebKit builds) and CSS can force width:100%.
        var request = URLRequest(url: model.sourceURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self, self.loadGeneration == generation else { return }
                guard error == nil,
                      let data,
                      let svg = String(data: data, encoding: .utf8),
                      svg.localizedCaseInsensitiveContains("<svg")
                else {
                    return
                }
                let html = Self.makeAutoplayHTML(embedding: svg)
                webView.loadHTMLString(html, baseURL: self.model.sourceURL)
            }
        }
        task.resume()

        // Safety timeout: if load never finishes, keep native placeholder.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard self.loadGeneration == generation, !self.didLoadSVG else { return }
            self.webView?.stopLoading()
        }
    }

    private static func makeAutoplayHTML(embedding svg: String) -> String {
        // Strip XML declaration noise; keep the <svg> tree intact so SMIL animates.
        var body = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("<?xml") {
            if let end = body.range(of: "?>") {
                body = String(body[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Forum content is untrusted: drop scripts / foreignObject handlers before WebKit executes.
        body = BadgeSVGSanitizer.stripActiveContent(from: body)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
        <style>
          html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            overflow: hidden;
            width: 100%;
            height: 100%;
          }
          svg {
            display: block;
            width: 100% !important;
            height: auto !important;
            max-width: 100%;
          }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didLoadSVG = true
        UIView.animate(withDuration: 0.18) {
            webView.alpha = 1
            self.placeholderView.alpha = 0
        } completion: { _ in
            self.placeholderView.isHidden = true
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        placeholderView.isHidden = false
        placeholderView.alpha = 1
        webView.alpha = 0
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        placeholderView.isHidden = false
        placeholderView.alpha = 1
        webView.alpha = 0
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Keep animations cheap: reload when re-entering hierarchy if prior load failed.
        if window != nil, !didLoadSVG, webView == nil {
            loadAnimatedSVG()
        }
    }

    @objc private func tapped() {
        delegate?.postCell(didTapLinkURL: model.sourceURL)
    }
}

private enum BadgeSVGSanitizer {
    static func stripActiveContent(from svg: String) -> String {
        var result = svg
        // Remove <script>...</script> and self-closing script tags.
        if let regex = try? NSRegularExpression(
            pattern: #"<script\b[^>]*>[\s\S]*?</script\s*>|<script\b[^>]*/>"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        if let regex = try? NSRegularExpression(
            pattern: #"<foreignObject\b[^>]*>[\s\S]*?</foreignObject\s*>|<foreignObject\b[^>]*/>"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
        }
        return result
    }
}

private extension UIColor {

    convenience init?(doerHex: String) {
        var hex = doerHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
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
