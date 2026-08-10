import CookedHTML
import SafariServices
import UIKit

// MARK: - Topic Timeline Sheet

// MARK: - PostCellDelegate

extension TopicDetailViewController: PostCellDelegate {
    func postCell(didTapImageURL url: URL, imageURLs: [URL]) {
        presentTopicImageGallery(currentURL: url, imageURLs: imageURLs)
    }

    func postCell(didTapLinkURL url: URL) {
        handleLink(url)
    }

    func postCell(didTapShowRepliesForPostId postId: Int) {
        let repliesVC = RepliesViewController(api: api, postId: postId, topicId: topicId)
        if let sheet = repliesVC.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(repliesVC, animated: true)
    }

    func postCell(didTapToggleDetails detailsIndex: Int, postId: Int) {
        // Details toggle not supported in native rendering — no-op
    }

    func postCell(didToggleBookmarkForPost post: DiscourseTopicDetail.Post, isBookmarked: Bool) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    if isBookmarked {
                        let response = try await self.api.createBookmark(postId: post.id)
                        self.viewModel.updatePostBookmark(postId: post.id, bookmarked: true, bookmarkId: response.id)
                    } else if let bookmarkId = post.bookmarkId {
                        try await self.api.deleteBookmark(id: bookmarkId)
                        self.viewModel.updatePostBookmark(postId: post.id, bookmarked: false, bookmarkId: nil)
                    } else {
                        await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
                    }
                    self.reloadPostCell(postId: post.id)
                } catch {
                    self.reloadPostCell(postId: post.id)
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didTapReaction reactionId: String, forPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    if let response = try await self.api.toggleReaction(postId: post.id, reactionId: reactionId) {
                        self.viewModel.updatePostReaction(
                            postId: post.id,
                            reactions: response.reactions,
                            reactionUsersCount: response.reactionUsersCount,
                            currentUserReaction: response.currentUserReaction
                        )
                        self.reloadPostCell(postId: post.id)
                    } else {
                        await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
                    }
                } catch {
                    self.reloadPostCell(postId: post.id)
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didTapToggleSharedIssueForTopicId topicId: Int) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            guard !self.pendingSharedIssueTopicIds.contains(topicId) else { return }
            self.pendingSharedIssueTopicIds.insert(topicId)

            Task { @MainActor in
                defer { self.pendingSharedIssueTopicIds.remove(topicId) }
                do {
                    let response = try await self.api.toggleSharedIssue(topicId: topicId)
                    self.viewModel.updateSharedIssue(
                        count: response.count,
                        userCreated: response.userCreatedSharedIssue
                    )
                    if let firstPostId = self.viewModel.topic?.postStream.posts.first?.id {
                        self.reloadPostCell(postId: firstPostId)
                    }
                } catch {
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didSubmitPollVoteForPostId postId: Int, pollName: String, optionIds: [String]) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.viewModel.submitPollVote(postId: postId, pollName: pollName, optionIds: optionIds)
                    self.reloadPostCell(postId: postId)
                } catch {
                    self.reloadPostCell(postId: postId)
                    self.showPostActionError(error)
                }
            }
        }
    }

    func postCell(didTapBoostForPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.presentBoostInput(for: post)
        }
    }

    func postCell(didRequestDeleteBoost boost: DiscourseTopicDetail.Boost, forPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.deleteBoost(boost, for: post)
        }
    }

    func postCell(didTapAvatarForUsername username: String) {
        let previewVC = UserProfilePreviewViewController(api: api, username: username)
        previewVC.onViewProfile = { [weak self] selectedUsername in
            guard let self else { return }
            let vc = UserProfileViewController(api: self.api, username: selectedUsername)
            self.navigationController?.pushViewController(vc, animated: true)
        }
        present(previewVC, animated: true)
    }

    func postCell(didTapQuotedPostNumber postNumber: Int) {
        Task { await jumpToPostNumber(postNumber) }
    }

    func postCell(didTapReplyToPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.presentReplyComposer(for: post)
        }
    }

    func postCell(didTapShareImageForPost post: DiscourseTopicDetail.Post) {
        shareTopicImage(postId: post.id)
    }

    func postCell(didTapShowRevisionForPost post: DiscourseTopicDetail.Post) {
        let vc = PostRevisionViewController(api: api, postId: post.id)
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    func postCell(didTapEditPost post: DiscourseTopicDetail.Post) {
        performAuthenticated { [weak self] in
            self?.loadAndPresentPostEditor(postId: post.id)
        }
    }

    
    func deleteBoost(_ boost: DiscourseTopicDetail.Boost, for post: DiscourseTopicDetail.Post) {
        Task {
            do {
                try await api.deleteBoost(boostId: boost.id)
                viewModel.removePostBoost(postId: post.id, boostId: boost.id)
                reloadPostCell(postId: post.id)
            } catch {
                reloadPostCell(postId: post.id)
                showPostActionError(error)
            }
        }
    }

func presentBoostInput(for post: DiscourseTopicDetail.Post) {
        let input = BoostInputViewController(api: api)
        input.onSubmit = { [weak self] result in
            guard let self else { return }
            switch result {
            case let .boost(raw):
                Task {
                    do {
                        let boost = try await self.api.createBoost(postId: post.id, raw: raw)
                        self.viewModel.appendPostBoost(postId: post.id, boost: boost)
                        self.reloadPostCell(postId: post.id)
                    } catch {
                        self.reloadPostCell(postId: post.id)
                        self.showPostActionError(error)
                    }
                }
            case let .reply(raw):
                self.presentReplyComposer(for: post, initialText: raw)
            }
        }
        input.modalPresentationStyle = .pageSheet
        if let sheet = input.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(input, animated: true)
    }

    func presentReplyComposer(for post: DiscourseTopicDetail.Post? = nil, initialText: String? = nil) {
        let composer = ReplyComposerViewController(
            api: api,
            topicId: topicId,
            replyToPost: post,
            baseURL: baseURL,
            initialText: initialText,
            mentionSeedUsers: mentionSeedUsersFromLoadedPosts()
        )
        composer.onPostCreated = { [weak self] in
            guard let self else { return }
            Task {
                await self.viewModel.loadTopic(id: self.topicId, containerWidth: self.view.bounds.width)
            }
        }
        composer.modalPresentationStyle = .pageSheet
        if let sheet = composer.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(composer, animated: true)
    }

    /// Unique authors from currently loaded posts — instant @ list like FluxDo.
    func mentionSeedUsersFromLoadedPosts() -> [DiscourseMentionUser] {
        var seen = Set<String>()
        var users: [DiscourseMentionUser] = []
        for post in viewModel.posts {
            let key = post.username.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            users.append(
                DiscourseMentionUser(
                    username: post.username,
                    name: post.name,
                    avatarTemplate: post.avatarTemplate
                )
            )
            if users.count >= 12 { break }
        }
        return users
    }

    func loadAndPresentPostEditor(postId: Int) {
        Task {
            do {
                let editablePost = try await api.fetchPost(id: postId)
                guard editablePost.canEdit, let raw = editablePost.raw else {
                    throw DiscourseAPIError(
                        messages: [String(localized: "post.edit.unavailable", defaultValue: "这条评论当前无法编辑。")],
                        errorType: "post_not_editable"
                    )
                }
                let composer = ReplyComposerViewController(
                    api: api,
                    topicId: topicId,
                    replyToPost: nil,
                    baseURL: baseURL,
                    initialText: raw,
                    submissionMode: .edit(postId: postId),
                    mentionSeedUsers: self.mentionSeedUsersFromLoadedPosts()
                )
                composer.onPostUpdated = { [weak self] updatedPostId in
                    guard let self else { return }
                    Task {
                        do {
                            try await self.viewModel.reloadPost(postId: updatedPostId)
                            self.reloadPostCell(postId: updatedPostId)
                        } catch {
                            self.showPostActionError(error)
                        }
                    }
                }
                composer.modalPresentationStyle = .pageSheet
                if let sheet = composer.sheetPresentationController {
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = false
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                }
                present(composer, animated: true)
            } catch {
                showPostActionError(error)
            }
        }
    }
}
