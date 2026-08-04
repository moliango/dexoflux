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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.configureMoreMenu(isBookmarked: self.isBookmarked)
        }
    }

    @objc func sourceButtonTapped() {
        UIPasteboard.general.string = cookedHTML
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        sourceButton.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
        sourceButton.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.sourceButton.setImage(UIImage(systemName: "doc.on.clipboard", withConfiguration: config), for: .normal)
            self?.sourceButton.tintColor = .tertiaryLabel
        }
    }

    @objc func reactButtonTapped() {
        guard let post = currentPost else { return }
        let reactionId = post.currentUserReaction?.id ?? "heart"
        delegate?.postCell(didTapReaction: reactionId, forPost: post)
    }

    @objc func reactionPillLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let post = currentPost,
              !validReactions.isEmpty
        else { return }
        presentReactionPicker(for: post)
    }

    func presentReactionPicker(for post: DiscourseTopicDetail.Post) {
        let pickerVC = UIViewController()
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        pickerVC.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pickerVC.view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: pickerVC.view.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: pickerVC.view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: pickerVC.view.trailingAnchor, constant: -12),
        ])

        let emojiSize: CGFloat = 28
        for reactionId in validReactions {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: emojiSize),
                button.heightAnchor.constraint(equalToConstant: emojiSize),
            ])
            button.accessibilityLabel = reactionId

            if let urlString = EmojiStore.url(for: reactionId) ?? EmojiStore.lookup(for: reactionId),
               let url = URL(string: urlString)
            {
                let iv = UIImageView()
                iv.contentMode = .scaleAspectFit
                iv.translatesAutoresizingMaskIntoConstraints = false
                ForumImageLoader.setImage(on: iv, url: url)
                iv.isUserInteractionEnabled = false
                button.addSubview(iv)
                NSLayoutConstraint.activate([
                    iv.topAnchor.constraint(equalTo: button.topAnchor),
                    iv.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                    iv.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                    iv.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                ])
            } else {
                button.setTitle(":\(reactionId):", for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 12)
                button.setTitleColor(.label, for: .normal)
            }

            button.addAction(UIAction { [weak self] _ in
                guard let self, let post = self.currentPost else { return }
                pickerVC.dismiss(animated: true)
                self.delegate?.postCell(didTapReaction: reactionId, forPost: post)
            }, for: .touchUpInside)

            stack.addArrangedSubview(button)
        }

        let pickerSize = CGSize(
            width: CGFloat(validReactions.count) * (emojiSize + 8) + 16,
            height: emojiSize + 16
        )
        pickerVC.preferredContentSize = pickerSize
        pickerVC.modalPresentationStyle = .popover
        if let popover = pickerVC.popoverPresentationController {
            popover.sourceView = reactionPillControl
            popover.sourceRect = reactionPillControl.bounds
            popover.permittedArrowDirections = [.down, .up]
            popover.delegate = self
        }

        // Find presenting view controller
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController {
                vc.present(pickerVC, animated: true)
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
