import UIKit

final class DexoListRefreshPolicy: NSObject {
    private weak var tableView: UITableView?
    private let viewModel: DexoObservableObject
    
    init(tableView: UITableView, viewModel: DexoObservableObject) {
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
            viewModel.notifyChanged()
        }
    }
    
    func forceScrollToTop(animated: Bool) {
        guard let tableView = tableView else { return }
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.scrollToRow(at: indexPath, at: .top, animated: animated)
    }
}
