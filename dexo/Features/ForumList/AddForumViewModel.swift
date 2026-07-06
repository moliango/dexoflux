import Foundation

final class AddForumViewModel: DexoObservableObject {
    var urlString = ""
    var isLoading = false
    var errorMessage: String?

    func addForum() async -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "add_forum.error.empty_url")
            notifyChanged()
            return false
        }

        var normalized = trimmed
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard URL(string: normalized) != nil else {
            errorMessage = String(localized: "add_forum.error.invalid_url")
            notifyChanged()
            return false
        }

        isLoading = true
        errorMessage = nil
        notifyChanged()

        do {
            let tempForum = ForumInstance.new(title: "", baseURL: normalized)
            let api = DiscourseAPI(forum: tempForum)
            let info = try await api.fetchBasicInfo()

            var forum = ForumInstance.new(
                title: info.title,
                baseURL: normalized,
                iconURL: resolveIconURL(base: normalized, info: info)
            )
            try DatabaseManager.shared.saveForum(&forum)
            isLoading = false
            notifyChanged()
            return true
        } catch {
            errorMessage = String(localized: "add_forum.error.connect \(error.localizedDescription)")
            isLoading = false
            notifyChanged()
            return false
        }
    }

    private func resolveIconURL(base: String, info: DiscourseBasicInfo) -> String? {
        // Prefer apple touch icon (180x180) > logo > favicon
        guard let path = info.appleTouchIconURL ?? info.logoURL ?? info.faviconURL else { return nil }
        if path.hasPrefix("http") {
            return path
        }
        return base + path
    }
}
