import UIKit

/// WeChat-style circular mini-program icon: logo fills the full disc, no gray ring padding.
enum MiniProgramIconBadge {
    static let defaultSize: CGFloat = 56

    /// Pre-rendered circular app icon (alwaysOriginal).
    @MainActor
    static func image(for programID: String, size: CGFloat = defaultSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let circle = UIBezierPath(ovalIn: rect)
            circle.addClip()

            if let composed = composeContent(for: programID, in: rect) {
                composed()
            } else {
                drawFallback(in: rect, symbolName: "app.fill")
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    /// Live badge view used by drawer / launcher grids.
    @MainActor
    static func view(for programID: String, size: CGFloat = defaultSize) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false
        container.backgroundColor = .clear

        let imageView = UIImageView(image: image(for: programID, size: size))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = size / 2
        imageView.layer.cornerCurve = .continuous
        // Subtle edge so white logos don't vanish on the dark drawer.
        imageView.layer.borderWidth = 1.0 / UIScreen.main.scale
        imageView.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor

        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: - Compose

    @MainActor
    private static func composeContent(for programID: String, in rect: CGRect) -> (() -> Void)? {
        switch programID {
        case MiniProgramID.newAPICheckIn:
            return {
                drawGradient(in: rect, colors: [.systemTeal, .systemGreen])
                drawSymbol("checkmark.seal.fill", in: rect, pointSize: rect.width * 0.46, color: .white)
            }
        case MiniProgramID.ldcStore:
            return {
                if let logo = UIImage(named: "LDStoreLogo") {
                    drawBitmap(logo, in: rect, fill: true)
                } else {
                    drawGradient(in: rect, colors: [.systemOrange, .systemPink])
                    drawSymbol("shippingbox.fill", in: rect, pointSize: rect.width * 0.46, color: .white)
                }
            }
        case MiniProgramID.metaverse:
            return {
                drawGradient(in: rect, colors: [
                    UIColor(red: 0.45, green: 0.30, blue: 0.95, alpha: 1),
                    UIColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1),
                ])
                drawSymbol("globe.asia.australia.fill", in: rect, pointSize: rect.width * 0.42, color: .white)
            }
        case MiniProgramID.ldc:
            return {
                drawGradient(in: rect, colors: [
                    UIColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 1),
                    UIColor(red: 0.35, green: 0.65, blue: 1.0, alpha: 1),
                ])
                drawSymbol("sparkles.rectangle.stack.fill", in: rect, pointSize: rect.width * 0.42, color: .white)
            }
        case MiniProgramID.cdk:
            return {
                drawGradient(in: rect, colors: [
                    UIColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1),
                    UIColor(red: 0.15, green: 0.40, blue: 0.85, alpha: 1),
                ])
                drawSymbol("ticket.fill", in: rect, pointSize: rect.width * 0.42, color: .white)
            }
        default:
            break
        }

        guard let record = MiniProgramStore.shared.program(id: programID) else {
            return nil
        }

        switch record.icon {
        case .none:
            // Custom programs may intentionally have no logo (export/import without assets).
            let colors = palette(for: programID)
            return {
                drawGradient(in: rect, colors: colors)
                drawSymbol("app.fill", in: rect, pointSize: rect.width * 0.42, color: .white)
            }
        case .system(let symbolName):
            let colors = palette(for: programID)
            return {
                drawGradient(in: rect, colors: colors)
                drawSymbol(symbolName, in: rect, pointSize: rect.width * 0.42, color: .white)
            }
        case .local(let relativePath):
            if let logo = MiniProgramIconStore.shared.image(relativePath: relativePath) {
                return { drawBitmap(logo, in: rect, fill: true) }
            }
            return {
                drawFallback(in: rect, symbolName: "app.fill")
            }
        case .remote:
            // Remote icons are downloaded to local store when saved; until then use a globe badge.
            return {
                drawSolid(in: rect, color: UIColor(white: 0.22, alpha: 1))
                drawSymbol("globe", in: rect, pointSize: rect.width * 0.42, color: .white)
            }
        }
    }

    // MARK: - Drawing

    private static func drawBitmap(_ image: UIImage, in rect: CGRect, fill: Bool) {
        // White disc first so transparent PNGs look like WeChat app icons.
        UIColor.white.setFill()
        UIBezierPath(ovalIn: rect).fill()

        let drawRect: CGRect
        if fill {
            // Edge-to-edge cover (WeChat brand icons fill the circle).
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else {
                image.draw(in: rect)
                return
            }
            let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
            let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            drawRect = CGRect(
                x: rect.midX - scaled.width / 2,
                y: rect.midY - scaled.height / 2,
                width: scaled.width,
                height: scaled.height
            )
        } else {
            let inset = rect.width * 0.14
            drawRect = rect.insetBy(dx: inset, dy: inset)
        }
        image.draw(in: drawRect)
    }

    private static func drawSymbol(
        _ name: String,
        in rect: CGRect,
        pointSize: CGFloat,
        color: UIColor
    ) {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        else { return }
        let size = symbol.size
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )
        symbol.draw(at: origin)
    }

    private static func drawGradient(in rect: CGRect, colors: [UIColor]) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let cgColors = colors.map(\.cgColor) as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors,
            locations: [0, 1]
        ) else { return }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: []
        )
    }

    private static func drawSolid(in rect: CGRect, color: UIColor) {
        color.setFill()
        UIBezierPath(ovalIn: rect).fill()
    }

    private static func drawFallback(in rect: CGRect, symbolName: String) {
        drawSolid(in: rect, color: UIColor(white: 0.22, alpha: 1))
        drawSymbol(symbolName, in: rect, pointSize: rect.width * 0.42, color: .white)
    }

    /// Stable pastel-ish gradient pair derived from program id (looks like distinct app icons).
    private static func palette(for programID: String) -> [UIColor] {
        let palettes: [[UIColor]] = [
            [.systemBlue, .systemTeal],
            [.systemIndigo, .systemPurple],
            [.systemOrange, .systemPink],
            [.systemGreen, .systemMint],
            [.systemRed, .systemOrange],
            [.systemPurple, .systemBlue],
            [.systemTeal, .systemCyan],
            [.systemBrown, .systemOrange],
        ]
        var hash = 0
        for scalar in programID.unicodeScalars {
            hash = (hash &+ Int(scalar.value) &* 31) & 0x7fff_ffff
        }
        return palettes[hash % palettes.count]
    }
}
