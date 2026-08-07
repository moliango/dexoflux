import UIKit

final class TopicReadingTracker {
    private let api: DiscourseAPI
    private var topicId: Int?
    private var visiblePostNumbers: Set<Int> = []
    private var pendingTimings: [Int: Int] = [:]
    private var pendingTopicTimeMilliseconds = 0
    private var timer: Timer?
    private var lastTickDate: Date?
    private var lastFlushDate = Date()
    private var isFlushInFlight = false

    init(api: DiscourseAPI) {
        self.api = api
    }

    func start(topicId: Int) {
        if self.topicId != topicId {
            pendingTimings.removeAll()
            pendingTopicTimeMilliseconds = 0
        }
        self.topicId = topicId
        lastTickDate = Date()
        lastFlushDate = Date()
        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTickDate = nil
        visiblePostNumbers.removeAll()
        flush(force: true)
    }

    func setVisiblePostNumbers(_ postNumbers: Set<Int>) {
        visiblePostNumbers = postNumbers.filter { $0 > 0 }
        guard let topicId, let highest = visiblePostNumbers.max() else { return }
        let username = AuthManager.shared.username(for: api.baseURL)
        let before = TopicReadProgressStore.shared.highestSeen(
            topicId: topicId,
            baseURL: api.baseURL,
            username: username
        )
        TopicReadProgressStore.shared.record(
            topicId: topicId,
            highestSeen: highest,
            baseURL: api.baseURL,
            username: username
        )
        // Push list styling as the user scrolls, not only on 60s timings flush.
        if highest > before {
            NotificationCenter.default.post(
                name: .topicReadProgressDidChange,
                object: nil,
                userInfo: [
                    TopicReadProgressUserInfoKey.baseURL: api.baseURL,
                    TopicReadProgressUserInfoKey.topicId: topicId,
                    TopicReadProgressUserInfoKey.highestSeen: highest,
                ]
            )
        }
    }

    func scrolled() {
        tick()
    }

    private func tick() {
        let now = Date()
        let elapsedMilliseconds: Int
        if let lastTickDate {
            elapsedMilliseconds = min(max(Int(now.timeIntervalSince(lastTickDate) * 1000), 0), 2_000)
        } else {
            elapsedMilliseconds = 0
        }
        lastTickDate = now

        guard elapsedMilliseconds > 0, !visiblePostNumbers.isEmpty else { return }
        pendingTopicTimeMilliseconds += elapsedMilliseconds
        for postNumber in visiblePostNumbers {
            pendingTimings[postNumber, default: 0] += elapsedMilliseconds
        }

        if now.timeIntervalSince(lastFlushDate) >= 60 {
            flush(force: false)
        }
    }

    private func flush(force: Bool) {
        guard !isFlushInFlight,
              let topicId,
              pendingTopicTimeMilliseconds > 0,
              !pendingTimings.isEmpty
        else { return }

        let topicTime = pendingTopicTimeMilliseconds
        let timings = pendingTimings
        pendingTopicTimeMilliseconds = 0
        pendingTimings.removeAll()
        lastFlushDate = Date()
        isFlushInFlight = true

        Task { [weak self, api, topicId, topicTime, timings] in
            let statusCode = await api.sendTopicTimings(
                topicId: topicId,
                topicTime: topicTime,
                timings: timings
            )
            await MainActor.run {
                guard let self else { return }
                self.isFlushInFlight = false
                if let statusCode,
                   (200 ..< 300).contains(statusCode),
                   let highestSeen = timings.keys.max() {
                    TopicReadProgressStore.shared.record(
                        topicId: topicId,
                        highestSeen: highestSeen,
                        baseURL: api.baseURL,
                        username: AuthManager.shared.username(for: api.baseURL)
                    )
                    NotificationCenter.default.post(
                        name: .topicReadProgressDidChange,
                        object: nil,
                        userInfo: [
                            TopicReadProgressUserInfoKey.baseURL: api.baseURL,
                            TopicReadProgressUserInfoKey.topicId: topicId,
                            TopicReadProgressUserInfoKey.highestSeen: highestSeen,
                        ]
                    )
                } else if let highestSeen = timings.keys.max() {
                    // Even if timings upload fails, keep local progress so list/resume stay honest.
                    TopicReadProgressStore.shared.record(
                        topicId: topicId,
                        highestSeen: highestSeen,
                        baseURL: api.baseURL,
                        username: AuthManager.shared.username(for: api.baseURL)
                    )
                    NotificationCenter.default.post(
                        name: .topicReadProgressDidChange,
                        object: nil,
                        userInfo: [
                            TopicReadProgressUserInfoKey.baseURL: api.baseURL,
                            TopicReadProgressUserInfoKey.topicId: topicId,
                            TopicReadProgressUserInfoKey.highestSeen: highestSeen,
                        ]
                    )
                }
                guard !force,
                      let statusCode,
                      !(200 ..< 300).contains(statusCode)
                else { return }
                self.pendingTopicTimeMilliseconds += topicTime
                for (postNumber, milliseconds) in timings {
                    self.pendingTimings[postNumber, default: 0] += milliseconds
                }
            }
        }
    }
}
