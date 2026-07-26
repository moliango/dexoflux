import SDWebImage
import UIKit

/// FluxDo-aligned external image download path.
///
/// FluxDo uses Dio with:
/// - `Accept: */*`
/// - `Accept-Language: zh-CN,zh;q=0.9,en;q=0.8`
/// - User-Agent
/// - no cookies for third-party hosts
/// - forum origin as Referer for external hosts
///
/// SDWebImage alone has been leaving external badge/image beds as gray
/// placeholders, so content images fall back to this URLSession path.
enum ExternalImageFetcher {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    private static let inflightLock = NSLock()
    private static var inflight: [String: [(UIImage?) -> Void]] = [:]

    static func fetch(
        url: URL,
        refererBaseURL: String?,
        completion: @escaping (UIImage?) -> Void
    ) {
        let cacheKey = url.absoluteString
        if let cached = SDImageCache.shared.imageFromCache(forKey: cacheKey) {
            completion(cached)
            return
        }

        inflightLock.lock()
        if inflight[cacheKey] != nil {
            inflight[cacheKey]?.append(completion)
            inflightLock.unlock()
            return
        }
        inflight[cacheKey] = [completion]
        inflightLock.unlock()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")

        let userAgent = WebCookieStore.shared.userAgent
            ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        if let referer = refererHeader(baseURL: refererBaseURL) {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        // Only attach cookies for forum hosts (secure-uploads). External beds stay cookieless.
        if isMainDomain(url, baseURL: refererBaseURL) {
            let cookie = WebCookieStore.shared.cookieHeader(for: url)
            if !cookie.isEmpty {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
        }

        let task = session.dataTask(with: request) { data, response, _ in
            let image: UIImage? = {
                guard let data, !data.isEmpty else { return nil }
                if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
                    return nil
                }
                // Prefer animated decoder, fall back to static.
                if let animated = SDAnimatedImage(data: data) {
                    return animated
                }
                return UIImage(data: data)
            }()

            if let image {
                SDImageCache.shared.store(image, forKey: cacheKey, completion: nil)
            }

            let callbacks: [(UIImage?) -> Void]
            inflightLock.lock()
            callbacks = inflight.removeValue(forKey: cacheKey) ?? []
            inflightLock.unlock()

            DispatchQueue.main.async {
                for callback in callbacks {
                    callback(image)
                }
            }
        }
        task.resume()
    }

    private static func isMainDomain(_ url: URL, baseURL: String?) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if let baseURL,
           let baseHost = URL(string: baseURL)?.host?.lowercased(),
           !baseHost.isEmpty {
            if host == baseHost || host.hasSuffix("." + baseHost) {
                return true
            }
        }
        return host == "linux.do" || host.hasSuffix(".linux.do")
    }

    private static func refererHeader(baseURL: String?) -> String? {
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
