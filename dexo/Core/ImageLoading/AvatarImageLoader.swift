import SDWebImage
import UIKit

enum AvatarImageLoader {
    static let defaultPlaceholder = UIImage(systemName: "person.crop.circle.fill")
    /// Shared pixel size for home / history / bookmarks so URL keys hit the same cache entries.
    static let primaryAvatarPixelSize = 120

    /// Process-wide entry cap for shared avatar reuse across tabs.
    private static let maxInProcessEntryCount = 100_000

    /// Resolved from `AppSettings.avatarCacheSizeLimit` (500MB … 2GB).
    private static var maxInProcessMemoryBytes: Int {
        AppSettings.shared.avatarCacheSizeLimit.byteCount
    }

    private static var maxDiskCacheBytes: Int {
        AppSettings.shared.avatarCacheSizeLimit.byteCount
    }

    private static let inMemoryCache = NSCache<NSURL, UIImage>()
    private static let userAvatarCacheLock = NSLock()
    private static var userAvatarCache: [String: UserAvatarCacheEntry] = [:]
    private static var userAvatarCacheStatsByBaseURL: [String: UserAvatarCacheStats] = [:]
    private static let prefetchLock = NSLock()
    private static var prefetchedURLStrings = Set<String>()
    private static let userAvatarStatsLogEveryLookupCount = 20

    struct UserAvatarCacheEntry {
        let image: UIImage
        let url: URL
    }

    private struct UserAvatarCacheStats {
        var lookups = 0
        var hits = 0
        var misses = 0
        var stores = 0
    }

    /// Shared SD load options: prefer sync cache hits so history/bookmarks paint
    /// immediately from home-warmed entries without a network round-trip.
    static let options: SDWebImageOptions = [
        .retryFailed,
        .continueInBackground,
        .scaleDownLargeImages,
        .highPriority,
        .queryMemoryDataSync,
        .queryDiskDataSync,
    ]

    static func configureGlobalImageLoading() {
        let profile = AppSettings.shared.avatarLoadingProfile
        let cacheLimit = AppSettings.shared.avatarCacheSizeLimit
        let memoryBytes = cacheLimit.byteCount
        let diskBytes = cacheLimit.byteCount
        SDWebImageDownloader.shared.config.maxConcurrentDownloads = profile.maxConcurrentDownloads
        SDWebImagePrefetcher.shared.maxConcurrentPrefetchCount = UInt(profile.maxConcurrentPrefetchCount)

        let cacheConfig = SDImageCache.shared.config
        cacheConfig.shouldCacheImagesInMemory = true
        // Keep strong memory entries so history/bookmarks reuse home-loaded avatars.
        cacheConfig.shouldUseWeakMemoryCache = false
        cacheConfig.maxMemoryCost = UInt(memoryBytes)
        cacheConfig.maxMemoryCount = UInt(maxInProcessEntryCount)
        cacheConfig.maxDiskSize = UInt(diskBytes)
        // Do not age-expire disk avatars; only user-triggered clear (or size pressure) removes them.
        cacheConfig.maxDiskAge = -1

        inMemoryCache.countLimit = maxInProcessEntryCount
        inMemoryCache.totalCostLimit = memoryBytes
        DohDebugLog.record(
            "avatar cache limit applied memory=\(cacheLimit.title) disk=\(cacheLimit.title)",
            subsystem: "Avatar"
        )
    }

    /// Clears process + SD image caches. Only call when the user opts into clearing
    /// (settings action or `clearImageCacheOnLaunch`).
    static func clearAllCaches(completion: (() -> Void)? = nil) {
        inMemoryCache.removeAllObjects()
        userAvatarCacheLock.lock()
        userAvatarCache.removeAll(keepingCapacity: true)
        userAvatarCacheStatsByBaseURL.removeAll(keepingCapacity: true)
        userAvatarCacheLock.unlock()
        prefetchLock.lock()
        prefetchedURLStrings.removeAll(keepingCapacity: true)
        prefetchLock.unlock()
        SDImageCache.shared.clearMemory()
        SDImageCache.shared.clearDisk {
            DispatchQueue.main.async {
                completion?()
            }
        }
        DohDebugLog.record("avatar caches cleared (user-requested)", subsystem: "Avatar")
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
        userId: Int? = nil,
        size: Int = 96,
        placeholder: UIImage? = defaultPlaceholder
    ) {
        let url = url(from: template, baseURL: baseURL, size: size)
        setImage(
            on: imageView,
            url: url,
            placeholder: placeholder,
            cloudflareBaseURL: baseURL,
            avatarBaseURL: baseURL,
            userId: userId
        )
    }

    static func setImage(
        on imageView: UIImageView,
        url: URL?,
        placeholder: UIImage? = defaultPlaceholder,
        cloudflareBaseURL: String? = nil,
        avatarBaseURL: String? = nil,
        userId: Int? = nil
    ) {
        imageView.tintColor = .tertiaryLabel
        guard let url else {
            imageView.sd_cancelCurrentImageLoad()
            if let cached = cachedUserAvatar(baseURL: avatarBaseURL ?? cloudflareBaseURL, userId: userId) {
                imageView.image = cached.image
            } else {
                imageView.image = placeholder
            }
            return
        }

        let cacheKey = url as NSURL
        if let cachedImage = cachedImage(for: url) {
            imageView.sd_cancelCurrentImageLoad()
            imageView.image = cachedImage
            storeUserAvatarIfPossible(
                cachedImage,
                url: url,
                baseURL: avatarBaseURL ?? cloudflareBaseURL,
                userId: userId
            )
            return
        }

        let cachedUserAvatar = cachedUserAvatar(baseURL: avatarBaseURL ?? cloudflareBaseURL, userId: userId)
        if let cachedUserAvatar {
            imageView.image = cachedUserAvatar.image
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
            placeholderImage: cachedUserAvatar?.image ?? placeholder,
            options: options,
            context: context(for: url, cloudflareBaseURL: cloudflareBaseURL),
            progress: nil,
            completed: { image, _, _, _ in
                guard let image else { return }
                inMemoryCache.setObject(image, forKey: cacheKey, cost: image.avatarCacheCost)
                storeUserAvatarIfPossible(
                    image,
                    url: url,
                    baseURL: avatarBaseURL ?? cloudflareBaseURL,
                    userId: userId
                )
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
                  let detection = DiscourseAPI.cloudflareChallengeDetection(httpResponse, data: nil)
            else { return response }

            let detectedBaseURL = cloudflareBaseURL
                ?? httpResponse.url.flatMap(Self.originString(for:))
                ?? Self.originString(for: url)
            if let detectedBaseURL {
                Task { @MainActor in
                    // Coalesce + pause: one shield per cooldown, not one per avatar.
                    CloudflareImageGate.reportImageChallenge(
                        baseURL: detectedBaseURL,
                        responseURL: httpResponse.url,
                        source: "image.avatar",
                        detection: detection
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

    static func cachedUserAvatar(baseURL: String?, userId: Int?) -> UserAvatarCacheEntry? {
        guard let cacheKey = userAvatarCacheKey(baseURL: baseURL, userId: userId),
              let statsKey = normalizedUserAvatarStatsKey(baseURL: baseURL)
        else { return nil }
        userAvatarCacheLock.lock()
        let entry = userAvatarCache[cacheKey]
        recordUserAvatarCacheLookupLocked(baseURL: statsKey, hit: entry != nil)
        userAvatarCacheLock.unlock()
        return entry
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

    private static func storeUserAvatarIfPossible(
        _ image: UIImage,
        url: URL,
        baseURL: String?,
        userId: Int?
    ) {
        guard let key = userAvatarCacheKey(baseURL: baseURL, userId: userId),
              let statsKey = normalizedUserAvatarStatsKey(baseURL: baseURL)
        else { return }
        userAvatarCacheLock.lock()
        userAvatarCache[key] = UserAvatarCacheEntry(image: image, url: url)
        recordUserAvatarCacheStoreLocked(baseURL: statsKey)
        // Soft trim: drop ~10% oldest-iteration keys when over cap (keeps recent hot set).
        if userAvatarCache.count > maxInProcessEntryCount {
            let overflow = userAvatarCache.count - maxInProcessEntryCount
            let trimCount = max(overflow, maxInProcessEntryCount / 10)
            let keysToDrop = Array(userAvatarCache.keys.prefix(trimCount))
            for dropKey in keysToDrop where dropKey != key {
                userAvatarCache.removeValue(forKey: dropKey)
            }
        }
        userAvatarCacheLock.unlock()
    }

    private static func userAvatarCacheKey(baseURL: String?, userId: Int?) -> String? {
        guard let baseURL, let userId, userId > 0 else { return nil }
        let normalizedBaseURL = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        guard !normalizedBaseURL.isEmpty else { return nil }
        return "\(normalizedBaseURL)#\(userId)"
    }

    private static func normalizedUserAvatarStatsKey(baseURL: String?) -> String? {
        guard let baseURL else { return nil }
        let normalizedBaseURL = baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return normalizedBaseURL.isEmpty ? nil : normalizedBaseURL
    }

    private static func recordUserAvatarCacheLookupLocked(baseURL: String, hit: Bool) {
        var stats = userAvatarCacheStatsByBaseURL[baseURL] ?? UserAvatarCacheStats()
        stats.lookups += 1
        if hit {
            stats.hits += 1
        } else {
            stats.misses += 1
        }
        userAvatarCacheStatsByBaseURL[baseURL] = stats
        logUserAvatarCacheStatsIfNeeded(baseURL: baseURL, stats: stats)
    }

    private static func recordUserAvatarCacheStoreLocked(baseURL: String) {
        var stats = userAvatarCacheStatsByBaseURL[baseURL] ?? UserAvatarCacheStats()
        stats.stores += 1
        userAvatarCacheStatsByBaseURL[baseURL] = stats
    }

    private static func logUserAvatarCacheStatsIfNeeded(baseURL: String, stats: UserAvatarCacheStats) {
        guard stats.lookups > 0,
              stats.lookups % userAvatarStatsLogEveryLookupCount == 0
        else { return }
        let hitRate = Int((Double(stats.hits) / Double(stats.lookups) * 100).rounded())
        DohDebugLog.record(
            "avatar user cache stats base=\(baseURL) lookups=\(stats.lookups) hits=\(stats.hits) misses=\(stats.misses) hitRate=\(hitRate)% stores=\(stats.stores)",
            subsystem: "Avatar"
        )
    }

    static func storeUserAvatarForTesting(
        _ image: UIImage,
        url: URL,
        baseURL: String?,
        userId: Int?
    ) {
        storeUserAvatarIfPossible(image, url: url, baseURL: baseURL, userId: userId)
    }

    static func cachedUserAvatarForTesting(baseURL: String?, userId: Int?) -> UserAvatarCacheEntry? {
        cachedUserAvatar(baseURL: baseURL, userId: userId)
    }

    static func clearUserAvatarCacheForTesting() {
        userAvatarCacheLock.lock()
        userAvatarCache.removeAll(keepingCapacity: true)
        userAvatarCacheStatsByBaseURL.removeAll(keepingCapacity: true)
        userAvatarCacheLock.unlock()
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

    /// Image response hit a CF challenge: pause downloads and notify recovery at most once per cooldown.
    ///
    /// Avatar/content storms are coalesced by `imagePostCooldown` so we still only arm one
    /// recovery cycle (shield + background verify → user sheet if needed), not one per tile.
    /// `shouldNotify: true` is required — silent pause alone left images blank with no UI.
    static func reportImageChallenge(
        baseURL: String,
        responseURL: URL?,
        source: String = "image",
        detection: CloudflareChallengeDetection? = nil
    ) {
        if CloudflareVerificationPolicy.isInVerificationGrace(baseURL: baseURL) {
            DohDebugLog.record(
                "image CF challenge ignored during grace source=\(source) base=\(baseURL) \(detection?.logSummary ?? "response=\(responseURL?.absoluteString ?? "none")")",
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
                "image CF challenge coalesced source=\(source) base=\(key) \(detection?.logSummary ?? "response=\(responseURL?.absoluteString ?? "none")")",
                subsystem: "CF"
            )
            return
        }

        DiscourseAPI.handleCloudflareChallengeDetected(
            baseURL: baseURL,
            responseURL: responseURL,
            source: source,
            routePath: nil,
            method: nil,
            detection: detection,
            shouldNotify: true
        )
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
