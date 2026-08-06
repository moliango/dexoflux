import UIKit

/// Picks classic vs WeChat chat Topic Detail without mutating the classic VC.
enum TopicDetailFactory {
    static func make(
        api: DiscourseAPI,
        topicId: Int,
        initialFloor: Int? = nil,
        initialPostId: Int? = nil,
        lastReadPostNumber: Int? = nil,
        forum: ForumInstance? = nil
    ) -> UIViewController {
        if AppSettings.shared.themeStyle == .weChat {
            return WeChatTopicDetailViewController(
                api: api,
                topicId: topicId,
                initialFloor: initialFloor,
                initialPostId: initialPostId,
                lastReadPostNumber: lastReadPostNumber,
                forum: forum
            )
        }
        return TopicDetailViewController(
            api: api,
            topicId: topicId,
            initialFloor: initialFloor,
            initialPostId: initialPostId,
            lastReadPostNumber: lastReadPostNumber,
            forum: forum
        )
    }
}
