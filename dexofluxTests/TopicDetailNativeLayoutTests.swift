import XCTest
@testable import dexoflux

@MainActor
final class TopicDetailNativeLayoutTests: XCTestCase {
    func testCodeBlockDarkPaletteUsesBlackBackgroundAndReadableForeground() {
        let palette = CodeBlockThemePalette.palette(for: .dark)
        let background = palette.background.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )
        let foreground = palette.foreground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )

        XCTAssertEqual(background, .black)
        XCTAssertGreaterThan(foreground.relativeLuminanceForTesting, 0.7)
    }

    func testTopicDetailPushDoesNotShiftRootViewHorizontally() {
        XCTAssertEqual(TopicDetailTransitionGeometry.pushInitialTransform.tx, 0, accuracy: 0.001)
    }

    func testTimelinePaginationDoesNotStartOppositeDirectionConcurrently() {
        XCTAssertFalse(TopicDetailPaginationPolicy.canStartEarlier(isLoadingEarlier: false, isLoadingMore: true, isJumping: false))
        XCTAssertFalse(TopicDetailPaginationPolicy.canStartMore(isLoadingEarlier: true, isLoadingMore: false, isJumping: false))
        XCTAssertFalse(TopicDetailPaginationPolicy.canStartEarlier(isLoadingEarlier: false, isLoadingMore: false, isJumping: true))
        XCTAssertTrue(TopicDetailPaginationPolicy.canStartEarlier(isLoadingEarlier: false, isLoadingMore: false, isJumping: false))
    }

    func testEarlierLoadAnchorIsConsumedOnlyAfterLoadingFinishes() {
        XCTAssertFalse(TopicDetailPaginationPolicy.shouldRestoreEarlierAnchor(
            hasAnchor: true,
            isLoadingEarlier: true,
            snapshotChanged: false
        ))
        XCTAssertTrue(TopicDetailPaginationPolicy.shouldRestoreEarlierAnchor(
            hasAnchor: true,
            isLoadingEarlier: false,
            snapshotChanged: true
        ))
    }

    func testHeadingUsesTagBadgeOnlyForCurrentTopicTags() {
        let topicTags: Set<String> = ["纯水", "VPS"]

        XCTAssertTrue(
            HeadingPresentationPolicy.shouldRenderTagBadge(
                level: 1,
                text: "纯水",
                topicTagNames: topicTags
            )
        )
        XCTAssertTrue(
            HeadingPresentationPolicy.shouldRenderTagBadge(
                level: 1,
                text: " vps ",
                topicTagNames: topicTags
            )
        )
        XCTAssertFalse(
            HeadingPresentationPolicy.shouldRenderTagBadge(
                level: 1,
                text: "UU远程",
                topicTagNames: topicTags
            )
        )
        XCTAssertFalse(
            HeadingPresentationPolicy.shouldRenderTagBadge(
                level: 1,
                text: "ToDesk",
                topicTagNames: topicTags
            )
        )
        XCTAssertFalse(
            HeadingPresentationPolicy.shouldRenderTagBadge(
                level: 2,
                text: "纯水",
                topicTagNames: topicTags
            )
        )
    }

    func testRegularHeadingDoesNotUseQuoteStyleAccentRail() {
        XCTAssertFalse(HeadingPresentationPolicy.usesAccentRail)
    }

    func testPostActionAreaKeepsStableWidthAfterPaginationReuse() throws {
        let cell = PostNativeCell(style: .default, reuseIdentifier: PostNativeCell.reuseIdentifier)
        cell.frame = CGRect(x: 0, y: 0, width: 402, height: 320)

        configure(
            cell,
            post: try decodePost(includesActionMetadata: true)
        )
        cell.layoutIfNeeded()
        let initialActions = try XCTUnwrap(actionStack(in: cell))
        let initialSupplementary = try XCTUnwrap(
            view(in: cell, accessibilityIdentifier: "post.supplementary.footer")
        )
        let initialWidth = initialActions.bounds.width
        XCTAssertEqual(initialWidth, 194, accuracy: 0.5)
        XCTAssertFalse(initialSupplementary.isHidden)
        XCTAssertEqual(initialSupplementary.bounds.height, PostNativeCell.bottomBarHeight, accuracy: 0.5)

        cell.prepareForReuse()
        configure(cell, post: try decodePost(includesActionMetadata: false))
        cell.layoutIfNeeded()
        let reusedActions = try XCTUnwrap(actionStack(in: cell))
        let reusedSupplementary = try XCTUnwrap(
            view(in: cell, accessibilityIdentifier: "post.supplementary.footer")
        )
        let reusedWidth = reusedActions.bounds.width

        XCTAssertEqual(initialWidth, reusedWidth, accuracy: 0.5)
        XCTAssertTrue(reusedSupplementary.isHidden)
        XCTAssertEqual(reusedSupplementary.bounds.height, 0, accuracy: 0.5)

        let reusedButtons = descendants(in: reusedActions).compactMap { $0 as? PostActionButton }
        XCTAssertEqual(reusedButtons.count, 5)
        for button in reusedButtons {
            XCTAssertEqual(button.fixedIconView.bounds.size, PostActionButton.iconSize)
            XCTAssertEqual(button.bounds.height, PostNativeCell.bottomBarHeight, accuracy: 0.5)
        }
    }

    func testPostFooterUsesTwoRowsWhenSupplementaryActionsNeedSpace() throws {
        let cell = PostNativeCell(style: .default, reuseIdentifier: PostNativeCell.reuseIdentifier)
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 360)
        configure(
            cell,
            post: try decodePost(includesActionMetadata: true, replyCount: 2),
            sharedIssue: .init(topicId: 99, canCreate: true, count: 12, userCreated: false)
        )
        cell.layoutIfNeeded()

        let supplementary = try XCTUnwrap(view(in: cell, accessibilityIdentifier: "post.supplementary.footer"))
        let actions = try XCTUnwrap(view(in: cell, accessibilityIdentifier: "post.action.footer"))

        XCTAssertFalse(supplementary.isHidden)
        XCTAssertLessThanOrEqual(supplementary.frame.maxY, actions.frame.minY + 0.5)
        XCTAssertEqual(actions.bounds.width, 194, accuracy: 0.5)
        XCTAssertLessThanOrEqual(actions.frame.maxX, actions.superview?.bounds.maxX ?? 0)
    }

    func testPostSnapshotUpdatesAreQueuedWhileAnApplyIsInFlight() {
        XCTAssertEqual(
            TopicDetailSnapshotPolicy.decision(
                isApplying: true,
                currentItemIDs: [1, 2],
                requestedItemIDs: [1, 2, 3]
            ),
            .queue
        )
        XCTAssertEqual(
            TopicDetailSnapshotPolicy.decision(
                isApplying: false,
                currentItemIDs: [1, 2],
                requestedItemIDs: [1, 2]
            ),
            .skip
        )
        XCTAssertEqual(
            TopicDetailSnapshotPolicy.decision(
                isApplying: false,
                currentItemIDs: [1, 2],
                requestedItemIDs: [1, 2, 3]
            ),
            .apply
        )
    }

    func testLinkTextViewMeasuresWrappedAttachmentBeforeFirstLayout() {
        let textView = LinkTextView()
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = NSAttributedString(
            string: "新鲜 grok cpa 第二弹 2000 个号 7z（1001.5 KB）",
            attributes: [.font: UIFont.systemFont(ofSize: 17)]
        )
        textView.preferredMeasurementWidth = 180

        let expectedHeight = ceil(textView.sizeThatFits(
            CGSize(width: 180, height: CGFloat.greatestFiniteMagnitude)
        ).height + 2)
        XCTAssertEqual(textView.intrinsicContentSize.height, expectedHeight)
        XCTAssertGreaterThan(expectedHeight, textView.font?.lineHeight ?? 0)
    }

    private func configure(
        _ cell: PostNativeCell,
        post: DiscourseTopicDetail.Post,
        sharedIssue: PostNativeCell.SharedIssueState? = nil
    ) {
        cell.configure(
            with: post,
            annotatedBlocks: [],
            config: .default(contentWidth: 354, baseURL: "https://linux.do"),
            delegate: nil,
            floorNumber: post.postNumber,
            postLink: nil,
            baseURL: "https://linux.do",
            hasUnsupportedBlocks: false,
            cookedHTML: post.cooked,
            validReactions: [],
            sharedIssue: sharedIssue
        )
    }

    private func decodePost(
        includesActionMetadata: Bool,
        replyCount: Int = 0
    ) throws -> DiscourseTopicDetail.Post {
        var object: [String: Any] = [
            "id": 8,
            "username": "sam",
            "created_at": "2026-07-19T00:00:00.000Z",
            "cooked": "<p>Hello</p>",
            "post_number": 8,
            "reply_count": replyCount,
        ]
        if includesActionMetadata {
            object["can_boost"] = true
            object["reactions"] = [[
                "id": "heart",
                "type": "emoji",
                "count": 3,
            ]]
            object["reaction_users_count"] = 3
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(DiscourseTopicDetail.Post.self, from: data)
    }

    private func actionStack(in root: UIView) -> UIStackView? {
        if let stack = root as? UIStackView,
           stack.arrangedSubviews.contains(where: { ($0 as? UIButton)?.accessibilityLabel == "收藏" }) {
            return stack
        }
        for subview in root.subviews {
            if let stack = actionStack(in: subview) {
                return stack
            }
        }
        return nil
    }

    private func view(in root: UIView, accessibilityIdentifier: String) -> UIView? {
        if root.accessibilityIdentifier == accessibilityIdentifier {
            return root
        }
        for subview in root.subviews {
            if let match = view(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return match
            }
        }
        return nil
    }

    private func descendants(in root: UIView) -> [UIView] {
        root.subviews + root.subviews.flatMap(descendants(in:))
    }
}

private extension UIColor {
    var relativeLuminanceForTesting: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return red * 0.2126 + green * 0.7152 + blue * 0.0722
    }
}
