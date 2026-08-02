import UIKit

enum TopicDetailTypography {
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
