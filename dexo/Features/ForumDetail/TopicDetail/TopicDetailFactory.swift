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
        // WeChat + Telegram share the chat-bubble detail surface (styled via ChatTopicStyle).
        if AppSettings.shared.themeStyle.usesChatTopicDetail {
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
