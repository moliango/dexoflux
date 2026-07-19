import Foundation
import UIKit
import CookedHTML

struct TopicDetailPostHTML: Sendable {
    let postId: Int
    let cooked: String
}

struct TopicDetailParsedPost: Sendable {
    let postId: Int
    let annotatedBlocks: [AnnotatedBlock]
    let hasUnsupportedBlocks: Bool
}

enum TopicDetailHTMLParsing {
    nonisolated static func parse(posts: [TopicDetailPostHTML], baseURL: String) async -> [TopicDetailParsedPost] {
        guard posts.count > 1 else {
            return posts.map { parse(post: $0, baseURL: baseURL) }
        }

        return await withTaskGroup(
            of: (Int, TopicDetailParsedPost).self,
            returning: [TopicDetailParsedPost].self
        ) { group in
            for (index, post) in posts.enumerated() {
                group.addTask(priority: .userInitiated) {
                    (index, parse(post: post, baseURL: baseURL))
                }
            }

            var parsedPosts = Array<TopicDetailParsedPost?>(repeating: nil, count: posts.count)
            for await (index, parsedPost) in group {
                parsedPosts[index] = parsedPost
            }
            return parsedPosts.compactMap { $0 }
        }
    }

    nonisolated private static func parse(post: TopicDetailPostHTML, baseURL: String) -> TopicDetailParsedPost {
        let annotated = CookedHTMLParser.parseAnnotated(html: post.cooked, baseURL: baseURL)
        return TopicDetailParsedPost(
            postId: post.postId,
            annotatedBlocks: annotated,
            hasUnsupportedBlocks: annotated.contains { !canRenderNatively($0.block) }
        )
    }

    nonisolated private static func canRenderNatively(_ block: ContentBlock) -> Bool {
        switch block {
        case .paragraph,
             .heading,
             .codeBlock,
             .image,
             .onebox,
             .video,
             .list,
             .poll,
             .table,
             .divider:
            return true
        case .blockquote(let blocks), .spoiler(let blocks):
            return blocks.allSatisfy(canRenderNatively)
        case .discourseQuote(_, _, _, _, _, _, _, let content):
            return content.allSatisfy(canRenderNatively)
        case .details(_, let content):
            return content.allSatisfy(canRenderNatively)
        case .rawHTML:
            return false
        }
    }
}

enum TopicDetailPollResultMerger {
    static func mergeInitialPollState(
        blocks: [AnnotatedBlock],
        post: DiscourseTopicDetail.Post
    ) -> [AnnotatedBlock] {
        guard !post.polls.isEmpty else { return blocks }
        return blocks.map { annotatedBlock in
            AnnotatedBlock(
                block: mergeInitialPollState(
                    block: annotatedBlock.block,
                    pollResults: DiscoursePollVoteResponse(polls: post.polls),
                    pollsVotes: post.pollsVotes
                ),
                sourceHTML: annotatedBlock.sourceHTML
            )
        }
    }

    static func merge(
        blocks: [AnnotatedBlock],
        voteResponse: DiscoursePollVoteResponse,
        submittedOptionIds: Set<String>
    ) -> [AnnotatedBlock] {
        return blocks.map { annotatedBlock in
            AnnotatedBlock(
                block: merge(block: annotatedBlock.block, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds),
                sourceHTML: annotatedBlock.sourceHTML
            )
        }
    }

    static func merged(
        _ blocks: [AnnotatedBlock],
        voteResponse: DiscoursePollVoteResponse,
        submittedOptionIds: Set<String>
    ) -> (blocks: [AnnotatedBlock], didChange: Bool) {
        let mergedBlocks = merge(blocks: blocks, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds)
        return (mergedBlocks, mergedBlocks.map(\.block) != blocks.map(\.block))
    }

    private static func mergeInitialPollState(
        blocks: [ContentBlock],
        pollResults: DiscoursePollVoteResponse,
        pollsVotes: [String: [String]]
    ) -> [ContentBlock] {
        blocks.map { mergeInitialPollState(block: $0, pollResults: pollResults, pollsVotes: pollsVotes) }
    }

    private static func mergeInitialPollState(
        block: ContentBlock,
        pollResults: DiscoursePollVoteResponse,
        pollsVotes: [String: [String]]
    ) -> ContentBlock {
        switch block {
        case .poll(let poll):
            guard let result = pollResults.poll(named: poll.name) else { return .poll(poll) }
            return .poll(merge(
                poll: poll,
                result: result,
                submittedOptionIds: selectedOptionIds(for: poll.name, pollsVotes: pollsVotes)
            ))
        case .blockquote(let blocks):
            return .blockquote(blocks: mergeInitialPollState(blocks: blocks, pollResults: pollResults, pollsVotes: pollsVotes))
        case .spoiler(let blocks):
            return .spoiler(blocks: mergeInitialPollState(blocks: blocks, pollResults: pollResults, pollsVotes: pollsVotes))
        case .discourseQuote(let username, let avatarURL, let topicTitle, let topicURL, let categoryName, let categoryURL, let quotePostNumber, let content):
            return .discourseQuote(
                username: username,
                avatarURL: avatarURL,
                topicTitle: topicTitle,
                topicURL: topicURL,
                categoryName: categoryName,
                categoryURL: categoryURL,
                quotePostNumber: quotePostNumber,
                content: mergeInitialPollState(blocks: content, pollResults: pollResults, pollsVotes: pollsVotes)
            )
        case .details(let summary, let content):
            return .details(
                summary: summary,
                content: mergeInitialPollState(blocks: content, pollResults: pollResults, pollsVotes: pollsVotes)
            )
        case .list(let ordered, let items):
            let mergedItems = items.map { item in
                ListItem(
                    content: item.content,
                    children: mergeInitialPollState(blocks: item.children, pollResults: pollResults, pollsVotes: pollsVotes)
                )
            }
            return .list(ordered: ordered, items: mergedItems)
        case .table(let headers, let rows):
            return .table(
                headers: headers.map { mergeInitialPollState(blocks: $0, pollResults: pollResults, pollsVotes: pollsVotes) },
                rows: rows.map { row in
                    row.map { mergeInitialPollState(blocks: $0, pollResults: pollResults, pollsVotes: pollsVotes) }
                }
            )
        case .paragraph,
             .heading,
             .codeBlock,
             .image,
             .onebox,
             .video,
             .divider,
             .rawHTML:
            return block
        }
    }

    private static func merge(
        blocks: [ContentBlock],
        voteResponse: DiscoursePollVoteResponse,
        submittedOptionIds: Set<String>
    ) -> [ContentBlock] {
        blocks.map { merge(block: $0, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds) }
    }

    private static func merge(
        block: ContentBlock,
        voteResponse: DiscoursePollVoteResponse,
        submittedOptionIds: Set<String>
    ) -> ContentBlock {
        switch block {
        case .poll(let poll):
            if let result = voteResponse.poll(named: poll.name) {
                return .poll(merge(poll: poll, result: result, submittedOptionIds: submittedOptionIds))
            }
            return .poll(mergeSubmittedVoteFallback(poll: poll, submittedOptionIds: submittedOptionIds))
        case .blockquote(let blocks):
            return .blockquote(blocks: merge(blocks: blocks, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds))
        case .spoiler(let blocks):
            return .spoiler(blocks: merge(blocks: blocks, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds))
        case .discourseQuote(let username, let avatarURL, let topicTitle, let topicURL, let categoryName, let categoryURL, let quotePostNumber, let content):
            return .discourseQuote(
                username: username,
                avatarURL: avatarURL,
                topicTitle: topicTitle,
                topicURL: topicURL,
                categoryName: categoryName,
                categoryURL: categoryURL,
                quotePostNumber: quotePostNumber,
                content: merge(blocks: content, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds)
            )
        case .details(let summary, let content):
            return .details(
                summary: summary,
                content: merge(blocks: content, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds)
            )
        case .list(let ordered, let items):
            let mergedItems = items.map { item in
                ListItem(
                    content: item.content,
                    children: merge(blocks: item.children, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds)
                )
            }
            return .list(ordered: ordered, items: mergedItems)
        case .table(let headers, let rows):
            return .table(
                headers: headers.map { merge(blocks: $0, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds) },
                rows: rows.map { row in
                    row.map { merge(blocks: $0, voteResponse: voteResponse, submittedOptionIds: submittedOptionIds) }
                }
            )
        case .paragraph,
             .heading,
             .codeBlock,
             .image,
             .onebox,
             .video,
             .divider,
             .rawHTML:
            return block
        }
    }

    private static func mergeSubmittedVoteFallback(
        poll: PollBlock,
        submittedOptionIds: Set<String>
    ) -> PollBlock {
        let submittedIds = normalizedOptionIds(submittedOptionIds)
        guard !submittedIds.isEmpty,
              poll.options.contains(where: { option in option.id.map { submittedIds.contains($0) } ?? false })
        else {
            return poll
        }

        let knownVoteTotal = poll.options.compactMap(\.voteCount).reduce(0, +)
        let currentTotal = max(poll.votersCount ?? 0, knownVoteTotal)
        let wasAlreadySelected = poll.options.contains { option in
            guard let id = option.id else { return false }
            return submittedIds.contains(id) && option.isSelected
        }
        let totalVotes = max(currentTotal + (wasAlreadySelected ? 0 : 1), 1)

        let options = poll.options.map { option in
            guard let id = option.id else { return option }
            let isSubmitted = submittedIds.contains(id)
            let voteCount: Int?
            if isSubmitted {
                voteCount = max((option.voteCount ?? 0) + (wasAlreadySelected ? 0 : 1), 1)
            } else {
                voteCount = option.voteCount
            }
            return PollOption(
                id: option.id,
                text: option.text,
                voteCount: voteCount,
                percentageText: percentageText(voteCount: voteCount, totalVotes: totalVotes) ?? option.percentageText,
                isSelected: isSubmitted
            )
        }

        return PollBlock(
            name: poll.name,
            status: poll.status,
            type: poll.type,
            options: options,
            votersText: poll.votersText,
            votersCount: totalVotes,
            minSelections: poll.minSelections,
            maxSelections: poll.maxSelections,
            resultsMode: poll.resultsMode,
            isPublic: poll.isPublic
        )
    }

    private static func merge(
        poll: PollBlock,
        result: DiscoursePollVoteResponse.Poll,
        submittedOptionIds: Set<String>
    ) -> PollBlock {
        var resultOptionsById: [String: DiscoursePollVoteResponse.Option] = [:]
        for option in result.options {
            guard let id = option.id else { continue }
            resultOptionsById[id] = option
        }

        let fallbackTotal = result.options.compactMap(\.voteCount).reduce(0, +)
        let totalVotes = result.votersCount ?? poll.votersCount ?? (fallbackTotal > 0 ? fallbackTotal : nil)
        let options = poll.options.map { option in
            guard let id = option.id,
                  let resultOption = resultOptionsById[id]
            else {
                return PollOption(
                    id: option.id,
                    text: option.text,
                    voteCount: option.voteCount,
                    percentageText: option.percentageText,
                    isSelected: option.id.map { submittedOptionIds.contains($0) } ?? option.isSelected
                )
            }

            let voteCount = resultOption.voteCount ?? option.voteCount
            return PollOption(
                id: option.id,
                text: option.text,
                voteCount: voteCount,
                percentageText: resultOption.percentageText
                    ?? option.percentageText
                    ?? percentageText(voteCount: voteCount, totalVotes: totalVotes),
                isSelected: resultOption.isSelected ?? (submittedOptionIds.contains(id) || option.isSelected)
            )
        }

        return PollBlock(
            name: poll.name ?? result.name,
            status: result.status ?? poll.status,
            type: result.type ?? poll.type,
            options: options,
            votersText: poll.votersText,
            votersCount: totalVotes,
            minSelections: result.minSelections ?? poll.minSelections,
            maxSelections: result.maxSelections ?? poll.maxSelections,
            resultsMode: result.resultsMode ?? poll.resultsMode,
            isPublic: result.isPublic ?? poll.isPublic
        )
    }

    private static func normalizedOptionIds(_ optionIds: Set<String>) -> Set<String> {
        Set(optionIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private static func selectedOptionIds(for pollName: String?, pollsVotes: [String: [String]]) -> Set<String> {
        guard !pollsVotes.isEmpty else { return [] }
        let normalizedName = normalizedPollName(pollName)
        if let normalizedName,
           let match = pollsVotes.first(where: { normalizedPollName($0.key) == normalizedName }) {
            return normalizedOptionIds(Set(match.value))
        }
        if pollsVotes.count == 1, let onlyVotes = pollsVotes.values.first {
            return normalizedOptionIds(Set(onlyVotes))
        }
        return []
    }

    private static func normalizedPollName(_ name: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func percentageText(voteCount: Int?, totalVotes: Int?) -> String? {
        guard let voteCount, let totalVotes, totalVotes > 0 else { return nil }
        let percent = Double(voteCount) / Double(totalVotes) * 100
        let rounded = (percent * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))%"
        }
        return "\(rounded)%"
    }
}

enum TopicDetailPaginationPolicy {
    static func canStartEarlier(
        isLoadingEarlier: Bool,
        isLoadingMore: Bool,
        isJumping: Bool
    ) -> Bool {
        !isLoadingEarlier && !isLoadingMore && !isJumping
    }

    static func canStartMore(
        isLoadingEarlier: Bool,
        isLoadingMore: Bool,
        isJumping: Bool
    ) -> Bool {
        !isLoadingEarlier && !isLoadingMore && !isJumping
    }

    static func shouldRestoreEarlierAnchor(
        hasAnchor: Bool,
        isLoadingEarlier: Bool,
        snapshotChanged: Bool
    ) -> Bool {
        hasAnchor && !isLoadingEarlier && snapshotChanged
    }
}

enum TopicDetailSnapshotPolicy {
    enum Decision: Equatable {
        case skip
        case apply
        case queue
    }

    static func decision(
        isApplying: Bool,
        currentItemIDs: [Int],
        requestedItemIDs: [Int]
    ) -> Decision {
        if isApplying { return .queue }
        return currentItemIDs == requestedItemIDs ? .skip : .apply
    }
}

final class TopicDetailViewModel: DexoObservableObject {
    var topic: DiscourseTopicDetail?
    private(set) var category: DiscourseCategory?
    private(set) var categoryPresentation: TopicCategoryBadgePresentation?
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
    private var parseGeneration = 0
    private var categoryMetadataTask: Task<Void, Never>?
    private var categoryMetadataCategoryId: Int?
    private var loadedCategoryMetadataId: Int?

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
        parseGeneration += 1
        let generation = parseGeneration
        notifyChanged()

        do {
            let detail = try await api.fetchTopic(id: id, trackVisit: true)
            topic = detail
            startLoadingCategoryMetadata(for: detail.categoryId)

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
            guard await parseAndStore(posts: postsToRender, generation: generation) else { return }

            isReady = true
        } catch {
            #if DEBUG
            print("[TopicDetail] Load failed: \(error)")
            #endif
            if !retryingExplicitCancellation,
               !Task.isCancelled,
               DiscourseAPI.isExplicitlyCancelledRequest(error) {
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

    private func startLoadingCategoryMetadata(for categoryId: Int?) {
        guard let categoryId else {
            categoryMetadataTask?.cancel()
            categoryMetadataTask = nil
            categoryMetadataCategoryId = nil
            loadedCategoryMetadataId = nil
            category = nil
            categoryPresentation = nil
            return
        }
        if loadedCategoryMetadataId == categoryId { return }
        if categoryMetadataCategoryId == categoryId, categoryMetadataTask != nil { return }

        if let cachedCategory = DiscourseTaxonomySessionStore.category(id: categoryId, for: api.baseURL) {
            let cachedParent = cachedCategory.parentCategoryId.flatMap {
                DiscourseTaxonomySessionStore.category(id: $0, for: api.baseURL)
            }
            category = cachedCategory
            categoryPresentation = TopicCategoryBadgePresentation.resolve(
                category: cachedCategory,
                parent: cachedParent,
                displayName: cachedCategory.displayName(parent: cachedParent),
                baseURL: api.baseURL
            )
            loadedCategoryMetadataId = categoryId
            return
        }

        if category?.id != categoryId {
            loadedCategoryMetadataId = nil
            let seededCategory = LinuxDoCategoryCatalog.category(id: categoryId, baseURL: api.baseURL)
            let seededParent = seededCategory?.parentCategoryId.flatMap {
                LinuxDoCategoryCatalog.category(id: $0, baseURL: api.baseURL)
            }
            category = seededCategory
            categoryPresentation = TopicCategoryBadgePresentation.resolve(
                category: seededCategory,
                parent: seededParent,
                displayName: seededCategory?.displayName(parent: seededParent),
                baseURL: api.baseURL
            )
        }

        let refreshBaseURL = api.baseURL
        categoryMetadataTask?.cancel()
        categoryMetadataCategoryId = categoryId
        categoryMetadataTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.categoryMetadataCategoryId == categoryId {
                    self.categoryMetadataTask = nil
                    self.categoryMetadataCategoryId = nil
                }
            }

            do {
                let categories: [DiscourseCategory]
                if DiscourseTaxonomySessionStore.beginRefresh(for: refreshBaseURL) {
                    defer { DiscourseTaxonomySessionStore.endRefresh(for: refreshBaseURL) }
                    categories = try await self.api.fetchSiteCategories()
                    try Task.checkCancellation()
                    DiscourseTaxonomySessionStore.replace(categories: categories, for: refreshBaseURL)
                } else {
                    categories = await DiscourseTaxonomySessionStore.waitForRefresh(for: refreshBaseURL)
                    try Task.checkCancellation()
                }
                self.applyCategoryMetadata(categories, categoryId: categoryId)
            } catch is CancellationError {
                return
            } catch {
                DohDebugLog.record(
                    "topic detail category metadata load failed: \(error.localizedDescription)",
                    subsystem: "Category"
                )
            }
        }
    }

    private func applyCategoryMetadata(_ categories: [DiscourseCategory], categoryId: Int) {
        guard topic?.categoryId == categoryId else { return }
        let index = DiscourseCategoryIndex(categories: categories, source: .site)
        guard let category = index[categoryId] else { return }
        let parent = category.parentCategoryId.flatMap { index[$0] }
        self.category = category
        categoryPresentation = TopicCategoryBadgePresentation.resolve(
            category: category,
            parent: parent,
            displayName: category.displayName(parent: parent),
            baseURL: api.baseURL
        )
        loadedCategoryMetadataId = categoryId
        notifyChanged()
    }

    func loadMorePosts(containerWidth: CGFloat) async {
        guard canLoadMore,
              TopicDetailPaginationPolicy.canStartMore(
                  isLoadingEarlier: isLoadingEarlier,
                  isLoadingMore: isLoadingMore,
                  isJumping: isJumping
              ),
              let topicId = topic?.id
        else { return }
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
            }
            guard await parseAndStore(posts: sortedPosts, generation: parseGeneration) else {
                isLoadingMore = false
                notifyChanged()
                return
            }

            loadedRangeEnd = newEnd
        } catch {
            // Silently fail; user can scroll again to retry
        }

        isLoadingMore = false
        notifyChanged()
    }

    @discardableResult
    func loadEarlierPosts(containerWidth: CGFloat) async -> Bool {
        guard canLoadEarlier,
              TopicDetailPaginationPolicy.canStartEarlier(
                  isLoadingEarlier: isLoadingEarlier,
                  isLoadingMore: isLoadingMore,
                  isJumping: isJumping
              ),
              let topicId = topic?.id
        else { return false }
        isLoadingEarlier = true
        notifyChanged()

        let newStart = max(0, loadedRangeStart - 20)
        let batch = Array(allPostIds[newStart..<loadedRangeStart])

        guard !batch.isEmpty else {
            isLoadingEarlier = false
            notifyChanged()
            return true
        }

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)
            let newPosts = response.postStream.posts.filter { !loadedPostIds.contains($0.id) }

            guard !newPosts.isEmpty else {
                for id in batch { loadedPostIds.insert(id) }
                loadedRangeStart = newStart
                isLoadingEarlier = false
                notifyChanged()
                return true
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
            }
            guard await parseAndStore(posts: sortedPosts, generation: parseGeneration) else {
                isLoadingEarlier = false
                notifyChanged()
                return true
            }

            loadedRangeStart = newStart
        } catch {
            // Silently fail; user can scroll again to retry
        }

        isLoadingEarlier = false
        notifyChanged()
        return true
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
        parseGeneration += 1
        let generation = parseGeneration

        do {
            let response = try await api.fetchTopicPosts(topicId: topicId, postIds: batch)

            // Sort by stream order
            let idOrder = Dictionary(uniqueKeysWithValues: allPostIds.enumerated().map { ($1, $0) })
            let sortedPosts = response.postStream.posts.sorted { (idOrder[$0.id] ?? 0) < (idOrder[$1.id] ?? 0) }

            topic?.postStream.posts = sortedPosts

            for post in sortedPosts {
                loadedPostIds.insert(post.id)
            }
            guard await parseAndStore(posts: sortedPosts, generation: generation) else {
                isJumping = false
                notifyChanged()
                return
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
        reactionUsersCount: Int?,
        currentUserReaction: DiscourseTopicDetail.Reaction?
    ) {
        guard let index = topic?.postStream.posts.firstIndex(where: { $0.id == postId }) else { return }
        topic?.postStream.posts[index].reactions = reactions
        topic?.postStream.posts[index].reactionUsersCount = reactionUsersCount ?? reactions.reduce(0) { $0 + $1.count }
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

    func updateSharedIssue(count: Int, userCreated: Bool) {
        topic?.sharedIssueCount = count
        topic?.userCreatedSharedIssue = userCreated
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

    func submitPollVote(postId: Int, pollName: String, optionIds: [String]) async throws {
        let voteResponse = try await api.votePoll(postId: postId, pollName: pollName, optionIds: optionIds)
        let submittedOptionIds = Set(optionIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        do {
            try await reloadPost(postId: postId)
        } catch {
            if applyPollVoteResponse(voteResponse, postId: postId, submittedOptionIds: submittedOptionIds) {
                notifyChanged()
                return
            }
            throw error
        }
        if applyPollVoteResponse(voteResponse, postId: postId, submittedOptionIds: submittedOptionIds) {
            notifyChanged()
        }
    }

    func reloadPost(postId: Int) async throws {
        guard let topicId = topic?.id else { return }
        let response = try await api.fetchTopicPosts(topicId: topicId, postIds: [postId])
        guard let updatedPost = response.postStream.posts.first(where: { $0.id == postId }) else { return }

        if let index = topic?.postStream.posts.firstIndex(where: { $0.id == postId }) {
            topic?.postStream.posts[index] = updatedPost
        } else {
            topic?.postStream.posts.append(updatedPost)
        }
        loadedPostIds.insert(updatedPost.id)
        guard await parseAndStore(posts: [updatedPost], generation: parseGeneration) else { return }
        notifyChanged()
    }

    @discardableResult
    private func applyPollVoteResponse(
        _ voteResponse: DiscoursePollVoteResponse,
        postId: Int,
        submittedOptionIds: Set<String>
    ) -> Bool {
        guard let blocks = parsedBlocks[postId] else { return false }
        let result = TopicDetailPollResultMerger.merged(
            blocks,
            voteResponse: voteResponse,
            submittedOptionIds: submittedOptionIds
        )
        guard result.didChange else { return false }
        parsedBlocks[postId] = result.blocks
        return true
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

    private func parseAndStore(posts: [DiscourseTopicDetail.Post], generation: Int) async -> Bool {
        let snapshots = posts.map { TopicDetailPostHTML(postId: $0.id, cooked: $0.cooked) }
        let baseURL = api.baseURL
        let parsedPosts = await TopicDetailHTMLParsing.parse(posts: snapshots, baseURL: baseURL)
        let postsById = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })

        guard generation == parseGeneration else { return false }
        for parsedPost in parsedPosts {
            let annotatedBlocks: [AnnotatedBlock]
            if let post = postsById[parsedPost.postId] {
                annotatedBlocks = TopicDetailPollResultMerger.mergeInitialPollState(
                    blocks: parsedPost.annotatedBlocks,
                    post: post
                )
            } else {
                annotatedBlocks = parsedPost.annotatedBlocks
            }
            parsedBlocks[parsedPost.postId] = annotatedBlocks
            if parsedPost.hasUnsupportedBlocks {
                unsupportedPostIds.insert(parsedPost.postId)
            } else {
                unsupportedPostIds.remove(parsedPost.postId)
            }
        }
        return true
    }
}
