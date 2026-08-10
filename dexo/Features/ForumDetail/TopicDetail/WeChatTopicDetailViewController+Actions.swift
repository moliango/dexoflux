import SafariServices
import UIKit

extension WeChatTopicDetailViewController {
    var pluginScope: PluginScope {
        PluginScope(
            baseURL: api.baseURL,
            username: AuthManager.shared.username(for: api.baseURL)
        )
    }

    /// Top-right: search + FluxDo-style more popup (quick icons + list).
    func configureTopicActions() {
        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(searchTopicTapped)
        )
        searchButton.accessibilityLabel = String(localized: "topic.search", defaultValue: "搜索话题")

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(presentTopicMoreMenu)
        )
        moreButton.accessibilityLabel = String(localized: "topic.more", defaultValue: "更多操作")
        navigationItem.rightBarButtonItems = [moreButton, searchButton]
    }

    @objc private func presentTopicMoreMenu() {
        let topic = viewModel.topic
        let username = AuthManager.shared.username(for: api.baseURL)
        let isReadLater = TopicReadLaterStore.shared.contains(
            topicId: topicId,
            baseURL: api.baseURL,
            username: username
        )
        let model = TopicMoreMenuViewController.Model(
            isBookmarked: topic?.bookmarked == true,
            isInReadLater: isReadLater,
            notificationLevel: topic?.notificationLevel,
            hasActiveFilter: viewModel.isFilteringByOP || viewModel.isFilteringTopLevel,
            canEdit: topic?.canEdit == true,
            showExport: DexoPluginRuntime.shared.registry.isPluginEnabled(
                BuiltInPluginID.topicExport,
                for: pluginScope
            )
        )
        TopicMoreMenuPresenter.present(
            from: self,
            barButtonItem: navigationItem.rightBarButtonItems?.first,
            model: model
        ) { [weak self] action in
            self?.handleTopicMoreMenuAction(action)
        }
    }

    private func handleTopicMoreMenuAction(_ action: TopicMoreMenuViewController.Action) {
        switch action {
        case .bookmark:
            bookmarkTopic()
        case .readLater:
            let title = viewModel.topic?.title
                ?? viewModel.topic?.fancyTitle
                ?? "#\(topicId)"
            TopicReadLaterStore.shared.toggle(
                topicId: topicId,
                baseURL: api.baseURL,
                username: AuthManager.shared.username(for: api.baseURL),
                title: title,
                lastReadPostNumber: lastReadPostNumber ?? viewModel.topic?.lastReadPostNumber
            )
            configureTopicActions()
        case .notification:
            presentNotificationLevelPicker()
        case .shareLink:
            shareTopicLink()
        case .filter:
            presentTopicFilterSheet()
        case .editTopic:
            editTopic()
        case .shareImage:
            shareTopicImage()
        case .export:
            let alert = UIAlertController(
                title: String(localized: "topic.export", defaultValue: "导出文章"),
                message: nil,
                preferredStyle: .actionSheet
            )
            for format in TopicExportFormat.allCases {
                for range in TopicExportRange.allCases {
                    alert.addAction(UIAlertAction(
                        title: "\(format.title) · \(range.title)",
                        style: .default
                    ) { [weak self] _ in
                        self?.exportTopic(format: format, range: range)
                    })
                }
            }
            alert.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
            if let pop = alert.popoverPresentationController {
                pop.barButtonItem = navigationItem.rightBarButtonItems?.first
            }
            present(alert, animated: true)
        case .openBrowser:
            guard let url = URL(string: "\(baseURL)/t/\(topicId)") else { return }
            let browser = InAppBrowserViewController(
                api: api,
                username: AuthManager.shared.username(for: api.baseURL),
                initialURL: url
            )
            navigationController?.pushViewController(browser, animated: true)
        case .readingSettings:
            navigationController?.pushViewController(ReadingSettingsViewController(), animated: true)
        }
    }

    private func presentNotificationLevelPicker() {
        let sheet = UIAlertController(
            title: String(localized: "topic.notifications", defaultValue: "通知级别"),
            message: nil,
            preferredStyle: .actionSheet
        )
        let current = viewModel.topic?.notificationLevel
        for level in DiscourseTopicDetail.NotificationLevel.allCases.reversed() {
            let mark = current == level ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: mark + title(for: level), style: .default) { [weak self] _ in
                self?.setNotificationLevel(level)
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(sheet, animated: true)
    }

    private func presentTopicFilterSheet() {
        let sheet = UIAlertController(
            title: String(localized: "topic.filter", defaultValue: "筛选"),
            message: nil,
            preferredStyle: .actionSheet
        )
        func add(_ title: String, on: Bool, handler: @escaping () -> Void) {
            sheet.addAction(UIAlertAction(title: on ? "✓ \(title)" : title, style: .default) { _ in handler() })
        }
        add(String(localized: "topic.filter_op", defaultValue: "只看题主"), on: viewModel.isFilteringByOP) { [weak self] in
            guard let self else { return }
            self.viewModel.setFilteringByOP(!self.viewModel.isFilteringByOP)
            self.applySnapshot()
            self.configureTopicActions()
        }
        add(String(localized: "topic.filter_top_level", defaultValue: "只看顶层"), on: viewModel.isFilteringTopLevel) { [weak self] in
            guard let self else { return }
            self.viewModel.setFilteringTopLevel(!self.viewModel.isFilteringTopLevel)
            self.applySnapshot()
            self.configureTopicActions()
        }
        add(String(localized: "topic.filter_nested", defaultValue: "树形视图"), on: viewModel.isNestedViewEnabled) { [weak self] in
            guard let self else { return }
            self.viewModel.setNestedViewEnabled(!self.viewModel.isNestedViewEnabled)
            self.applySnapshot()
            self.configureTopicActions()
        }
        if viewModel.isFilteringByOP || viewModel.isFilteringTopLevel {
            sheet.addAction(UIAlertAction(
                title: String(localized: "topic.filter_clear", defaultValue: "取消筛选"),
                style: .destructive
            ) { [weak self] _ in
                self?.viewModel.clearTopicFilters()
                self?.applySnapshot()
                self?.configureTopicActions()
            })
        }
        sheet.addAction(UIAlertAction(title: String(localized: "common.cancel", defaultValue: "取消"), style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        present(sheet, animated: true)
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
