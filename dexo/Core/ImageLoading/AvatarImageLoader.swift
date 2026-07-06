import SDWebImage
import UIKit

enum AvatarImageLoader {
    static let defaultPlaceholder = UIImage(systemName: "person.crop.circle.fill")

    private static let inMemoryCache = NSCache<NSURL, UIImage>()
    private static let prefetchLock = NSLock()
    private static var prefetchedURLStrings = Set<String>()

    private static let options: SDWebImageOptions = [
        .retryFailed,
        .continueInBackground,
        .scaleDownLargeImages,
    ]

    static func configureGlobalImageLoading() {
        SDWebImageDownloader.shared.config.maxConcurrentDownloads = 12
        SDWebImagePrefetcher.shared.maxConcurrentPrefetchCount = 6

        let cacheConfig = SDImageCache.shared.config
        cacheConfig.shouldCacheImagesInMemory = true
        cacheConfig.shouldUseWeakMemoryCache = true
        cacheConfig.maxMemoryCost = 80 * 1024 * 1024
        cacheConfig.maxMemoryCount = 900
        cacheConfig.maxDiskSize = 300 * 1024 * 1024

        inMemoryCache.countLimit = 900
        inMemoryCache.totalCostLimit = 80 * 1024 * 1024
    }

    static func url(from template: String?, baseURL: String, size: Int = 96) -> URL? {
        guard let template else { return nil }
        let sized = template
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "{size}", with: "\(size)")
        guard !sized.isEmpty else { return nil }

        if sized.hasPrefix("//") {
            return URL(string: "https:\(sized)")
        }

        if let absoluteURL = URL(string: sized), absoluteURL.scheme != nil {
            return absoluteURL
        }

        let normalizedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        guard let base = URL(string: normalizedBase) else { return URL(string: sized) }
        return URL(string: sized, relativeTo: base)?.absoluteURL
    }

    static func setImage(
        on imageView: UIImageView,
        template: String?,
        baseURL: String,
        size: Int = 96,
        placeholder: UIImage? = defaultPlaceholder
    ) {
        setImage(
            on: imageView,
            url: url(from: template, baseURL: baseURL, size: size),
            placeholder: placeholder
        )
    }

    static func setImage(
        on imageView: UIImageView,
        url: URL?,
        placeholder: UIImage? = defaultPlaceholder
    ) {
        imageView.tintColor = .tertiaryLabel
        guard let url else {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = placeholder
            return
        }

        let cacheKey = url as NSURL
        if let cachedImage = inMemoryCache.object(forKey: cacheKey) {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = cachedImage
            return
        }

        imageView.sd_setImage(
            with: url,
            placeholderImage: placeholder,
            options: options,
            context: context(for: url),
            progress: nil,
            completed: { image, _, _, _ in
                guard let image else { return }
                inMemoryCache.setObject(image, forKey: cacheKey, cost: image.avatarCacheCost)
            }
        )
    }

    static func prefetch(urls: [URL]) {
        let uniqueURLs = uniqueUnprefetchedURLs(urls)
        guard !uniqueURLs.isEmpty else { return }

        let grouped = Dictionary(grouping: uniqueURLs) { requestHeaderSignature(for: $0) }
        for urls in grouped.values {
            let requestContext: [SDWebImageContextOption: Any]?
            if let firstURL = urls.first {
                requestContext = context(for: firstURL)
            } else {
                requestContext = nil
            }

            SDWebImagePrefetcher.shared.prefetchURLs(
                urls,
                options: options,
                context: requestContext,
                progress: nil,
                completed: nil
            )
        }
    }

    private static func uniqueUnprefetchedURLs(_ urls: [URL]) -> [URL] {
        let uniqueStrings = Array(Set(urls.map(\.absoluteString))).sorted()
        prefetchLock.lock()
        defer { prefetchLock.unlock() }

        if prefetchedURLStrings.count > 1_500 {
            prefetchedURLStrings.removeAll(keepingCapacity: true)
        }

        var result: [URL] = []
        for urlString in uniqueStrings where !prefetchedURLStrings.contains(urlString) {
            prefetchedURLStrings.insert(urlString)
            if let url = URL(string: urlString) {
                result.append(url)
            }
        }
        return result
    }

    private static func context(for url: URL) -> [SDWebImageContextOption: Any]? {
        let headers = requestHeaders(for: url)
        guard !headers.isEmpty else { return nil }
        let modifier = SDWebImageDownloaderRequestModifier(headers: headers)
        return [SDWebImageContextOption.downloadRequestModifier: modifier]
    }

    private static func requestHeaderSignature(for url: URL) -> String {
        let headers = requestHeaders(for: url)
        return headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
    }

    private static func requestHeaders(for url: URL) -> [String: String] {
        var headers: [String: String] = [:]
        let cookieHeader = WebCookieStore.shared.cookieHeader(for: url)
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }

        let userAgent = WebCookieStore.shared.userAgent
        if let userAgent, !userAgent.isEmpty {
            headers["User-Agent"] = userAgent
        }
        return headers
    }
}

private extension UIImage {
    var avatarCacheCost: Int {
        guard let cgImage else { return 1 }
        return max(cgImage.bytesPerRow * cgImage.height, 1)
    }
}
