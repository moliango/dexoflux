import UIKit

/// Source vs visual editing. FluxDo’s toolbar `Aa` / `MD` switch.
enum ComposerEditingMode: String {
    case rich
    case source

    private static let defaultsKey = "composer.editingMode"

    static var stored: ComposerEditingMode {
        get { ComposerEditingMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .rich }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var toggled: ComposerEditingMode { self == .rich ? .source : .rich }
}

/// Composer body matches Topic Detail cooked markdown — content font, not the 25pt chrome size.
enum ComposerTypography {
    static var theme: AppSettings.ThemeStyle { AppSettings.shared.themeStyle }

    static var bodyFont: UIFont { TopicDetailTypography.bodyContentFont() }
    static var codeFont: UIFont { TopicDetailTypography.bodyCodeFont() }
    static var titleFont: UIFont { TopicDetailTypography.topicTitleFont(relativeTo: .title2) }

    static var accentColor: UIColor { theme.accentColor }
    static var backgroundColor: UIColor { theme.contentBackgroundColor }
    static var mutedFill: UIColor { theme.mutedContentBackgroundColor }
    static var chromeRadius: CGFloat { theme.chromeCornerRadius }

    static var lineHeightMultiple: CGFloat { 1.5 }

    static func headingFont(level: Int) -> UIFont {
        let base = bodyFont.pointSize
        let delta: CGFloat
        let weight: UIFont.Weight
        switch level {
        case 1: delta = 6; weight = .bold
        case 2: delta = 5; weight = .bold
        case 3: delta = 4; weight = .semibold
        case 4: delta = 2; weight = .semibold
        case 5: delta = 1; weight = .semibold
        default: delta = 0; weight = .medium
        }
        return AppSettings.shared.contentFont(ofSize: base + delta, weight: weight)
    }

    static func paragraphStyle(
        headIndent: CGFloat = 0,
        paragraphSpacing: CGFloat = 8
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = paragraphSpacing
        style.lineBreakMode = .byWordWrapping
        style.headIndent = headIndent
        style.firstLineHeadIndent = headIndent
        return style
    }

    static var typingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle(),
        ]
    }

    static func applyBody(to textView: UITextView) {
        textView.font = bodyFont
        textView.textColor = .label
        textView.backgroundColor = backgroundColor
        textView.adjustsFontForContentSizeCategory = true
        textView.typingAttributes = typingAttributes
        textView.tintColor = accentColor
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 20, bottom: 20, right: 20)
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
    }

    static func applyBody(to placeholder: UILabel) {
        placeholder.font = bodyFont
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.textColor = .placeholderText
        placeholder.numberOfLines = 0
    }

    static func applyChrome(to view: UIView) {
        view.backgroundColor = backgroundColor
    }
}
