import Foundation

final class ForumListViewModel: DexoObservableObject {
    var forums: [ForumInstance] = []
    var isLoading = false
    var errorMessage: String?

    func loadForums() {
        isLoading = true
        errorMessage = nil
        notifyChanged()
        do {
            let allForums = try DatabaseManager.shared.fetchAllForums()
            let linuxDoForums = allForums.filter(\.isLinuxDoDefault)
            forums = linuxDoForums.isEmpty ? [DatabaseManager.shared.defaultForum()] : linuxDoForums
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }

    func deleteForum(at index: Int) {
        guard index < forums.count else { return }
        let forum = forums[index]
        AuthManager.shared.logout(forum: forum)
        do {
            try DatabaseManager.shared.deleteForum(forum)
            forums.remove(at: index)
        } catch {
            errorMessage = error.localizedDescription
        }
        notifyChanged()
    }
}
