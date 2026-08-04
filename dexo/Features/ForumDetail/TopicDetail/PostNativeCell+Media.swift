import CookedHTML
import UIKit

extension PostNativeCell {
    // MARK: - Media
    // MARK: - View Setup

    func setupTextViews(in view: UIView) {
        if let textView = view as? LinkTextView {
            textView.delegate = self
            textView.configureSpoilerIfNeeded()
            loadInlineImages(in: textView)
            return
        }
        if let textView = view as? UITextView {
            textView.delegate = self
            loadInlineImages(in: textView)
            return
        }
        for subview in view.subviews {
            setupTextViews(in: subview)
        }
    }

    // MARK: - Inline Image Loading

    func loadInlineImages(in textView: UITextView) {
        guard let attrText = textView.attributedText else { return }
        let full = NSRange(location: 0, length: attrText.length)

        // Collect all (attachment, location, url, isEmoji) first — enumerateAttribute merges
        // adjacent characters that share the same URL into one range, so we must
        // iterate character-by-character inside each range.
        var entries: [(attachment: NSTextAttachment, location: Int, url: URL, isEmoji: Bool)] = []
        attrText.enumerateAttribute(.cookedHTMLImageURL, in: full) { value, range, _ in
            guard let urlString = value as? String,
                  let url = URL(string: urlString) else { return }
            for i in 0 ..< range.length {
                let loc = range.location + i
                if let attachment = attrText.attribute(.attachment, at: loc, effectiveRange: nil) as? NSTextAttachment {
                    // Emoji attachments have small bounds (≤ lineHeight); non-emoji have larger bounds
                    let isEmoji = attachment.bounds.width <= 24 && attachment.bounds.height <= 24
                    entries.append((attachment, loc, url, isEmoji))
                }
            }
        }

        for entry in entries {
            ForumImageLoader.loadImage(with: entry.url) { [weak textView] image in
                guard let textView, let image else { return }
                entry.attachment.image = image
                // Keep the bounds already set by the attributed string builder
                let charRange = NSRange(location: entry.location, length: 1)
                textView.textStorage.edited(.editedAttributes, range: charRange, changeInLength: 0)
            }
        }
    }

}
