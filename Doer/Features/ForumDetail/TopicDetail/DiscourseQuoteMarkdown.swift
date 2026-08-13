import UIKit

enum DiscourseQuoteMarkdown {
    static let actionTitle = String(localized: "post.quote_reply", defaultValue: "引用回复")

    static func make(username: String, postNumber: Int, topicId: Int, excerpt: String) -> String {
        let clipped = excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipped.isEmpty else { return "" }
        let safeName = username.replacingOccurrences(of: "\"", with: "'")
        return "[quote=\"\(safeName), post:\(postNumber), topic:\(topicId)\"]\n\(clipped)\n[/quote]\n\n"
    }

    static func selectedText(in textView: UITextView, range: NSRange? = nil) -> String {
        if let range {
            let ns = (textView.text ?? "") as NSString
            guard range.location != NSNotFound,
                  range.location + range.length <= ns.length
            else { return "" }
            return ns.substring(with: range)
        }
        guard let selected = textView.selectedTextRange else { return "" }
        return textView.text(in: selected) ?? ""
    }

    /// iOS 16+ edit menu. iOS 15 uses `UIMenuItem` on `LinkTextView` instead.
    @available(iOS 16.0, *)
    static func editMenu(
        for textView: UITextView,
        range: NSRange,
        suggestedActions: [UIMenuElement],
        handler: @escaping (String) -> Void
    ) -> UIMenu {
        let selected = selectedText(in: textView, range: range)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else {
            return UIMenu(children: suggestedActions)
        }
        let quote = UIAction(
            title: actionTitle,
            image: UIImage(systemName: "text.quote")
        ) { _ in
            handler(selected)
        }
        return UIMenu(children: [quote] + suggestedActions)
    }
}
