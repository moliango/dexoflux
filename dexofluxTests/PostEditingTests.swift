import Alamofire
import UIKit
import XCTest
@testable import dexoflux

@MainActor
final class PostEditingTests: XCTestCase {
    func testPostDecodesEditingFields() throws {
        let post = try decodePost(extra: [
            "raw": "before **edit**",
            "can_edit": true,
            "yours": true,
        ])

        XCTAssertEqual(post.raw, "before **edit**")
        XCTAssertTrue(post.canEdit)
        XCTAssertTrue(post.yours)
    }

    func testPostEditingFieldsDefaultSafelyWhenMissing() throws {
        let post = try decodePost(extra: [:])

        XCTAssertNil(post.raw)
        XCTAssertFalse(post.canEdit)
        XCTAssertFalse(post.yours)
    }

    func testPostEditingRoutesUseSinglePostEndpoint() {
        XCTAssertEqual(DiscourseRouter.post(id: 42).method, .get)
        XCTAssertEqual(DiscourseRouter.post(id: 42).path, "/posts/42.json")
        XCTAssertEqual(DiscourseRouter.updatePost(id: 42).method, .put)
        XCTAssertEqual(DiscourseRouter.updatePost(id: 42).path, "/posts/42.json")
    }

    func testUpdateParametersNestRawUnderPost() throws {
        let parameters = PostEditingRequest.parameters(raw: "updated text")
        let post = try XCTUnwrap(parameters["post"] as? Parameters)

        XCTAssertEqual(post["raw"] as? String, "updated text")
    }

    func testEditActionRequiresServerPermission() throws {
        let editable = try decodePost(extra: ["can_edit": true, "yours": true])
        let expired = try decodePost(extra: ["can_edit": false, "yours": true])

        XCTAssertTrue(PostEditingPolicy.canShowEditAction(for: editable))
        XCTAssertFalse(PostEditingPolicy.canShowEditAction(for: expired))
    }

    func testComposerEditModeKeepsTargetPostId() {
        XCTAssertEqual(ReplyComposerSubmissionMode.edit(postId: 42), .edit(postId: 42))
        XCTAssertNotEqual(ReplyComposerSubmissionMode.edit(postId: 42), .reply)
    }

    func testCellReuseRemovesEditActionWithoutPermission() throws {
        let cell = PostNativeCell(style: .default, reuseIdentifier: PostNativeCell.reuseIdentifier)
        configure(cell, post: try decodePost(extra: ["can_edit": true]))
        XCTAssertTrue(moreMenuTitles(in: cell).contains(String(localized: "post.edit.action")))

        cell.prepareForReuse()
        configure(cell, post: try decodePost(extra: ["can_edit": false]))
        XCTAssertFalse(moreMenuTitles(in: cell).contains(String(localized: "post.edit.action")))
    }

    private func decodePost(extra: [String: Any]) throws -> DiscourseTopicDetail.Post {
        var object: [String: Any] = [
            "id": 42,
            "username": "sam",
            "created_at": "2026-07-19T00:00:00.000Z",
            "cooked": "<p>Hello</p>",
            "post_number": 2,
            "reply_count": 0,
        ]
        object.merge(extra) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(DiscourseTopicDetail.Post.self, from: data)
    }

    private func configure(_ cell: PostNativeCell, post: DiscourseTopicDetail.Post) {
        cell.configure(
            with: post,
            annotatedBlocks: [],
            config: .default(contentWidth: 320, baseURL: "https://linux.do"),
            delegate: nil,
            floorNumber: post.postNumber,
            postLink: nil,
            baseURL: "https://linux.do",
            hasUnsupportedBlocks: false,
            cookedHTML: post.cooked,
            validReactions: [],
            sharedIssue: nil
        )
    }

    private func moreMenuTitles(in root: UIView) -> [String] {
        if let button = root as? UIButton,
           button.accessibilityLabel == "更多",
           let menu = button.menu {
            return menu.children.map(\.title)
        }
        return root.subviews.flatMap(moreMenuTitles(in:))
    }
}
