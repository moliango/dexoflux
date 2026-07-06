import Foundation
import SwiftSoup

/// Extracts Discourse onebox blocks (`aside.onebox`).
enum OneboxExtractor {
    static func extract(from element: Element, options: ParseOptions) -> ContentBlock {
        // Source URL from header > a
        let sourceURL: String? = {
            guard let anchor = try? element.select("header a").first() else { return nil }
            let href = (try? anchor.attr("href")) ?? ""
            return href.isEmpty ? nil : URLResolver.resolve(href, baseURL: options.baseURL)
        }()

        // Favicon from header img
        let faviconURL: String? = {
            guard let img = try? element.select("header img").first() else { return nil }
            let src = (try? img.attr("src")) ?? ""
            return src.isEmpty ? nil : URLResolver.resolve(src, baseURL: options.baseURL)
        }()

        // Title from h3 or h4 in .onebox-body, or article title
        let title: String? = {
            if let h = try? element.select(".onebox-body h3").first() ?? element.select(".onebox-body h4").first() {
                return try? h.text()
            }
            return nil
        }()

        // Description from p in .onebox-body
        let description: String? = {
            guard let p = try? element.select(".onebox-body p").first() else { return nil }
            let text = (try? p.text()) ?? ""
            return text.isEmpty ? nil : text
        }()

        // Content image from .onebox-body img or .thumbnail img only.
        // Skip small inline images (avatars, icons) — they have explicit small dimensions
        // or classes like onebox-avatar-inline / github-icon.
        var imageURL: String?
        var imageWidth: Int?
        var imageHeight: Int?
        let selectors = [".onebox-body img", ".thumbnail img"]
        outer: for selector in selectors {
            guard let imgs = try? element.select(selector) else { continue }
            for img in imgs {
                let cls = (try? img.attr("class")) ?? ""
                if cls.contains("avatar") || cls.contains("icon") || cls.contains("emoji") {
                    continue
                }
                let w = Int((try? img.attr("width")) ?? "")
                let h = Int((try? img.attr("height")) ?? "")
                if let w, let h, w <= 80, h <= 80 {
                    continue
                }
                let src = (try? img.attr("src")) ?? ""
                if !src.isEmpty {
                    imageURL = URLResolver.resolve(src, baseURL: options.baseURL)
                    imageWidth = w
                    imageHeight = h
                    break outer
                }
            }
        }

        return .onebox(sourceURL: sourceURL, title: title, description: description, imageURL: imageURL, imageWidth: imageWidth, imageHeight: imageHeight, faviconURL: faviconURL)
    }
}
