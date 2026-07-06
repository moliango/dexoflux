import Foundation
import UIKit
import CookedHTML

final class TopicDetailViewModel: DexoObservableObject {
    var topic: DiscourseTopicDetail?
    var parsedBlocks: [Int: [AnnotatedBlock]] = [:]
    var unsupportedPostIds: Set<Int> = []
    var isLoading = false
    var isReady = false
    var isLoadingMore = false
    var isLoadingEarlier = false
    var isFilteringByOP = false
    var isJumping = false
    var jumpTargetFloor: Int?
    var errorMessage: String?

    private let api: DiscourseAPI
    private(set) var allPostIds: [Int] = []
    private var loadedPostIds: Set<Int> = []
    private(set) var loadedRangeStart: Int = 0
    private(set) var loadedRangeEnd: Int = 0
    /// Cached first post (OP) to preserve across jumpToFloor
    private var firstPost: DiscourseTopicDetail.Post?

    init(api: DiscourseAPI) {
        self.api = api
    }

    var posts: [DiscourseTopicDetail.Post] {
        topic?.postStream.posts ?? []
    }

    var opUsername: String? {
        firstPost?.username ?? posts.first?.username
    }

    var visiblePosts: [DiscourseTopicDetail.Post] {
        let base = posts.filter { !Self.isSystemActionPost($0) }
        if isFilteringByOP, let op = opUsername {
            return base.filter { $0.username == op }
        }
        return base
    }

    var canLoadMore: Bool {
        !allPostIds.isEmpty && loadedRangeEnd < allPostIds.count
    }

    var canLoadEarlier: Bool {
        loadedRangeStart > 0
    }

    var totalFloors: Int {
        allPostIds.count
    }

    /// Check if a floor (1-based) is already loaded
    func isFloorLoaded(_ floor: Int) -> Bool {
        let index = floor - 1
        guard index >= 0, index < allPostIds.count else { return false }
        return loadedPostIds.contains(allPostIds[index])
    }

    /// Find the index in `posts` array for a given floor (1-based)
    func postIndexForFloor(_ floor: Int) -> Int? {
        let index = floor - 1
        guard index >= 0, index < allPostIds.count else { return nil }
        let targetId = allPostIds[index]
        return posts.firstIndex(where: { $0.id == targetId })
    }

    /// Find the row index in `visiblePosts` for a given floor (1-based)
    func visibleRowForFloor(_ floor: Int) -> Int? {
        let index = floor - 1
        guard index >= 0, index < allPostIds.count else { return nil }
        let targetId = allPostIds[index]
        return visiblePosts.firstIndex(where: { $0.id == targetId })
    }

    func setFilteringByOP(_ enabled: Bool) {
        guard isFilteringByOP != enabled else { return }
        isFilteringByOP = enabled
        notifyChanged()
    }

    func loadTopic(id: Int, containerWidth: CGFloat) async {
        await loadTopic(id: id, containerWidth: containerWidth, retryingExplicitCancellation: false)
    }

    private func loadTopic(id: Int, containerWidth: CGFloat, retryingExplicitCancellation: Bool) async {
        isLoading = true
        isReady = false
        errorMessage = nil
        parsedBlocks = [:]
        unsupportedPostIds = []
        notifyChanged()

        do {
            let detail = try await api.fetchTopic(id: id, trackVisit: true)
            topic = detail

            // Save the full stream of post IDs
            allPostIds = detail.postStream.stream ?? detail.postStream.posts.map(\.id)
            loadedPostIds = Set(detail.postStream.posts.map(\.id))

            // Cache the first post (OP)
            firstPost = detail.postStream.posts.first

            // Set range tracking
            loadedRangeStart = 0
            if let lastLoadedId = detail.postStream.posts.last?.id,
               let lastIndex = allPostIds.firstIndex(of: lastLoadedId) {
                loadedRangeEnd = lastIndex + 1
            } else {
                loadedRangeEnd = detail.postStream.posts.count
            }

            let postsToRender = detail.postStream.posts
            guard !postsToRender.isEmpty else {
                isReady = true
                isLoading = false
                notifyChanged()
                return
            }

            // Parse all posts with annotated blocks
            for post in postsToRender {
                parseAndStore(post: post)
            }

            isReady = true
        } catch {
            #if DEBUG
            print("[TopicDetail] Load failed: \(error)")
            #endif
            if !retryingExplicitCancellation,
               !Task.isCancelled,
               Self.isExplicitlyCancelledRequest(error) {
                #if DEBUG
                print("[TopicDetail] Initial request was explicitly cancelled; retrying once")
                #endif
                do {
                    try await Task.sleep(nanoseconds: 250_000_000)
                } catch {
                    isLoading = false
                    notifyChanged()
                    return
                }
                guard !Task.isCancelled else {
                    isLoading = false
                    notifyChanged()
                    return
                }
                await loadTopic(id: id, containerWidth: containerWidth, retryingExplicitCancellation: true)
                return
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
        notifyChanged()
    }

    func loadMorePosts(containerWidth: CGFloat) async {
        guard canLoadMore, !isLoadingMore, let topicId = topic?.id else { return }
        isLoadingMore = true
        notifyChanged()

        let newEnd = min(loadedRangeEnd + 20, allPostIds.count)
        let batch = Array(allPostIds[loadedRangeEnd..<newEnd])

        guard !batch.isEmpty else {
            isLoadingMore = false
            notifyChanged()
            return
        }

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)
            let newPosts = response.postStream.posts.filter { !loadedPostIds.contains($0.id) }

            guard !newPosts.isEmpty else {
                for id in batch { loadedPostIds.insert(id) }
                loadedRangeEnd = newEnd
                isLoadingMore = false
                notifyChanged()
                return
            }

            // Sort new posts by their order in allPostIds
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = newPosts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            topic?.postStream.posts.append(contentsOf: sortedPosts)

            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }

            loadedRangeEnd = newEnd
        } catch {
            // Silently fail; user can scroll again to retry
        }

        isLoadingMore = false
        notifyChanged()
    }

    func loadEarlierPosts(containerWidth: CGFloat) async {
        guard canLoadEarlier, !isLoadingEarlier, let topicId = topic?.id else { return }
        isLoadingEarlier = true
        notifyChanged()

        let newStart = max(0, loadedRangeStart - 20)
        let batch = Array(allPostIds[newStart..<loadedRangeStart])

        guard !batch.isEmpty else {
            isLoadingEarlier = false
            notifyChanged()
            return
        }

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)
            let newPosts = response.postStream.posts.filter { !loadedPostIds.contains($0.id) }

            guard !newPosts.isEmpty else {
                for id in batch { loadedPostIds.insert(id) }
                loadedRangeStart = newStart
                isLoadingEarlier = false
                notifyChanged()
                return
            }

            // Sort new posts by their order in allPostIds
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = newPosts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            // Insert after the pinned first post (index 1) if it exists, otherwise at 0
            let insertIndex: Int
            if loadedRangeStart > 0, let fp = firstPost, posts.first?.id == fp.id {
                insertIndex = 1
            } else {
                insertIndex = 0
            }
            topic?.postStream.posts.insert(contentsOf: sortedPosts, at: insertIndex)

            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }

            loadedRangeStart = newStart
        } catch {
            // Silently fail; user can scroll again to retry
        }

        isLoadingEarlier = false
        notifyChanged()
    }

    func jumpToFloor(_ floor: Int, containerWidth: CGFloat) async {
        guard !allPostIds.isEmpty, let topicId = topic?.id else { return }

        let targetIndex = max(0, min(floor - 1, allPostIds.count - 1))
        let startIndex = targetIndex
        let endIndex = min(startIndex + 20, allPostIds.count)
        let batch = Array(allPostIds[startIndex..<endIndex])

        guard !batch.isEmpty else { return }

        isJumping = true
        jumpTargetFloor = floor
        notifyChanged()

        // Clear current posts
        topic?.postStream.posts.removeAll()
        parsedBlocks.removeAll()
        unsupportedPostIds.removeAll()
        loadedPostIds.removeAll()
        firstPost = nil

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)

            // Sort by stream order
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = response.postStream.posts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            topic?.postStream.posts = sortedPosts

            for post in sortedPosts {
                loadedPostIds.insert(post.id)
                parseAndStore(post: post)
            }

            loadedRangeStart = startIndex
            loadedRangeEnd = endIndex
        } catch {
            #if DEBUG
            print("[TopicDetail] Jump failed: \(error)")
            #endif
            errorMessage = error.localizedDescription
            jumpTargetFloor = nil
        }

        isJumping = false
        if isReady {
            // Force updateUI to re-run even if isReady was already true
            isReady = false
            isReady = true
        } else {
            isReady = true
        }
        notifyChanged()
    }

    func updatePostReaction(
        postId: Int,
        reactions: [DiscourseTopicDetail.Reaction],
        currentUserReaction: DiscourseTopicDetail.Reaction?
    ) {
        guard let index = topic?.postStream.posts.firstIndex(where: { $0.id == postId }) else { return }
        topic?.postStream.posts[index].reactions = reactions
        topic?.postStream.posts[index].reactionUsersCount = reactions.reduce(0) { $0 + $1.count }
        topic?.postStream.posts[index].currentUserReaction = currentUserReaction
        topic?.postStream.posts[index].currentUserUsedMainReaction = currentUserReaction?.id == "heart"
        notifyChanged()
    }

    func updatePostBookmark(postId: Int, bookmarked: Bool, bookmarkId: Int?) {
        guard let index = topic?.postStream.posts.firstIndex(where: { $0.id == postId }) else { return }
        topic?.postStream.posts[index].bookmarked = bookmarked
        topic?.postStream.posts[index].bookmarkId = bookmarked ? bookmarkId : nil
        notifyChanged()
    }

    func appendPostBoost(postId: Int, boost: DiscourseTopicDetail.Boost) {
        guard let index = topic?.postStream.posts.firstIndex(where: { $0.id == postId }) else { return }
        var boosts = topic?.postStream.posts[index].boosts ?? []
        if !boosts.contains(where: { $0.id == boost.id }) {
            boosts.append(boost)
        }
        topic?.postStream.posts[index].boosts = boosts
        topic?.postStream.posts[index].canBoost = false
        notifyChanged()
    }

    // MARK: - Private

    private static func isSystemActionPost(_ post: DiscourseTopicDetail.Post) -> Bool {
        normalizedActionCode(post.actionCode) != nil
    }

    private static func normalizedActionCode(_ actionCode: String?) -> String? {
        guard let actionCode = actionCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !actionCode.isEmpty
        else { return nil }
        return actionCode
    }

    private static func isExplicitlyCancelledRequest(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("request explicitly cancelled")
            || message.contains("request explicitly canceled")
            || message.contains("explicitly cancelled")
            || message.contains("explicitly canceled")
    }

    private func parseAndStore(post: DiscourseTopicDetail.Post) {
        let annotated = CookedHTMLParser.parseAnnotated(html: post.cooked, baseURL: api.baseURL)
        parsedBlocks[post.id] = annotated

        // Check if any block has no native renderer
        let hasUnsupported = annotated.contains { ab in
            !NativeContentRenderer.renderers.contains { $0.canRender(ab.block) }
        }
        if hasUnsupported {
            unsupportedPostIds.insert(post.id)
        }
    }
}
