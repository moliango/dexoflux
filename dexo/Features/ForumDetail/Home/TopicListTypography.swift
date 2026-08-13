import UIKit

/// Shared list typography so theme switches (standard / WeChat / Telegram) keep the same sizes.
/// Design sizes are theme-agnostic; scaling goes through `AppSettings` interface font pipeline once.
enum TopicListTypography {
    enum Role {
        case title
        case subtitle
        case meta
        case badge

        /// Pre-adjustment design size. Same across all themes.
        var designPointSize: CGFloat {
            switch self {
            case .title: return AppSettings.topicTitleReferencePointSize // 15
            case .subtitle: return 13
            case .meta: return 12
            case .badge: return 12
            }
        }

        var textStyle: UIFont.TextStyle {
            switch self {
            case .title: return .headline
            case .subtitle: return .subheadline
            case .meta, .badge: return .caption1
            }
        }
    }

    static func font(
        for role: Role,
        weight: UIFont.Weight,
        scaledForDynamicType: Bool = true
    ) -> UIFont {
        let interfaceFont = interfaceFont(ofSize: role.designPointSize, weight: weight)
        guard scaledForDynamicType else { return interfaceFont }
        return UIFontMetrics(forTextStyle: role.textStyle).scaledFont(for: interfaceFont)
    }

    static func scaledFont(
        ofSize pointSize: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle
    ) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(
            for: interfaceFont(ofSize: pointSize, weight: weight)
        )
    }

    static func fixedFont(ofSize pointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        interfaceFont(ofSize: pointSize, weight: weight)
    }

    /// 15pt design → `ContentFontSize.standard` visual size at 100%.
    /// Do not also apply `effectiveInterfacePointSize`; that double-shrinks against the slider multiplier.
    private static func interfaceFont(ofSize pointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        let settings = AppSettings.shared
        return settings.appInterfaceFont(
            ofSize: pointSize,
            weight: weight,
            fallback: UIFont.dexoOriginalSystemFont(ofSize: pointSize, weight: weight)
        )
    }

    static func topicTitleFont(
        weight: UIFont.Weight = .semibold,
        relativeTo textStyle: UIFont.TextStyle = .headline
    ) -> UIFont {
        _ = textStyle
        return font(for: .title, weight: weight, scaledForDynamicType: true)
    }
}
