import SDWebImage
import UIKit

enum AvatarImageLoader {
    static let defaultPlaceholder = UIImage(systemName: "person.crop.circle.fill")
    static let primaryAvatarPixelSize = 120

    private static let inMemoryCache = NSCache<NSURL, UIImage>()
    private static let prefetchLock = NSLock()
    private static var prefetchedURLStrings = Set<String>()

    static let options: SDWebImageOptions = [
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
        let url = url(from: template, baseURL: baseURL, size: size)
        setImage(
            on: imageView,
            url: url,
            placeholder: placeholder,
            cloudflareBaseURL: baseURL
        )
    }

    static func setImage(
        on imageView: UIImageView,
        url: URL?,
        placeholder: UIImage? = defaultPlaceholder,
        cloudflareBaseURL: String? = nil
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
            context: context(for: url, cloudflareBaseURL: cloudflareBaseURL),
            progress: nil,
            completed: { image, _, _, _ in
                guard let image else { return }
                inMemoryCache.setObject(image, forKey: cacheKey, cost: image.avatarCacheCost)
            }
        )
    }

    static func prefetch(urls: [URL], cloudflareBaseURL: String? = nil) {
        let uniqueURLs = uniqueUnprefetchedURLs(urls)
        guard !uniqueURLs.isEmpty else { return }

        let grouped = Dictionary(grouping: uniqueURLs) {
            requestHeaderSignature(for: $0, cloudflareBaseURL: cloudflareBaseURL)
        }
        for urls in grouped.values {
            let requestContext: [SDWebImageContextOption: Any]?
            if let firstURL = urls.first {
                requestContext = context(
                    for: firstURL,
                    cloudflareBaseURL: cloudflareBaseURL
                )
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

    static func credentialsDidChange(for baseURL: String, retrying retryURLs: [URL] = []) {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return }
        let retryURLStrings = Set(retryURLs.map(\.absoluteString))
        prefetchLock.lock()
        prefetchedURLStrings = prefetchedURLStrings.filter { value in
            if retryURLStrings.contains(value) { return false }
            guard let urlHost = URL(string: value)?.host?.lowercased() else { return true }
            return urlHost != host && !urlHost.hasSuffix(".\(host)")
        }
        prefetchLock.unlock()
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

    static func context(
        for url: URL,
        cloudflareBaseURL: String? = nil
    ) -> [SDWebImageContextOption: Any]? {
        var context: [SDWebImageContextOption: Any] = [:]
        let headers = requestHeaders(for: url, cloudflareBaseURL: cloudflareBaseURL)
        if !headers.isEmpty {
            context[SDWebImageContextOption.downloadRequestModifier] = SDWebImageDownloaderRequestModifier(
                headers: headers
            )
        }

        let responseModifier = SDWebImageDownloaderResponseModifier(block: { response in
            guard let httpResponse = response as? HTTPURLResponse,
                  DiscourseAPI.isCloudflareChallengeResponse(httpResponse, data: nil)
            else { return response }

            let detectedBaseURL = cloudflareBaseURL
                ?? httpResponse.url.flatMap(Self.originString(for:))
                ?? Self.originString(for: url)
            if let detectedBaseURL {
                Task { @MainActor in
                    DiscourseAPI.postCloudflareChallengeDetected(
                        baseURL: detectedBaseURL,
                        responseURL: httpResponse.url
                    )
                }
            }
            return response
        })
        context[SDWebImageContextOption.downloadResponseModifier] = responseModifier
        return context
    }

    nonisolated private static func originString(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func requestHeaderSignature(for url: URL, cloudflareBaseURL: String? = nil) -> String {
        let headers = requestHeaders(for: url, cloudflareBaseURL: cloudflareBaseURL)
        return headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
    }

    private static func requestHeaders(
        for url: URL,
        cloudflareBaseURL: String? = nil
    ) -> [String: String] {
        // Align with FluxDo DioHttpClient image headers:
        // Accept */* + Accept-Language; main domain may need cookies;
        // third-party hosts must not send cookies (and often need forum Referer).
        var headers: [String: String] = [
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        ]

        let userAgent = WebCookieStore.shared.userAgent
        if let userAgent, !userAgent.isEmpty {
            headers["User-Agent"] = userAgent
        } else {
            headers["User-Agent"] =
                "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        }

        if isMainDomain(url, baseURL: cloudflareBaseURL) {
            let cookieHeader = WebCookieStore.shared.cookieHeader(for: url)
            if !cookieHeader.isEmpty {
                headers["Cookie"] = cookieHeader
            }
        }

        if let referer = refererHeader(for: url, baseURL: cloudflareBaseURL) {
            headers["Referer"] = referer
        }

        return headers
    }

    /// Main forum host (and subdomains) need session cookies for secure-uploads.
    /// External image hosts must stay cookieless — same split as FluxDo.
    private static func isMainDomain(_ url: URL, baseURL: String?) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if let baseURL,
           let baseHost = URL(string: baseURL)?.host?.lowercased(),
           !baseHost.isEmpty {
            if host == baseHost || host.hasSuffix("." + baseHost) {
                return true
            }
        }
        // Fallback for linux.do family when baseURL is temporarily unavailable.
        if host == "linux.do" || host.hasSuffix(".linux.do") {
            return true
        }
        return false
    }

    private static func refererHeader(for url: URL, baseURL: String?) -> String? {
        // Always attach forum origin as Referer for non-main hosts (image beds / badge APIs).
        guard !isMainDomain(url, baseURL: baseURL) else { return nil }
        guard let baseURL, let base = URL(string: baseURL), base.scheme != nil, base.host != nil else {
            return "https://linux.do/"
        }
        var components = URLComponents()
        components.scheme = base.scheme
        components.host = base.host
        components.port = base.port
        components.path = "/"
        return components.string
    }
}

enum ForumImageLoader {
    @discardableResult
    static func loadImage(
        with url: URL,
        cloudflareBaseURL: String? = nil,
        completed: @escaping (UIImage?) -> Void
    ) -> SDWebImageOperation? {
        SDWebImageManager.shared.loadImage(
            with: url,
            options: AvatarImageLoader.options,
            context: AvatarImageLoader.context(for: url, cloudflareBaseURL: cloudflareBaseURL),
            progress: nil
        ) { image, _, _, _, _, _ in
            completed(image)
        }
    }

    static func setImage(
        on imageView: UIImageView,
        url: URL?,
        placeholder: UIImage? = nil,
        cloudflareBaseURL: String? = nil,
        completed: SDExternalCompletionBlock? = nil
    ) {
        guard let url else {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = placeholder
            return
        }

        imageView.sd_setImage(
            with: url,
            placeholderImage: placeholder,
            options: AvatarImageLoader.options,
            context: AvatarImageLoader.context(for: url, cloudflareBaseURL: cloudflareBaseURL),
            progress: nil,
            completed: completed
        )
    }

    static func prefetch(urls: [URL], cloudflareBaseURL: String? = nil) {
        AvatarImageLoader.prefetch(
            urls: urls,
            cloudflareBaseURL: cloudflareBaseURL
        )
    }
}

private extension UIImage {
    var avatarCacheCost: Int {
        guard let cgImage else { return 1 }
        return max(cgImage.bytesPerRow * cgImage.height, 1)
    }
}
