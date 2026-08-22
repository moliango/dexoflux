import UIKit

final class TelegramChatPostCell: WeChatChatPostCell {
    override func dateChipCornerRadius() -> CGFloat { 11 }

    override func dateChipHeight() -> CGFloat { 22 }

    override func dateChipTopInset() -> CGFloat { 8 }

    override func dateChipBackgroundColor(isDark: Bool) -> UIColor {
        isDark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.08)
    }

    override func dateChipTextColor(isDark: Bool) -> UIColor {
        isDark ? UIColor.white.withAlphaComponent(0.75) : .secondaryLabel
    }
}
