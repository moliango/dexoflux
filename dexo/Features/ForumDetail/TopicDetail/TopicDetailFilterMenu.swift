import UIKit

/// FluxDo-style topic content filters: author-only, top-level-only, nested tree.
enum TopicDetailFilterMenu {
    static func makeMenu(
        viewModel: TopicDetailViewModel,
        onChanged: @escaping () -> Void
    ) -> UIMenu {
        let author = UIAction(
            title: String(localized: "topic.filter_op", defaultValue: "只看题主"),
            image: UIImage(systemName: "person"),
            state: viewModel.isFilteringByOP ? .on : .off
        ) { _ in
            viewModel.setFilteringByOP(!viewModel.isFilteringByOP)
            onChanged()
        }

        let topLevel = UIAction(
            title: String(localized: "topic.filter_top_level", defaultValue: "只看顶层"),
            image: UIImage(systemName: "arrow.up.to.line"),
            state: viewModel.isFilteringTopLevel ? .on : .off
        ) { _ in
            viewModel.setFilteringTopLevel(!viewModel.isFilteringTopLevel)
            onChanged()
        }

        let nested = UIAction(
            title: String(localized: "topic.filter_nested", defaultValue: "树形视图"),
            image: UIImage(systemName: "list.bullet.indent"),
            state: viewModel.isNestedViewEnabled ? .on : .off
        ) { _ in
            viewModel.setNestedViewEnabled(!viewModel.isNestedViewEnabled)
            onChanged()
        }

        var children: [UIMenuElement] = [author, topLevel, nested]

        if viewModel.isFilteringByOP || viewModel.isFilteringTopLevel {
            children.append(UIMenu(options: .displayInline, children: [
                UIAction(
                    title: String(localized: "topic.filter_clear", defaultValue: "取消筛选"),
                    image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
                    attributes: .destructive
                ) { _ in
                    viewModel.clearTopicFilters()
                    onChanged()
                }
            ]))
        }

        return UIMenu(
            title: String(localized: "topic.filter", defaultValue: "筛选"),
            children: children
        )
    }

    static func makeBarButton(
        viewModel: TopicDetailViewModel,
        onChanged: @escaping () -> Void
    ) -> UIBarButtonItem {
        // Fill icon for content filters; tree mode is visible via menu checkmark only.
        let active = viewModel.isFilteringByOP || viewModel.isFilteringTopLevel
        let imageName = active
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
        let button = UIBarButtonItem(
            image: UIImage(systemName: imageName),
            menu: makeMenu(viewModel: viewModel, onChanged: onChanged)
        )
        button.accessibilityLabel = String(localized: "topic.filter", defaultValue: "筛选")
        return button
    }
}
