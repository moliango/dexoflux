import UIKit

@MainActor
protocol DexoListRefreshPolicy: AnyObject {
    var isRefreshing: Bool { get }
    var isLoadingMore: Bool { get }
    
    func startPullToRefresh()
    func endPullToRefresh()
    func beginLoadingMore()
    func endLoadingMore()
    func forceScrollToTop(animated: Bool)
}

final class DexoListRefreshPolicy: NSObject {
    private weak var tableView: UITableView?
    private let viewModel: any DexoObservableObject
    
    init(tableView: UITableView, viewModel: any DexoObservableObject) {
        self.tableView = tableView
        self.viewModel = viewModel
    }
    
    func startPullToRefresh() {
        Task { @MainActor in
            viewModel.notifyChanged()
            tableView?.contentInset.top = 0
            forceScrollToTop(animated: false)
        }
    }
    
    func handleWillDisplay(at indexPath: IndexPath) {
        guard let tableView = tableView else { return }
        let totalRows = tableView.numberOfRows(inSection: 0)
        guard indexPath.row >= totalRows - 6 else { return }
        
        Task { @MainActor in
            if !viewModel.isLoadingMore {
                viewModel.notifyChanged()
            }
        }
    }
    
    func forceScrollToTop(animated: Bool) {
        guard let tableView = tableView else { return }
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.scrollToRow(at: indexPath, at: .top, animated: animated)
    }
}
