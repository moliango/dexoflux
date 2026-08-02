import Foundation

final class MiniProgramStore {
      static let shared = MiniProgramStore()
    static let catalogDidChangeNotification = Notification.Name("DexoMiniProgramCatalogDidChange")

    private static let defaultsKey = "miniProgram.catalog.v1"
    private static let currentVersion = 1
    /// Matches drawer grid: 4 columns × 2 rows.
    private static let maxRecentCount = 8
    private static let maxFavoriteCount = 8
    /// 「我的小程序」收藏列表（首页「常用」区只展示这些，最多 8 个）。
    private var favoriteProgramIDs: [String] {
        get { snapshot.favoriteProgramIDs }
        set { snapshot.favoriteProgramIDs = newValue }
    }

    func favoritePrograms() -> [MiniProgramRecord] {
        let byID = Dictionary(uniqueKeysWithValues: allPrograms().map { ($0.id, $0) })
        return favoriteProgramIDs
            .compactMap { byID[$0] }
            .prefix(Self.maxFavoriteCount)
            .sorted { lhs, rhs in
                let lhsOrder = favoriteProgramIDs.firstIndex(of: lhs.id) ?? 0
                let rhsOrder = favoriteProgramIDs.firstIndex(of: rhs.id) ?? 0
                return lhsOrder < rhsOrder
            }
    }

    func addFavorite(_ programID: String) {
        guard !favoriteProgramIDs.contains(programID) else { return }
        var ids = favoriteProgramIDs
        ids.insert(programID, at: 0)
        favoriteProgramIDs = Array(ids.prefix(Self.maxFavoriteCount))
        save()
    }

    func removeFavorite(_ programID: String) {
        let before = favoriteProgramIDs
        favoriteProgramIDs = before.filter { $0 != programID }
        guard before.count != favoriteProgramIDs.count else { return }
        save()
    }

    func setFavorite(_ programID: String, isFavorite: Bool) {
        guard let index = favoriteProgramIDs.firstIndex(of: programID) else {
            if isFavorite {
                addFavorite(programID)
            }
            return
        }
        if !isFavorite {
            favoriteProgramIDs.remove(at: index)
        }
        save()
    }

    func toggleFavorite(_ programID: String) {
        if favoriteProgramIDs.contains(programID) {
            removeFavorite(programID)
        } else {
            addFavorite(programID)
        }
    }

    private let defaults: UserDefaults
    private var snapshot: MiniProgramCatalogSnapshot

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(MiniProgramCatalogSnapshot.self, from: data) {
            snapshot = Self.normalized(decoded)
        } else {
            snapshot = Self.normalized(MiniProgramCatalogSnapshot(
                version: Self.currentVersion,
                programs: [],
                categories: [],
                recentProgramIDs: [],
                favoriteProgramIDs: []
            ))
        }
        save(notify: false)
    }

    func allPrograms() -> [MiniProgramRecord] {
        snapshot.programs.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id < rhs.id
        }
    }

    func visiblePrograms() -> [MiniProgramRecord] {
        allPrograms().filter(\.isVisible)
    }

    func programs(in categoryID: String) -> [MiniProgramRecord] {
        visiblePrograms().filter { $0.categoryID == categoryID }
    }

    func program(id: String) -> MiniProgramRecord? {
        snapshot.programs.first { $0.id == id }
    }

    func allCategories() -> [MiniProgramCategory] {
        snapshot.categories.sorted { lhs, rhs in
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id < rhs.id
        }
    }

    func category(id: String) -> MiniProgramCategory? {
        snapshot.categories.first { $0.id == id }
    }

    @discardableResult
    func addCategory(name: String) -> String {
        let id = "category.\(UUID().uuidString.lowercased())"
        let order = (snapshot.categories.map(\.order).max() ?? -1) + 1
        snapshot.categories.append(MiniProgramCategory(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            order: order,
            isBuiltIn: false
        ))
        save()
        return id
    }

    @discardableResult
    func deleteCategory(id: String) -> Bool {
        guard let index = snapshot.categories.firstIndex(where: { $0.id == id }),
              !snapshot.categories[index].isBuiltIn
        else { return false }
        snapshot.categories.remove(at: index)
        for programIndex in snapshot.programs.indices where snapshot.programs[programIndex].categoryID == id {
            snapshot.programs[programIndex].categoryID = MiniProgramCategoryID.other
        }
        normalizeOrders()
        save()
        return true
    }

    func moveCategory(id: String, to destinationIndex: Int) {
        var categories = allCategories()
        guard let sourceIndex = categories.firstIndex(where: { $0.id == id }) else { return }
        let category = categories.remove(at: sourceIndex)
        categories.insert(category, at: clampedIndex(destinationIndex, count: categories.count))
        for index in categories.indices {
            categories[index].order = index
        }
        snapshot.categories = categories
        save()
    }

    func renameCategory(id: String, name: String) {
        guard let index = snapshot.categories.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        snapshot.categories[index].name = trimmed
        save()
    }

    @discardableResult
    func addCustomProgram(
        name: String,
        url: URL,
        categoryID: String,
        icon: MiniProgramIcon
    ) throws -> String {
        guard let normalizedURL = Self.normalizedURLString(url) else {
            throw MiniProgramStoreError.invalidURL
        }
        let id = "custom.\(UUID().uuidString.lowercased())"
        let order = (snapshot.programs.map(\.order).max() ?? -1) + 1
        snapshot.programs.append(MiniProgramRecord(
            id: id,
            kind: .url,
            displayName: normalizedName(name, fallback: url.host ?? normalizedURL),
            urlString: normalizedURL,
            categoryID: categoryExists(categoryID) ? categoryID : MiniProgramCategoryID.other,
            icon: icon,
            isVisible: true,
            order: order
        ))
        save()
        return id
    }

    func updateCustomProgram(
        id: String,
        name: String,
        url: URL,
        categoryID: String,
        icon: MiniProgramIcon,
        isVisible: Bool
    ) throws {
        guard let index = snapshot.programs.firstIndex(where: { $0.id == id }) else {
            throw MiniProgramStoreError.programNotFound
        }
        guard !snapshot.programs[index].isBuiltIn else {
            throw MiniProgramStoreError.builtInCannotBeEditedAsCustom
        }
        guard let normalizedURL = Self.normalizedURLString(url) else {
            throw MiniProgramStoreError.invalidURL
        }
        snapshot.programs[index].displayName = normalizedName(name, fallback: url.host ?? normalizedURL)
        snapshot.programs[index].urlString = normalizedURL
        snapshot.programs[index].categoryID = categoryExists(categoryID) ? categoryID : MiniProgramCategoryID.other
        snapshot.programs[index].icon = icon
        snapshot.programs[index].isVisible = isVisible
        snapshot.recentProgramIDs = normalizedRecentIDs(snapshot.recentProgramIDs)
        save()
    }

    @discardableResult
    func deleteProgram(id: String) -> Bool {
        guard let index = snapshot.programs.firstIndex(where: { $0.id == id }),
              !snapshot.programs[index].isBuiltIn
        else { return false }
        snapshot.programs.remove(at: index)
        snapshot.recentProgramIDs = normalizedRecentIDs(snapshot.recentProgramIDs)
        normalizeOrders()
        save()
        return true
    }

    func setProgram(_ id: String, isVisible: Bool) {
        guard let index = snapshot.programs.firstIndex(where: { $0.id == id }) else { return }
        snapshot.programs[index].isVisible = isVisible
        snapshot.recentProgramIDs = normalizedRecentIDs(snapshot.recentProgramIDs)
        save()
    }

    func setProgram(_ id: String, categoryID: String) {
        guard let index = snapshot.programs.firstIndex(where: { $0.id == id }),
              categoryExists(categoryID)
        else { return }
        snapshot.programs[index].categoryID = categoryID
        save()
    }

    func moveProgram(id: String, to destinationIndex: Int) {
        var programs = allPrograms()
        guard let sourceIndex = programs.firstIndex(where: { $0.id == id }) else { return }
        let program = programs.remove(at: sourceIndex)
        programs.insert(program, at: clampedIndex(destinationIndex, count: programs.count))
        for index in programs.indices {
            programs[index].order = index
        }
        snapshot.programs = programs
        save()
    }

    func recordOpen(programID: String) {
        guard program(id: programID)?.isVisible == true else { return }
        var ids = snapshot.recentProgramIDs.filter { $0 != programID }
        ids.insert(programID, at: 0)
        snapshot.recentProgramIDs = Array(normalizedRecentIDs(ids).prefix(Self.maxRecentCount))
        save()
    }

    /// Removes a program from the recent list only (does not hide/delete the program itself).
    @discardableResult
    func removeRecent(programID: String) -> Bool {
        let before = snapshot.recentProgramIDs
        snapshot.recentProgramIDs = before.filter { $0 != programID }
        guard snapshot.recentProgramIDs != before else { return false }
        save()
        return true
    }

    func recentPrograms() -> [MiniProgramRecord] {
        let programsByID = Dictionary(uniqueKeysWithValues: visiblePrograms().map { ($0.id, $0) })
        return snapshot.recentProgramIDs.compactMap { programsByID[$0] }
    }

    private func categoryExists(_ id: String) -> Bool {
        snapshot.categories.contains { $0.id == id }
    }

    private func normalizedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedRecentIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        let visibleIDs = Set(snapshot.programs.filter(\.isVisible).map(\.id))
        return ids.filter { id in
            visibleIDs.contains(id) && seen.insert(id).inserted
        }
    }

    private func normalizeOrders() {
        var programs = allPrograms()
        for index in programs.indices {
            programs[index].order = index
        }
        snapshot.programs = programs

        var categories = allCategories()
        for index in categories.indices {
            categories[index].order = index
        }
        snapshot.categories = categories
    }

    private func clampedIndex(_ index: Int, count: Int) -> Int {
        min(max(index, 0), count)
    }

    private func save(notify: Bool = true) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        guard notify else { return }
        NotificationCenter.default.post(name: Self.catalogDidChangeNotification, object: self)
    }
}

private extension MiniProgramStore {
    static func normalized(_ snapshot: MiniProgramCatalogSnapshot) -> MiniProgramCatalogSnapshot {
        var next = snapshot
        next.version = currentVersion
        mergeBuiltInCategories(into: &next)
        mergeBuiltInPrograms(into: &next)
        normalizeReferences(in: &next)
        return next
    }

    static func normalizedURLString(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.host = host
        if components.path.isEmpty {
            components.path = ""
        }
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func mergeBuiltInCategories(into snapshot: inout MiniProgramCatalogSnapshot) {
        let existingIDs = Set(snapshot.categories.map(\.id))
        var order = (snapshot.categories.map(\.order).max() ?? -1) + 1
        for category in builtInCategories where !existingIDs.contains(category.id) {
            var inserted = category
            inserted.order = order
            snapshot.categories.append(inserted)
            order += 1
        }
    }

    static func mergeBuiltInPrograms(into snapshot: inout MiniProgramCatalogSnapshot) {
        let existingIDs = Set(snapshot.programs.map(\.id))
        var order = (snapshot.programs.map(\.order).max() ?? -1) + 1
        for program in builtInPrograms where !existingIDs.contains(program.id) {
            var inserted = program
            inserted.order = order
            snapshot.programs.append(inserted)
            order += 1
        }
    }

    static func normalizeReferences(in snapshot: inout MiniProgramCatalogSnapshot) {
        let categoryIDs = Set(snapshot.categories.map(\.id))
        for index in snapshot.programs.indices where !categoryIDs.contains(snapshot.programs[index].categoryID) {
            snapshot.programs[index].categoryID = MiniProgramCategoryID.other
        }
        let visibleIDs = Set(snapshot.programs.filter(\.isVisible).map(\.id))
        var seen = Set<String>()
        snapshot.recentProgramIDs = snapshot.recentProgramIDs.filter { id in
            visibleIDs.contains(id) && seen.insert(id).inserted
        }
    }

    static let builtInCategories: [MiniProgramCategory] = [
        MiniProgramCategory(id: MiniProgramCategoryID.tools, name: "工具", order: 0, isBuiltIn: true),
        MiniProgramCategory(id: MiniProgramCategoryID.ai, name: "AI", order: 1, isBuiltIn: true),
        MiniProgramCategory(id: MiniProgramCategoryID.community, name: "社区", order: 2, isBuiltIn: true),
        MiniProgramCategory(id: MiniProgramCategoryID.entertainment, name: "娱乐", order: 3, isBuiltIn: true),
        MiniProgramCategory(id: MiniProgramCategoryID.other, name: "其他", order: 4, isBuiltIn: true),
    ]

    static let builtInPrograms: [MiniProgramRecord] = [
        MiniProgramRecord(
            id: MiniProgramID.ldc,
            kind: .builtIn,
            displayName: "LDC",
            urlString: nil,
            categoryID: MiniProgramCategoryID.community,
            icon: .system(symbolName: "sparkles.rectangle.stack.fill"),
            isVisible: true,
            order: 0
        ),
        MiniProgramRecord(
            id: MiniProgramID.cdk,
            kind: .builtIn,
            displayName: "CDK",
            urlString: nil,
            categoryID: MiniProgramCategoryID.community,
            icon: .system(symbolName: "ticket.fill"),
            isVisible: true,
            order: 1
        ),
        MiniProgramRecord(
            id: MiniProgramID.newAPICheckIn,
            kind: .builtIn,
            displayName: "NewAPI 签到",
            urlString: nil,
            categoryID: MiniProgramCategoryID.tools,
            icon: .system(symbolName: "checkmark.circle.fill"),
            isVisible: true,
            order: 2
        ),
        MiniProgramRecord(
            id: MiniProgramID.ldcStore,
            kind: .builtIn,
            displayName: "LD 士多",
            urlString: "https://ldcstore.com",
            categoryID: MiniProgramCategoryID.community,
            icon: .system(symbolName: "bag.fill"),
            isVisible: true,
            order: 3
        ),
    ]
}
