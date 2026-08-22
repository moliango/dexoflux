import UIKit

// MARK: - UIColor hex helper

extension UIColor {
    nonisolated convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let int = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - UITextViewDelegate

extension PostNativeCell: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard interaction == .invokeDefaultAction else {
            return true
        }
        delegate?.postCell(didTapLinkURL: URL)
        return false
    }

    @available(iOS 16.0, *)
    func textView(
        _ textView: UITextView,
        editMenuForTextIn range: NSRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        DiscourseQuoteMarkdown.editMenu(
            for: textView,
            range: range,
            suggestedActions: suggestedActions,
            handler: { [weak self] selected in
                self?.delegate?.postCell(didQuoteSelectedText: selected, postId: self?.postId)
            },
            decryptHandler: { [weak self] selected in
                self?.delegate?.postCell(didRequestDecrypt: selected, postId: self?.postId)
            }
        )
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension PostNativeCell: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }
}
