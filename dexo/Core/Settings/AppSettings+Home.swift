import UIKit
import ObjectiveC
import CoreText

// MARK: - Home
extension AppSettings {
    static func uniqueCategoryIds(_ ids: [Int]) -> [Int] {
        var seen = Set<Int>()
        return ids.filter { seen.insert($0).inserted }
    }

    var homePinnedCategoryIds: [Int] {
        get {
            defaults.stringArray(forKey: "homePinnedCategoryIds")?
                .compactMap(Int.init) ?? []
        }
        set {
            let uniqueIds = Self.uniqueCategoryIds(newValue)
            defaults.set(uniqueIds.map(String.init), forKey: "homePinnedCategoryIds")
            notifyChanged()
        }
    }

    func addHomePinnedCategoryId(_ categoryId: Int) {
        var ids = homePinnedCategoryIds
        guard !ids.contains(categoryId) else { return }
        ids.append(categoryId)
        homePinnedCategoryIds = ids
    }

    func removeHomePinnedCategoryId(_ categoryId: Int) {
        let ids = homePinnedCategoryIds.filter { $0 != categoryId }
        homePinnedCategoryIds = ids
    }
}
