import UIKit

/// Topic Detail typography — body + chrome stay on the same AppSettings content/interface scales
/// across classic and WeChat/Telegram surfaces.
enum TopicDetailTypography {
    /// Semantic chrome roles (design sizes are theme-agnostic).
    enum ChromeRole {
        case navTitle
        case error
        case authorName
        case authorMeta
        case floor
        case time
        case replyChip
        case action
        case sortChip
        case dateChip
        case inputBody
        case inputMeta
        case adminBadge

        var designPointSize: CGFloat {
            switch self {
            case .navTitle: return 17
            case .error: return 14
            case .authorName: return 14
            case .authorMeta: return 12
            case .floor: return 13
            case .time: return 11
            case .replyChip: return 12
            case .action: return 12
            case .sortChip: return 13
            case .dateChip: return 13
            case .inputBody: return 16
            case .inputMeta: return 12
            case .adminBadge: return 11
            }
        }

        var textStyle: UIFont.TextStyle {
            switch self {
            case .navTitle: return .headline
            case .error: return .subheadline
            case .authorName: return .subheadline
            case .authorMeta, .floor, .time, .replyChip, .action, .sortChip, .dateChip, .inputMeta, .adminBadge:
                return .caption1
            case .inputBody: return .body
            }
        }

        /// When true, size tracks content (reading) scale; otherwise interface scale.
        var tracksContentScale: Bool {
            switch self {
            case .authorName, .authorMeta, .floor, .time, .replyChip, .dateChip, .adminBadge:
                return true
            case .navTitle, .error, .action, .sortChip, .inputBody, .inputMeta:
                return false
            }
        }

        /// Offset from body design size when `tracksContentScale` is true.
        var contentOffsetFromBody: CGFloat {
            switch self {
            case .authorName: return 0
            case .authorMeta: return -2
            case .floor: return -1
            case .time: return -3
            case .replyChip: return -3
            case .dateChip: return -1
            case .adminBadge: return -3
            default: return 0
            }
        }
    }

    static func interfaceFont(ofSize pointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        let settings = AppSettings.shared
        let adjustedPointSize = settings.effectiveInterfacePointSize(for: pointSize)
        let baseFont = UIFont.systemFont(ofSize: adjustedPointSize, weight: weight)
        return settings.appInterfaceFont(matching: baseFont)
    }

    static func scaledInterfaceFont(
        ofSize pointSize: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle
    ) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: interfaceFont(ofSize: pointSize, weight: weight)
        )
    }

    static func chromeFont(
        _ role: ChromeRole,
        weight: UIFont.Weight,
        scaledForDynamicType: Bool = true
    ) -> UIFont {
        if role.tracksContentScale {
            return contentContextFont(
                offsetFromBody: role.contentOffsetFromBody,
                weight: weight,
                relativeTo: role.textStyle
            )
        }
        let font = interfaceFont(ofSize: role.designPointSize, weight: weight)
        guard scaledForDynamicType else { return font }
        return UIFontMetrics(forTextStyle: role.textStyle).scaledFont(for: font)
    }

    static func topicTitleFont(relativeTo textStyle: UIFont.TextStyle = .headline) -> UIFont {
        let settings = AppSettings.shared
        let comfortFontDelta: CGFloat = settings.readingComfortMode ? 1 : 0
        let pointSize = settings.effectiveContentPointSize(
            for: settings.contentFontSize.basePointSize + comfortFontDelta
        )
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: settings.contentFont(ofSize: pointSize, weight: .semibold)
        )
    }

    /// Post body / cooked HTML base font — single source for classic + chat.
    static func bodyContentFont() -> UIFont {
        let settings = AppSettings.shared
        let comfortFontDelta: CGFloat = settings.readingComfortMode ? 1 : 0
        let basePointSize = settings.effectiveContentPointSize(
            for: settings.contentFontSize.basePointSize + comfortFontDelta
        )
        return UIFontMetrics(forTextStyle: .body).scaledFont(
            for: settings.contentFont(ofSize: basePointSize)
        )
    }

    static func bodyCodeFont() -> UIFont {
        let settings = AppSettings.shared
        let comfortFontDelta: CGFloat = settings.readingComfortMode ? 1 : 0
        let basePointSize = settings.effectiveContentPointSize(
            for: settings.contentFontSize.basePointSize + comfortFontDelta
        )
        return UIFontMetrics(forTextStyle: .body).scaledFont(
            for: settings.contentMonospacedFont(ofSize: max(basePointSize - 1, 1))
        )
    }

    static func contentContextFont(
        offsetFromBody offset: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle
    ) -> UIFont {
        let settings = AppSettings.shared
        let pointSize = contentContextPointSize(offsetFromBody: offset)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: settings.contentFont(ofSize: pointSize, weight: weight)
        )
    }

    static func contentContextMonospacedFont(
        offsetFromBody offset: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle
    ) -> UIFont {
        let settings = AppSettings.shared
        let pointSize = contentContextPointSize(offsetFromBody: offset)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: settings.contentMonospacedFont(ofSize: pointSize, weight: weight)
        )
    }

    static func contentVisualScale() -> CGFloat {
        let settings = AppSettings.shared
        let comfortFontDelta: CGFloat = settings.readingComfortMode ? 1 : 0
        let bodySourceSize = settings.contentFontSize.basePointSize + comfortFontDelta
        let bodySizeRatio = bodySourceSize / AppSettings.ContentFontSize.standard.basePointSize
        let scaleRatio = CGFloat(settings.contentFontScalePercent) / CGFloat(AppSettings.defaultFontScalePercent)
        return max(bodySizeRatio * scaleRatio, 0.75)
    }

    private static func contentContextPointSize(offsetFromBody offset: CGFloat) -> CGFloat {
        let settings = AppSettings.shared
        let comfortFontDelta: CGFloat = settings.readingComfortMode ? 1 : 0
        let sourcePointSize = max(settings.contentFontSize.basePointSize + comfortFontDelta + offset, 1)
        return settings.effectiveContentPointSize(for: sourcePointSize)
    }
}
