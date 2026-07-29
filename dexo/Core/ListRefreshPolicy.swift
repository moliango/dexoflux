import UIKit

final class DexoListRefreshPolicy: NSObject {
    private weak var tableView: UITableView?
    private let viewModel: DexoObservableObject
    private var isRefreshing = false
    private var isLoadingMore = false
    private var loadMoreTask: Task<Void, Never>?
    private let onRefresh: () -> Void
    private let onLoadMore: () -> Void

    init(tableView: UITableView, viewModel: DexoObservableObject, onRefresh: @escaping () -> Void, onLoadMore: @escaping () -> Void) {
        self.tableView = tableView
        self.viewModel = viewModel
        self.onRefresh = onRefresh
        self.onLoadMore = onLoadMore
    }

    func startPullToRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            viewModel.notifyChanged()
            tableView?.contentInset.top = 0
            forceScrollToTop(animated: false)
            onRefresh()
            isRefreshing = false
        }
    }

    func handleWillDisplay(at indexPath: IndexPath) {
        guard let tableView = tableView else { return }
        let totalRows = tableView.numberOfRows(inSection: 0)
        guard indexPath.row >= totalRows - 6 else { return }
        guard !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreTask = Task { [weak self] in
            guard let self = self else { return }
            viewModel.notifyChanged()
            onLoadMore()
            isLoadingMore = false
        }
    }

    func cancelLoadMore() {
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
    }

    func forceScrollToTop(animated: Bool) {
        guard let tableView = tableView else { return }
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.scrollToRow(at: indexPath, at: .top, animated: animated)
    }
}
