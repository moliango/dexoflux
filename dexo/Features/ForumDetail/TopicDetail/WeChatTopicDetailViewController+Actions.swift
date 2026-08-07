import SafariServices
import UIKit

extension WeChatTopicDetailViewController {
    var pluginScope: PluginScope {
        PluginScope(
            baseURL: api.baseURL,
            username: AuthManager.shared.username(for: api.baseURL)
        )
    }

    /// Mirrors classic Topic Detail top-right: search + ellipsis menu.
    func configureTopicActions() {
        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(searchTopicTapped)
        )
        searchButton.accessibilityLabel = String(localized: "topic.search", defaultValue: "搜索话题")

        let topic = viewModel.topic
        let bookmarkTitle = topic?.bookmarked == true
            ? String(localized: "topic.bookmark.remove", defaultValue: "取消书签")
            : String(localized: "topic.bookmark.add", defaultValue: "添加书签")
        let bookmark = UIAction(
            title: bookmarkTitle,
            image: UIImage(systemName: topic?.bookmarked == true ? "bookmark.slash" : "bookmark")
        ) { [weak self] _ in
            self?.bookmarkTopic()
        }

        let share = UIAction(
            title: String(localized: "topic.share", defaultValue: "分享链接"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.shareTopicLink()
        }

        let username = AuthManager.shared.username(for: api.baseURL)
        let isReadLater = TopicReadLaterStore.shared.contains(
            topicId: topicId,
            baseURL: api.baseURL,
            username: username
        )
        let readLater = UIAction(
            title: isReadLater
                ? String(localized: "topic.read_later.remove", defaultValue: "移出稍后阅读")
                : String(localized: "topic.read_later.add", defaultValue: "稍后阅读"),
            image: UIImage(systemName: "square.stack.3d.up"),
            state: isReadLater ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            let title = self.viewModel.topic?.title
                ?? self.viewModel.topic?.fancyTitle
                ?? "#\(self.topicId)"
            TopicReadLaterStore.shared.toggle(
                topicId: self.topicId,
                baseURL: self.api.baseURL,
                username: AuthManager.shared.username(for: self.api.baseURL),
                title: title,
                lastReadPostNumber: self.lastReadPostNumber ?? self.viewModel.topic?.lastReadPostNumber
            )
            self.configureTopicActions()
        }

        let shareImage = UIAction(
            title: String(localized: "topic.share_image", defaultValue: "生成分享图片"),
            image: UIImage(systemName: "photo")
        ) { [weak self] _ in
            self?.shareTopicImage()
        }

        let opFilter = UIAction(
            title: viewModel.isFilteringByOP
                ? String(localized: "topic.filter_all", defaultValue: "显示全部回复")
                : String(localized: "topic.filter_op", defaultValue: "只看楼主"),
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            state: viewModel.isFilteringByOP ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.viewModel.setFilteringByOP(!self.viewModel.isFilteringByOP)
            self.applySnapshot()
            self.configureTopicActions()
        }

        let notificationMenu = UIMenu(
            title: String(localized: "topic.notifications", defaultValue: "通知级别"),
            image: UIImage(systemName: "bell"),
            children: DiscourseTopicDetail.NotificationLevel.allCases.reversed().map { level in
                UIAction(
                    title: self.title(for: level),
                    state: topic?.notificationLevel == level ? .on : .off
                ) { [weak self] _ in
                    self?.setNotificationLevel(level)
                }
            }
        )

        let openBrowser = UIAction(
            title: String(localized: "topic.open_browser", defaultValue: "在浏览器打开"),
            image: UIImage(systemName: "globe")
        ) { [weak self] _ in
            guard let self, let url = URL(string: "\(self.baseURL)/t/\(self.topicId)") else { return }
            let browser = InAppBrowserViewController(
                api: self.api,
                username: AuthManager.shared.username(for: self.api.baseURL),
                initialURL: url
            )
            self.navigationController?.pushViewController(browser, animated: true)
        }

        let readingSettings = UIAction(
            title: String(localized: "topic.reading_settings", defaultValue: "阅读设置"),
            image: UIImage(systemName: "book")
        ) { [weak self] _ in
            self?.navigationController?.pushViewController(ReadingSettingsViewController(), animated: true)
        }

        var actions: [UIMenuElement] = [bookmark, readLater, notificationMenu, share, shareImage, opFilter]
        if topic?.canEdit == true {
            actions.append(
                UIAction(
                    title: String(localized: "topic.edit", defaultValue: "编辑话题"),
                    image: UIImage(systemName: "pencil")
                ) { [weak self] _ in
                    self?.editTopic()
                }
            )
        }
        if DexoPluginRuntime.shared.registry.isPluginEnabled(BuiltInPluginID.topicExport, for: pluginScope) {
            actions.append(makeExportMenu())
        }
        actions.append(contentsOf: [openBrowser, readingSettings])

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: actions)
        )
        moreButton.accessibilityLabel = String(localized: "topic.more", defaultValue: "更多操作")
        navigationItem.rightBarButtonItems = [moreButton, searchButton]
    }

    private func title(for level: DiscourseTopicDetail.NotificationLevel) -> String {
        switch level {
        case .watching: return String(localized: "topic.notifications.watching", defaultValue: "关注")
        case .tracking: return String(localized: "topic.notifications.tracking", defaultValue: "跟踪")
        case .regular: return String(localized: "topic.notifications.regular", defaultValue: "常规")
        case .muted: return String(localized: "topic.notifications.muted", defaultValue: "静音")
        }
    }

    private func makeExportMenu() -> UIMenu {
        let formatMenus = TopicExportFormat.allCases.map { format in
            UIMenu(
                title: format.title,
                image: UIImage(systemName: format == .markdown ? "doc.plaintext" : "chevron.left.forwardslash.chevron.right"),
                children: TopicExportRange.allCases.map { range in
                    UIAction(title: range.title) { [weak self] _ in
                        self?.exportTopic(format: format, range: range)
                    }
                }
            )
        }
        let notionMenus = NotionSyncScope.allCases.map { scope in
            UIAction(title: scope.title) { [weak self] _ in
                self?.syncTopicToNotion(scope: scope)
            }
        }
        let notionMenu = UIMenu(
            title: String(localized: "notion.sync", defaultValue: "同步到 Notion"),
            image: UIImage(systemName: "tray.and.arrow.up"),
            children: notionMenus
        )
        return UIMenu(
            title: String(localized: "topic.export", defaultValue: "导出话题"),
            image: UIImage(systemName: "square.and.arrow.up"),
            children: formatMenus + [notionMenu]
        )
    }

    // MARK: - Actions

    @objc private func searchTopicTapped() {
        let alert = UIAlertController(
            title: String(localized: "topic.search", defaultValue: "搜索话题"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = String(localized: "topic.search.placeholder", defaultValue: "输入关键词")
            field.returnKeyType = .search
        }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "topic.search", defaultValue: "搜索话题"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let query = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !query.isEmpty
            else { return }
            self.performTopicSearch(query)
        })
        present(alert, animated: true)
    }

    private func performTopicSearch(_ query: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await api.searchTopic(topicId: topicId, term: query)
                let posts = (result.posts ?? []).filter { $0.topicId == topicId }
                presentSearchResults(posts, query: query)
            } catch {
                showPostActionError(error)
            }
        }
    }

    private func presentSearchResults(_ posts: [DiscourseSearchResult.SearchPost], query: String) {
        guard !posts.isEmpty else {
            let alert = UIAlertController(
                title: String(localized: "topic.search", defaultValue: "搜索话题"),
                message: String(localized: "topic.search.empty", defaultValue: "没有找到匹配内容"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default))
            present(alert, animated: true)
            return
        }
        let sheet = UIAlertController(title: query, message: nil, preferredStyle: .actionSheet)
        for post in posts.prefix(12) {
            let excerptSource = post.blurb ?? post.username
            let excerpt = CookedContentPipeline.plainTextPreview(fromCooked: excerptSource)
            let title = "#\(post.postNumber)  \(String((excerpt.isEmpty ? post.username : excerpt).prefix(70)))"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                if post.id > 0 {
                    self.scrollToPostId(post.id)
                } else {
                    Task { await self.jumpToFloor(post.postNumber) }
                }
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
        present(sheet, animated: true)
    }

    private func shareTopicLink() {
        let link = "\(baseURL)/t/\(topicId)"
        let activity = UIActivityViewController(activityItems: [link], applicationActivities: nil)
        activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(activity, animated: true)
    }

    private func bookmarkTopic() {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    if self.viewModel.topic?.bookmarked == true,
                       let bookmarkId = self.viewModel.topic?.bookmarkId {
                        try await self.api.deleteBookmark(id: bookmarkId)
                    } else {
                        _ = try await self.api.createBookmark(topicId: self.topicId)
                    }
                    await self.viewModel.loadTopic(
                        id: self.topicId,
                        containerWidth: max(self.view.bounds.width, UIScreen.main.bounds.width)
                    )
                    self.configureTopicActions()
                } catch {
                    self.showPostActionError(error)
                }
            }
        }
    }

    private func setNotificationLevel(_ level: DiscourseTopicDetail.NotificationLevel) {
        performAuthenticated { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.api.updateTopicNotificationLevel(topicId: self.topicId, level: level)
                    self.viewModel.topic?.notificationLevel = level
                    self.configureTopicActions()
                } catch {
                    self.showPostActionError(error)
                }
            }
        }
    }

    private func editTopic() {
        guard let topic = viewModel.topic, topic.canEdit else { return }
        let alert = UIAlertController(
            title: String(localized: "topic.edit", defaultValue: "编辑话题"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { $0.text = topic.title }
        alert.addAction(UIAlertAction(title: String(localized: "common.cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "common.done"), style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let title = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty
            else { return }
            Task {
                do {
                    try await self.api.updateTopic(topicId: self.topicId, title: title)
                    await self.viewModel.loadTopic(
                        id: self.topicId,
                        containerWidth: max(self.view.bounds.width, UIScreen.main.bounds.width)
                    )
                    self.configureTopicActions()
                } catch {
                    self.showPostActionError(error)
                }
            }
        })
        present(alert, animated: true)
    }

    private func shareTopicImage() {
        guard let topic = viewModel.topic else { return }
        let post = viewModel.posts.first(where: { $0.postNumber == 1 && $0.actionCode == nil })
            ?? viewModel.posts.first(where: { $0.actionCode == nil })
        guard let post else {
            showPostActionError(NSError(
                domain: "ShareImage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "share.image.no_content", defaultValue: "暂无可分享内容")]
            ))
            return
        }

        let displayTitle = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
        let authorName = (post.name?.isEmpty == false ? post.name! : post.username)
        let createdAtText: String? = post.createdAt.isEmpty ? nil : TopicCell.formatDate(post.createdAt)
        let avatarURL = AvatarImageLoader.url(from: post.avatarTemplate, baseURL: baseURL, size: 120)
        let hostName = URL(string: baseURL)?.host?.lowercased() ?? ""
        let brandName = hostName.contains("linux.do") ? "LINUX DO" : "DexoFlux"
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let shareURL = "\(trimmedBase)/t/\(topicId)/\(post.postNumber)"
        let cookedTrimmed = post.cooked.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareHTML: String = {
            if !cookedTrimmed.isEmpty {
                return PostImageLinkPreprocessor.rewrite(cookedTrimmed)
            }
            if let raw = post.raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return ShareImageBodyComposer.normalizeCookedInput(raw)
            }
            return ""
        }()
        let contentBlocks = (viewModel.parsedBlocks[post.id] ?? []).map(\.block)
        let preview = ShareImagePreviewViewController(
            model: .init(
                topicId: topicId,
                baseURL: baseURL,
                title: displayTitle,
                brandName: brandName,
                authorName: authorName,
                username: post.username,
                createdAtText: createdAtText,
                avatarURL: avatarURL,
                cookedHTML: shareHTML,
                contentBlocks: contentBlocks,
                shareURL: shareURL,
                postNumber: post.postNumber
            )
        )
        present(preview, animated: true)
    }

    private func exportTopic(format: TopicExportFormat, range: TopicExportRange) {
        guard let topic = viewModel.topic else {
            showPostActionError(TopicExportError.noPosts)
            return
        }
        let title = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
        let posts = viewModel.posts
        let username = AuthManager.shared.username(for: api.baseURL)
        let service = TopicExportService(baseURL: baseURL, username: username)
        let history = ExportHistoryStore(baseURL: baseURL, username: username)
        let selectedPostCount = range == .firstPost
            ? min(posts.count, 1)
            : posts.filter { $0.actionCode == nil }.count
        do {
            let fileURL = try service.export(
                topicId: topicId,
                title: title,
                posts: posts,
                format: format,
                range: range
            )
            let record = TopicExportRecord(
                topicId: topicId,
                title: title,
                format: format,
                filePath: fileURL.path,
                postCount: selectedPostCount,
                errorMessage: nil
            )
            try history.add(record)
            let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
            present(activity, animated: true)
        } catch {
            let failedRecord = TopicExportRecord(
                topicId: topicId,
                title: title,
                format: format,
                filePath: nil,
                postCount: selectedPostCount,
                errorMessage: error.localizedDescription
            )
            try? history.add(failedRecord)
            showPostActionError(error)
        }
    }

    private func syncTopicToNotion(scope: NotionSyncScope) {
        guard let topic = viewModel.topic else { return }
        let username = AuthManager.shared.username(for: api.baseURL)
        let scopeKey = NotionConfigStore.shared.scopeKey(baseURL: baseURL, username: username)
        guard let token = NotionConfigStore.shared.token(scopeKey: scopeKey), !token.isEmpty,
              NotionConfigStore.shared.isComplete(scopeKey: scopeKey)
        else {
            let alert = UIAlertController(
                title: String(localized: "notion.not_configured", defaultValue: "请先配置 Notion"),
                message: String(
                    localized: "notion.not_configured.message",
                    defaultValue: "在「我的」里打开 Notion 同步并填写 Token 与 Database ID"
                ),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
            present(alert, animated: true)
            return
        }
        // Reuse classic coordinator path via a temporary host is heavy; call service directly if available.
        // Fall back: open Notion settings when sync helper is host-bound.
        let config = NotionConfigStore.shared.loadConfig(scopeKey: scopeKey)
        let service = NotionSyncService(config: config, token: token, baseURL: baseURL)
        let title = TitleEmojiRenderer.plainTitle(fancyTitle: topic.fancyTitle, title: topic.title)
        let posts = viewModel.posts
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await service.syncTopic(
                    topicId: self.topicId,
                    title: title,
                    posts: posts,
                    scope: scope
                )
                let alert = UIAlertController(
                    title: String(localized: "notion.sync.success", defaultValue: "已同步到 Notion"),
                    message: nil,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
                self.present(alert, animated: true)
            } catch {
                self.showPostActionError(error)
            }
        }
    }
}
