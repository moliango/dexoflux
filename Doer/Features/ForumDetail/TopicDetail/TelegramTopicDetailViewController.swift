import UIKit

final class TelegramTopicDetailViewController: ChatTopicDetailViewController {
    override func chatThemeStyle() -> ChatTopicStyle { .telegram }

    override func dateSeparatorText(for post: DiscourseTopicDetail.Post, at row: Int) -> String? {
        chatDateSeparatorText(for: post, at: row)
    }

    override func incomingLinkColor(defaultColor: UIColor) -> UIColor {
        chatThemeStyle().accentColor
    }

    override func registerChatCells(on tableView: UITableView) {
        tableView.register(TelegramChatPostCell.self, forCellReuseIdentifier: WeChatChatPostCell.reuseIdentifier)
    }

    override func estimatedChatRowHeight() -> CGFloat { 168 }

    override func jumpScrollPosition() -> UITableView.ScrollPosition { .bottom }

    override func scrollsToBottomWhenOpeningLatest() -> Bool { true }

    override func animatesCanvasColorChange() -> Bool { true }
}
