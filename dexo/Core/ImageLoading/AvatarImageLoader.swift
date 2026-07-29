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
        if let cachedImage = cachedImage(for: url) {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = cachedImage
            return
        }

        // CF recovery in flight: serve cache only; don't hammer main-domain images.
        if CloudflareImageGate.shouldBlockNetworkLoad(url: url, cloudflareBaseURL: cloudflareBaseURL) {
            imageView.sd_cancelCurrentImageLoad()
            if imageView.image == nil {
                imageView.image = placeholder
            }
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
        // Skip main-domain network prefetch while CF gate is paused.
        let networkURLs = urls.filter {
            !CloudflareImageGate.shouldBlockNetworkLoad(url: $0, cloudflareBaseURL: cloudflareBaseURL)
        }
        let uniqueURLs = uniqueUnprefetchedURLs(networkURLs)
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
                    // Coalesce + pause: one shield per cooldown, not one per avatar.
                    CloudflareImageGate.reportImageChallenge(
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

    /// Memory first, then SD disk — used for fast path and CF-gated cache-only loads.
    static func cachedImageIfAvailable(for url: URL) -> UIImage? {
        cachedImage(for: url)
    }

    private static func cachedImage(for url: URL) -> UIImage? {
        let cacheKey = url as NSURL
        if let memory = inMemoryCache.object(forKey: cacheKey) {
            return memory
        }
        // SDWebImage default key is absoluteString for plain URL loads.
        if let disk = SDImageCache.shared.imageFromCache(forKey: url.absoluteString) {
            inMemoryCache.setObject(disk, forKey: cacheKey, cost: disk.avatarCacheCost)
            return disk
        }
        return nil
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
        if let cached = AvatarImageLoader.cachedImageIfAvailable(for: url) {
            completed(cached)
            return nil
        }
        if CloudflareImageGate.shouldBlockNetworkLoad(url: url, cloudflareBaseURL: cloudflareBaseURL) {
            completed(nil)
            return nil
        }
        return SDWebImageManager.shared.loadImage(
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

        if let cached = AvatarImageLoader.cachedImageIfAvailable(for: url) {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = cached
            completed?(cached, nil, .none, url)
            return
        }

        if CloudflareImageGate.shouldBlockNetworkLoad(url: url, cloudflareBaseURL: cloudflareBaseURL) {
            imageView.sd_cancelCurrentImageLoad()
            if imageView.image == nil {
                imageView.image = placeholder
            }
            completed?(nil, nil, .none, url)
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


/// Coalesces image-pipeline Cloudflare challenges and pauses main-domain image
/// network loads while clearance is being recovered.
///
/// Why: a single expired `cf_clearance` turns a home-feed avatar storm into N
/// challenge notifications and keeps the shield flashing. Cache still serves
/// hits; only uncached main-host downloads are gated.
enum CloudflareImageGate {
    private static let lock = NSLock()
    private static var pausedUntilByBase: [String: Date] = [:]
    private static var lastPostedAtByBase: [String: Date] = [:]

    /// Don't re-post challenge from images more often than this.
    private static let imagePostCooldown: TimeInterval = 12
    /// Safety auto-resume if verification-completed never arrives.
    private static let defaultPauseDuration: TimeInterval = 45

    static func normalizedKey(_ baseURL: String) -> String {
        CloudflareVerificationPolicy.normalizedBaseKey(baseURL)
    }

    /// Pause main-domain image downloads for this forum base.
    static func pause(baseURL: String, duration: TimeInterval = defaultPauseDuration) {
        let key = normalizedKey(baseURL)
        let until = Date().addingTimeInterval(duration)
        lock.lock()
        if let existing = pausedUntilByBase[key] {
            pausedUntilByBase[key] = max(existing, until)
        } else {
            pausedUntilByBase[key] = until
        }
        lock.unlock()
        DohDebugLog.record("image gate pause base=\(key) duration=\(Int(duration))s", subsystem: "CF")
    }

    static func pause(baseURL: URL, duration: TimeInterval = defaultPauseDuration) {
        pause(baseURL: baseURL.absoluteString, duration: duration)
    }

    /// Clear pause so uncached avatars/uploads can hit the network again.
    static func resume(baseURL: String) {
        let key = normalizedKey(baseURL)
        lock.lock()
        let hadPause = pausedUntilByBase[key] != nil
        pausedUntilByBase[key] = nil
        lock.unlock()
        if hadPause {
            DohDebugLog.record("image gate resume base=\(key)", subsystem: "CF")
        }
    }

    static func resume(baseURL: URL) {
        resume(baseURL: baseURL.absoluteString)
    }

    static func isPaused(baseURL: String, now: Date = Date()) -> Bool {
        let key = normalizedKey(baseURL)
        lock.lock()
        defer { lock.unlock() }
        guard let until = pausedUntilByBase[key] else { return false }
        if now < until {
            return true
        }
        pausedUntilByBase[key] = nil
        return false
    }

    static func isPaused(baseURL: URL, now: Date = Date()) -> Bool {
        isPaused(baseURL: baseURL.absoluteString, now: now)
    }

    /// True when `url` is a main-forum host asset and downloads for that forum are paused.
    static func shouldBlockNetworkLoad(url: URL, cloudflareBaseURL: String?, now: Date = Date()) -> Bool {
        guard isMainDomain(url, cloudflareBaseURL: cloudflareBaseURL) else { return false }

        if let cloudflareBaseURL, isPaused(baseURL: cloudflareBaseURL, now: now) {
            return true
        }
        if let origin = originString(for: url), isPaused(baseURL: origin, now: now) {
            return true
        }
        if let host = url.host?.lowercased(), !host.isEmpty {
            if isPaused(baseURL: "https://\(host)", now: now) { return true }
            if isPaused(baseURL: "http://\(host)", now: now) { return true }
        }
        return false
    }

    /// Image response hit a CF challenge: pause downloads and post at most once per cooldown.
    static func reportImageChallenge(baseURL: String, responseURL: URL?) {
        if CloudflareVerificationPolicy.isInVerificationGrace(baseURL: baseURL) {
            DohDebugLog.record(
                "image CF challenge ignored during grace base=\(baseURL)",
                subsystem: "CF"
            )
            return
        }

        pause(baseURL: baseURL)

        let key = normalizedKey(baseURL)
        let now = Date()
        lock.lock()
        let shouldPost: Bool
        if let last = lastPostedAtByBase[key], now.timeIntervalSince(last) < imagePostCooldown {
            shouldPost = false
        } else {
            lastPostedAtByBase[key] = now
            shouldPost = true
        }
        lock.unlock()

        guard shouldPost else {
            DohDebugLog.record(
                "image CF challenge coalesced base=\(key) response=\(responseURL?.absoluteString ?? "none")",
                subsystem: "CF"
            )
            return
        }

        DiscourseAPI.postCloudflareChallengeDetected(baseURL: baseURL, responseURL: responseURL)
    }

    // MARK: - Host helpers (same split as AvatarImageLoader / FluxDo)

    static func isMainDomain(_ url: URL, cloudflareBaseURL: String?) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if let cloudflareBaseURL,
           let baseHost = URL(string: cloudflareBaseURL)?.host?.lowercased(),
           !baseHost.isEmpty {
            if host == baseHost || host.hasSuffix("." + baseHost) {
                return true
            }
        }
        if host == "linux.do" || host.hasSuffix(".linux.do") {
            return true
        }
        return false
    }

    static func originString(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// Test hook: wipe gate state between unit tests.
    static func resetForTests() {
        lock.lock()
        pausedUntilByBase.removeAll()
        lastPostedAtByBase.removeAll()
        lock.unlock()
    }
}
