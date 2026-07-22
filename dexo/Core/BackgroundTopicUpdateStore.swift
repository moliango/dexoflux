import Foundation

/// 后台刷新抓到的 latest.json 原始数据缓存：首页冷启动或列表被清空时
/// 先用缓存立即渲染，再等网络刷新替换。
enum BackgroundTopicListCache {
    /// 超过该时长的缓存不再展示（宁缺毋滥的上限，正常后台刷新远比这频繁）。
    private static let maximumAge: TimeInterval = 24 * 60 * 60

    nonisolated private static func fileURL(for baseURL: String) -> URL {
        let normalized = ForumInstance.normalizedBaseURL(baseURL)
        let name = normalized
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "forum"
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DexoFlux/TopicListCache", isDirectory: true)
            .appendingPathComponent("\(name).json")
    }

    nonisolated static func save(_ rawData: Data, baseURL: String) {
        let url = fileURL(for: baseURL)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? rawData.write(to: url, options: .atomic)
    }

    nonisolated static func load(baseURL: String) -> DiscourseTopicList? {
        let url = fileURL(for: baseURL)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maximumAge,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(DiscourseTopicList.self, from: data)
    }
}

struct BackgroundTopicFingerprint: Codable, Equatable {
    let id: Int
    let postsCount: Int
    let replyCount: Int
    let lastPostedAt: String?
    let pinned: Bool

    init(
        id: Int,
        postsCount: Int,
        replyCount: Int,
        lastPostedAt: String?,
        pinned: Bool
    ) {
        self.id = id
        self.postsCount = postsCount
        self.replyCount = replyCount
        self.lastPostedAt = lastPostedAt
        self.pinned = pinned
    }

    init(topic: DiscourseTopicList.Topic) {
        self.init(
            id: topic.id,
            postsCount: topic.postsCount,
            replyCount: topic.replyCount,
            lastPostedAt: topic.lastPostedAt,
            pinned: topic.pinned == true
        )
    }

    func hasContentUpdate(comparedTo baseline: BackgroundTopicFingerprint) -> Bool {
        postsCount != baseline.postsCount
            || replyCount != baseline.replyCount
            || lastPostedAt != baseline.lastPostedAt
    }
}

final class BackgroundTopicUpdateStore {
    static let shared = BackgroundTopicUpdateStore()

    private struct ForumState: Codable {
        var baseline: [BackgroundTopicFingerprint]
        var pendingTopicIDs: [Int]
    }

    private let defaults: UserDefaults
    private let storageKey = "backgroundTopicUpdateStore.v1"
    private let maximumTopicCount = 30

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func replaceForegroundBaseline(
        _ topics: [DiscourseTopicList.Topic],
        baseURL: String
    ) {
        replaceForegroundBaseline(topics.map(BackgroundTopicFingerprint.init(topic:)), baseURL: baseURL)
    }

    func replaceForegroundBaseline(
        _ fingerprints: [BackgroundTopicFingerprint],
        baseURL: String
    ) {
        var states = loadStates()
        states[normalizedBaseURL(baseURL)] = ForumState(
            baseline: Array(fingerprints.prefix(maximumTopicCount)),
            pendingTopicIDs: []
        )
        saveStates(states)
    }

    func establishForegroundBaselineIfNeeded(
        _ topics: [DiscourseTopicList.Topic],
        baseURL: String
    ) {
        establishForegroundBaselineIfNeeded(topics.map(BackgroundTopicFingerprint.init(topic:)), baseURL: baseURL)
    }

    func establishForegroundBaselineIfNeeded(
        _ fingerprints: [BackgroundTopicFingerprint],
        baseURL: String
    ) {
        let normalizedBaseURL = normalizedBaseURL(baseURL)
        var states = loadStates()
        guard states[normalizedBaseURL] == nil else { return }
        states[normalizedBaseURL] = ForumState(
            baseline: Array(fingerprints.prefix(maximumTopicCount)),
            pendingTopicIDs: []
        )
        saveStates(states)
    }

    @discardableResult
    func processBackgroundSnapshot(
        _ topics: [DiscourseTopicList.Topic],
        baseURL: String
    ) -> [Int] {
        processBackgroundSnapshot(topics.map(BackgroundTopicFingerprint.init(topic:)), baseURL: baseURL)
    }

    @discardableResult
    func processBackgroundSnapshot(
        _ fingerprints: [BackgroundTopicFingerprint],
        baseURL: String
    ) -> [Int] {
        let normalizedBaseURL = normalizedBaseURL(baseURL)
        var states = loadStates()
        guard var state = states[normalizedBaseURL], !state.baseline.isEmpty else {
            states[normalizedBaseURL] = ForumState(
                baseline: Array(fingerprints.prefix(maximumTopicCount)),
                pendingTopicIDs: []
            )
            saveStates(states)
            return []
        }

        var baselineByID: [Int: BackgroundTopicFingerprint] = [:]
        for fingerprint in state.baseline where baselineByID[fingerprint.id] == nil {
            baselineByID[fingerprint.id] = fingerprint
        }
        let referenceTopicID = state.baseline.first(where: { !$0.pinned })?.id
        var reachedReferenceTopic = referenceTopicID == nil
        var detectedIDs: [Int] = []
        var seenIDs = Set<Int>()

        for fingerprint in fingerprints {
            if fingerprint.id == referenceTopicID {
                reachedReferenceTopic = true
            }

            let isNewBeforeReference = !reachedReferenceTopic && baselineByID[fingerprint.id] == nil
            let isUpdated = baselineByID[fingerprint.id].map {
                fingerprint.hasContentUpdate(comparedTo: $0)
            } ?? false
            if (isNewBeforeReference || isUpdated), seenIDs.insert(fingerprint.id).inserted {
                detectedIDs.append(fingerprint.id)
            }
        }

        for topicID in state.pendingTopicIDs where seenIDs.insert(topicID).inserted {
            detectedIDs.append(topicID)
        }
        state.pendingTopicIDs = Array(detectedIDs.prefix(maximumTopicCount))
        states[normalizedBaseURL] = state
        saveStates(states)
        return state.pendingTopicIDs
    }

    func pendingTopicIDs(for baseURL: String) -> [Int] {
        loadStates()[normalizedBaseURL(baseURL)]?.pendingTopicIDs ?? []
    }

    func clear(baseURL: String) {
        var states = loadStates()
        states.removeValue(forKey: normalizedBaseURL(baseURL))
        saveStates(states)
    }

    private func loadStates() -> [String: ForumState] {
        guard let data = defaults.data(forKey: storageKey),
              let states = try? JSONDecoder().decode([String: ForumState].self, from: data)
        else { return [:] }
        return states
    }

    private func saveStates(_ states: [String: ForumState]) {
        guard !states.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(states) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private func normalizedBaseURL(_ baseURL: String) -> String {
        ForumInstance.normalizedBaseURL(baseURL)
    }
}
