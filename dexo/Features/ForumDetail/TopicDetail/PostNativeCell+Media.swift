import CookedHTML
import UIKit

/// Shared loader for `cookedHTMLImageURL` attachments produced by CookedHTML.
/// Used by classic `PostNativeCell` and WeChat chat bubbles.
enum CookedInlineImageLoader {
    static func loadImages(
        in textView: UITextView,
        cloudflareBaseURL: String? = nil,
        onAnyImageLoaded: (() -> Void)? = nil
    ) {
        guard let attrText = textView.attributedText else { return }
        let full = NSRange(location: 0, length: attrText.length)

        // Collect all (attachment, location, url) first — enumerateAttribute merges
        // adjacent characters that share the same URL into one range, so we must
        // iterate character-by-character inside each range.
        var entries: [(attachment: NSTextAttachment, location: Int, url: URL)] = []
        attrText.enumerateAttribute(.cookedHTMLImageURL, in: full) { value, range, _ in
            guard let urlString = value as? String,
                  let url = URL(string: urlString) else { return }
            for i in 0 ..< range.length {
                let loc = range.location + i
                if let attachment = attrText.attribute(.attachment, at: loc, effectiveRange: nil) as? NSTextAttachment {
                    entries.append((attachment, loc, url))
                }
            }
        }

        for entry in entries {
            // Same pipeline as TappableImageContainer — avoids SD failed-URL blacklist
            // trapping inline emoji/images until process death.
            ExternalImageFetcher.fetch(
                url: entry.url,
                refererBaseURL: cloudflareBaseURL
            ) { [weak textView] image in
                guard let textView, let image else { return }
                entry.attachment.image = image
                // Keep the bounds already set by the attributed string builder
                let charRange = NSRange(location: entry.location, length: 1)
                textView.textStorage.edited(.editedAttributes, range: charRange, changeInLength: 0)
                onAnyImageLoaded?()
            }
        }
    }

    /// Cancel in-flight block media under a content root (images / onebox / video / fallback).
    static func cancelMediaLoads(in view: UIView) {
        if let container = view as? TappableImageContainer {
            container.cancelImageLoad()
        } else if let signature = view as? SignatureImageView {
            signature.cancelImageLoad()
        } else if let onebox = view as? OneboxCardView {
            onebox.cancelImageLoad()
        } else if let video = view as? VideoCardView {
            video.cancelImageLoad()
        } else if let fallback = view as? FallbackBlockView {
            fallback.cancelRender()
        }

        if let stack = view as? UIStackView {
            for arranged in stack.arrangedSubviews {
                cancelMediaLoads(in: arranged)
            }
        }
        for subview in view.subviews {
            cancelMediaLoads(in: subview)
        }
    }

    /// Pause/resume animated media (GIF) while scrolling — FluxDo-style scroll busy.
    static func setAnimatedMediaPaused(_ paused: Bool, in view: UIView) {
        if let container = view as? TappableImageContainer {
            if paused {
                container.stopAnimating()
            } else {
                container.startAnimating()
            }
        }
        if let stack = view as? UIStackView {
            for arranged in stack.arrangedSubviews {
                setAnimatedMediaPaused(paused, in: arranged)
            }
        }
        for subview in view.subviews {
            setAnimatedMediaPaused(paused, in: subview)
        }
    }
}

extension PostNativeCell {
    // MARK: - Media
    // MARK: - View Setup

    func setupTextViews(in view: UIView, cloudflareBaseURL: String? = nil) {
        if let textView = view as? LinkTextView {
            textView.delegate = self
            textView.configureSpoilerIfNeeded()
            loadInlineImages(in: textView, cloudflareBaseURL: cloudflareBaseURL)
            return
        }
        if let textView = view as? UITextView {
            textView.delegate = self
            loadInlineImages(in: textView, cloudflareBaseURL: cloudflareBaseURL)
            return
        }
        for subview in view.subviews {
            setupTextViews(in: subview, cloudflareBaseURL: cloudflareBaseURL)
        }
    }

    // MARK: - Inline Image Loading

    func loadInlineImages(in textView: UITextView, cloudflareBaseURL: String? = nil) {
        CookedInlineImageLoader.loadImages(in: textView, cloudflareBaseURL: cloudflareBaseURL)
    }
}
