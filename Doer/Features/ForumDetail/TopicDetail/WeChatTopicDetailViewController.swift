import UIKit

final class WeChatTopicDetailViewController: ChatTopicDetailViewController {
    override func chatThemeStyle() -> ChatTopicStyle { .weChat }

    override func dateSeparatorText(for post: DiscourseTopicDetail.Post, at row: Int) -> String? {
        chatDateSeparatorText(for: post, at: row)
    }

    override func registerChatCells(on tableView: UITableView) {
        tableView.register(WeChatChatPostCell.self, forCellReuseIdentifier: WeChatChatPostCell.reuseIdentifier)
    }

    override func estimatedChatRowHeight() -> CGFloat { 140 }

    override func jumpScrollPosition() -> UITableView.ScrollPosition { .middle }

    override func scrollsToBottomWhenOpeningLatest() -> Bool { true }

    override func animatesCanvasColorChange() -> Bool { false }
}
