import Foundation
import UIKit

/// Parses `dexo://` and forum `https://…/t/…` URLs into in-app routes.
enum DexoDeepLinkRouter {
    enum Destination: Equatable {
        case topic(topicId: Int, postNumber: Int?, baseURL: String?)
        case readLater
        case notifications
    }

    static func destination(from url: URL) -> Destination? {
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "dexo" || scheme == "dexoflux" {
            return parseAppScheme(url)
        }
        if scheme == "http" || scheme == "https" {
            return parseHTTPS(url)
        }
        return nil
    }

    static func handle(_ url: URL, defaultBaseURL: String) -> Bool {
        guard let destination = destination(from: url) else { return false }
        switch destination {
        case .topic(let topicId, let postNumber, let baseURL):
            let route = ForumNotificationRoute(
                baseURL: baseURL ?? defaultBaseURL,
                notificationId: nil,
                topicId: topicId,
                postNumber: postNumber,
                postId: nil
            )
            Task { @MainActor in
                ForumNotificationRouteStore.shared.enqueue(route)
                ForumNotificationRoutePresenter.presentPendingRouteIfNeeded()
            }
            return true
        case .readLater:
            Task { @MainActor in
                DexoInAppRouteStore.shared.enqueue(.readLater)
                DexoInAppRoutePresenter.presentPendingIfNeeded()
            }
            return true
        case .notifications:
            Task { @MainActor in
                let route = ForumNotificationRoute(
                    baseURL: defaultBaseURL,
                    notificationId: nil,
                    topicId: nil,
                    postNumber: nil,
                    postId: nil
                )
                ForumNotificationRouteStore.shared.enqueue(route)
                ForumNotificationRoutePresenter.presentPendingRouteIfNeeded()
            }
            return true
        }
    }

    private static func parseAppScheme(_ url: URL) -> Destination? {
        // dexo://topic/123/4  | dexo://t/123/4 | dexo://read-later | dexo://notifications
        let host = (url.host ?? "").lowercased()
        let parts = url.path.split(separator: "/").map(String.init)
        let head = host.isEmpty ? parts.first?.lowercased() : host
        let rest: [String]
        if host.isEmpty {
            rest = Array(parts.dropFirst())
        } else {
            rest = parts
        }

        switch head {
        case "topic", "t":
            guard let idString = rest.first, let topicId = Int(idString), topicId > 0 else { return nil }
            let postNumber = rest.count > 1 ? Int(rest[1]) : nil
            return .topic(topicId: topicId, postNumber: postNumber, baseURL: nil)
        case "read-later", "readlater", "later":
            return .readLater
        case "notifications", "notification":
            return .notifications
        default:
            // dexo://123/4  bare id
            if let topicId = Int(head ?? ""), topicId > 0 {
                let postNumber = rest.first.flatMap(Int.init)
                return .topic(topicId: topicId, postNumber: postNumber, baseURL: nil)
            }
            return nil
        }
    }

    private static func parseHTTPS(_ url: URL) -> Destination? {
        // Prefer matching default forum host; also accept any /t/ path for installed forums.
        let forums = (try? DatabaseManager.shared.fetchAllForums()) ?? [DatabaseManager.shared.defaultForum()]
        for forum in forums {
            if let info = DiscourseTopicLinkParser.parse(url: url, allowedHost: host(from: forum.baseURL) ?? "") {
                return .topic(topicId: info.topicId, postNumber: info.postNumber, baseURL: forum.baseURL)
            }
        }
        // Fallback: parse path even if host is linux.do-like without DB match
        if let host = url.host,
           let info = DiscourseTopicLinkParser.parse(url: url, allowedHost: host) {
            return .topic(topicId: info.topicId, postNumber: info.postNumber, baseURL: "https://\(host)")
        }
        return nil
    }

    private static func host(from baseURL: String) -> String? {
        if let url = URL(string: baseURL), let host = url.host { return host.lowercased() }
        return nil
    }
}

enum DexoInAppRoute: Equatable {
    case readLater
}

@MainActor
final class DexoInAppRouteStore: DexoObservableObject {
    static let shared = DexoInAppRouteStore()
    private(set) var pending: DexoInAppRoute?

    private override init() { super.init() }

    func enqueue(_ route: DexoInAppRoute) {
        pending = route
        notifyChanged()
    }

    func consume() -> DexoInAppRoute? {
        defer { pending = nil }
        return pending
    }
}

@MainActor
enum DexoInAppRoutePresenter {
    static func presentPendingIfNeeded() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0.delegate as? SceneDelegate)?.window })
            .first
        else { return }
        presentPendingIfNeeded(in: window)
    }

    static func presentPendingIfNeeded(in window: UIWindow) {
        guard let route = DexoInAppRouteStore.shared.consume() else { return }
        guard let container = window.rootViewController as? ForumContainerViewController
            ?? window.rootViewController?.children.compactMap({ $0 as? ForumContainerViewController }).first
        else {
            DexoInAppRouteStore.shared.enqueue(route)
            return
        }
        container.handleInAppRoute(route)
    }
}
