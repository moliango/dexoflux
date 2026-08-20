import UIKit

extension PostNativeCell {
    // MARK: - Actions
    // MARK: - Actions

    @objc func repliesButtonTapped() {
        delegate?.postCell(didTapShowRepliesForPostId: postId)
    }

    @objc func sharedIssueButtonTapped() {
        guard let topicId = currentSharedIssueTopicId else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.postCell(didTapToggleSharedIssueForTopicId: topicId)
    }

    @objc func replyButtonTapped() {
        guard let post = currentPost else { return }
        delegate?.postCell(didTapReplyToPost: post)
    }

    @objc func avatarTapped() {
        guard let username = currentPost?.username else { return }
        delegate?.postCell(didTapAvatarForUsername: username)
    }

    @objc func copyLinkTapped() {
        guard let link = postLink else { return }
        UIPasteboard.general.string = link
        configureActionButton(
            moreButton,
            symbolName: "checkmark",
            tintColor: .systemGreen,
            backgroundColor: UIColor.systemGreen.withAlphaComponent(0.14),
            accessibilityLabel: "已复制"
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(1.0 * 1_000_000_000))
            self.configureMoreMenu(isBookmarked: self.isBookmarked)
        }
    }

    @objc func sourceButtonTapped() {
        UIPasteboard.general.string = cookedHTML
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        sourceButton.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
        sourceButton.tintColor = .systemGreen
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(1.0 * 1_000_000_000))
            self.sourceButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
            self.sourceButton.tintColor = .tertiaryLabel
        }
    }

    @objc func reactButtonTapped() {
        guard let post = currentPost, !post.yours else { return }
        let reactionId = post.currentUserReaction?.id ?? "heart"
        delegate?.postCell(didTapReaction: reactionId, forPost: post)
    }

    @objc func reactionPillLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let post = currentPost,
              !post.yours,
              !validReactions.isEmpty
        else { return }
        presentReactionPicker(for: post)
    }

    func presentReactionPicker(for post: DiscourseTopicDetail.Post) {
        // Own posts cannot be reacted to.
        guard !post.yours else { return }
        guard !validReactions.isEmpty else { return }

        let pickerVC = UIViewController()
        pickerVC.view.backgroundColor = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor.systemBackground
        }

        // Compact horizontal strip: fixed emoji size, scroll if many reactions.
        let emojiSize: CGFloat = 28
        let hitSize: CGFloat = 36
        let hPad: CGFloat = 10
        let vPad: CGFloat = 8
        let spacing: CGFloat = 6

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = validReactions.count > 8
        scroll.clipsToBounds = true
        pickerVC.view.addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = spacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: pickerVC.view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: pickerVC.view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: pickerVC.view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pickerVC.view.trailingAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: vPad),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -vPad),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: hPad),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -hPad),
            stack.heightAnchor.constraint(equalToConstant: hitSize),
        ])

        for reactionId in validReactions {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityLabel = reactionId
            button.layer.cornerRadius = hitSize / 2
            button.clipsToBounds = true
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: hitSize),
                button.heightAnchor.constraint(equalToConstant: hitSize),
            ])

            let iv = UIImageView()
            iv.contentMode = .scaleAspectFit
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.isUserInteractionEnabled = false
            button.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iv.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: emojiSize),
                iv.heightAnchor.constraint(equalToConstant: emojiSize),
            ])

            if let urlString = EmojiStore.url(for: reactionId) ?? EmojiStore.lookup(for: reactionId),
               let url = URL(string: urlString)
            {
                // Request a crisp pixel size so custom Discourse emojis don't load tiny then upscale blurry.
                ForumImageLoader.setImage(on: iv, url: url)
            } else if reactionId == "heart" {
                let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
                iv.image = UIImage(systemName: "heart.fill", withConfiguration: config)
                iv.tintColor = .systemPink
            } else {
                // Compact monogram — never a microscopic glyph on the trailing edge.
                let label = UILabel()
                label.text = String(reactionId.prefix(1)).uppercased()
                label.font = .systemFont(ofSize: 14, weight: .bold)
                label.textAlignment = .center
                label.textColor = .secondaryLabel
                label.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                ])
            }

            let rid = reactionId
            button.addAction(UIAction { [weak self] _ in
                guard let self, let current = self.currentPost else { return }
                pickerVC.dismiss(animated: true) {
                    self.delegate?.postCell(didTapReaction: rid, forPost: current)
                }
            }, for: .touchUpInside)

            stack.addArrangedSubview(button)
        }

        let count = max(validReactions.count, 1)
        let contentWidth = CGFloat(count) * hitSize + CGFloat(max(count - 1, 0)) * spacing + hPad * 2
        // Compact bubble: show as many as fit; scroll for the rest. Never full-screen wide.
        let screenCap = min(UIScreen.main.bounds.width - 48, 320)
        let width = min(contentWidth, screenCap)
        let height = hitSize + vPad * 2
        pickerVC.preferredContentSize = CGSize(width: width, height: height)
        pickerVC.modalPresentationStyle = .popover

        if let popover = pickerVC.popoverPresentationController {
            popover.sourceView = reactionPillControl
            popover.sourceRect = reactionPillControl.bounds.insetBy(dx: 4, dy: 4)
            popover.permittedArrowDirections = [.up, .down]
            popover.delegate = self
            // Soft chrome so it reads as a reaction chip strip, not a sheet.
            if #available(iOS 15.0, *) {
                popover.backgroundColor = pickerVC.view.backgroundColor
            }
        }

        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                // Dismiss any existing picker first to avoid stacked popovers.
                if vc.presentedViewController != nil {
                    vc.dismiss(animated: false) {
                        vc.present(pickerVC, animated: true)
                    }
                } else {
                    vc.present(pickerVC, animated: true)
                }
                break
            }
            responder = next
        }
    }

    @objc func boostButtonTapped() {
        guard let post = currentPost else { return }
        delegate?.postCell(didTapBoostForPost: post)
    }

    @objc func bookmarkButtonTapped() {
        guard let post = currentPost else { return }
        let targetState = !isBookmarked
        isBookmarked = targetState
        configureBookmarkButton(isBookmarked: targetState)
        configureMoreMenu(isBookmarked: targetState)
        delegate?.postCell(didToggleBookmarkForPost: post, isBookmarked: targetState)
    }

}
