enum PostEditingPolicy {
    static func canShowEditAction(for post: DiscourseTopicDetail.Post) -> Bool {
        post.canEdit
    }
}
