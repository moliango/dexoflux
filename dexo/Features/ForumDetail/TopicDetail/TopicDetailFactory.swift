import UIKit

/// Picks classic vs chat-style Topic Detail (WeChat / Telegram) without mutating classic VC.
enum TopicDetailFactory {
    static func make(
        api: DiscourseAPI,
        topicId: Int,
        initialFloor: Int? = nil,
        initialPostId: Int? = nil,
        lastReadPostNumber: Int? = nil,
        forum: ForumInstance? = nil,
        preferNested: Bool = false
    ) -> UIViewController {
        // WeChat + Telegram default to chat-bubble detail; user can opt into classic via
        // Appearance →「聊天式话题详情」(`chatTopicDetailEnabled`, default on).
        if AppSettings.shared.prefersChatTopicDetail {
            let vc = WeChatTopicDetailViewController(
                api: api,
                topicId: topicId,
                initialFloor: initialFloor,
                initialPostId: initialPostId,
                lastReadPostNumber: lastReadPostNumber,
                forum: forum
            )
            if preferNested || AppSettings.shared.nestedReplyViewEnabled {
                vc.preferNestedOnLoad = true
            }
            return vc
        }
        let vc = TopicDetailViewController(
            api: api,
            topicId: topicId,
            initialFloor: initialFloor,
            initialPostId: initialPostId,
            lastReadPostNumber: lastReadPostNumber,
            forum: forum
        )
        if preferNested || AppSettings.shared.nestedReplyViewEnabled {
            vc.preferNestedOnLoad = true
        }
        return vc
    }
}
