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
        interfaceFont(
            ofSize: role.designPointSize,
            weight: weight,
            textStyle: scaledForDynamicType ? role.textStyle : nil
        )
    }

    static func scaledFont(
        ofSize pointSize: CGFloat,
        weight: UIFont.Weight,
        relativeTo textStyle: UIFont.TextStyle
    ) -> UIFont {
        interfaceFont(ofSize: pointSize, weight: weight, textStyle: textStyle)
    }

    static func fixedFont(ofSize pointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        interfaceFont(ofSize: pointSize, weight: weight, textStyle: nil)
    }

    /// Scale design size with the interface slider. Use `scaledValue(for:)` instead of
    /// `scaledFont(for:)` so Dynamic Type does not stamp a text style that makes
    /// `adjustsFontForContentSizeCategory` ignore the slider.
    private static func interfaceFont(
        ofSize pointSize: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle?
    ) -> UIFont {
        let designSize: CGFloat
        if let textStyle {
            designSize = UIFontMetrics(forTextStyle: textStyle).scaledValue(for: pointSize)
        } else {
            designSize = pointSize
        }
        let settings = AppSettings.shared
        return settings.appInterfaceFont(
            ofSize: designSize,
            weight: weight,
            fallback: UIFont.doerOriginalSystemFont(ofSize: designSize, weight: weight)
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
