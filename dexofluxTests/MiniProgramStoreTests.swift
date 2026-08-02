import XCTest
@testable import dexoflux

@MainActor
final class MiniProgramStoreTests: XCTestCase {
    func testDefaultCatalogSeedsBuiltInsInStableOrder() {
        let store = makeStore()

        XCTAssertEqual(store.visiblePrograms().map(\.id), [
            MiniProgramID.ldc,
            MiniProgramID.cdk,
            MiniProgramID.newAPICheckIn,
            MiniProgramID.ldcStore,
        ])
        XCTAssertEqual(store.visiblePrograms().map(\.displayName), [
            "LDC",
            "CDK",
            "NewAPI 签到",
            "LD 士多",
        ])
        XCTAssertTrue(store.visiblePrograms().allSatisfy(\.isBuiltIn))
    }

    func testBuiltInsCanBeHiddenButNotDeleted() {
        let store = makeStore()

        store.setProgram(MiniProgramID.ldc, isVisible: false)
        XCTAssertFalse(store.visiblePrograms().map(\.id).contains(MiniProgramID.ldc))
        XCTAssertEqual(store.program(id: MiniProgramID.ldc)?.isVisible, false)

        XCTAssertFalse(store.deleteProgram(id: MiniProgramID.ldc))
        XCTAssertNotNil(store.program(id: MiniProgramID.ldc))

        store.setProgram(MiniProgramID.ldc, isVisible: true)
        XCTAssertTrue(store.visiblePrograms().map(\.id).contains(MiniProgramID.ldc))
    }

    func testCustomURLProgramCanBeAddedEditedAndDeleted() throws {
        let store = makeStore()

        let id = try store.addCustomProgram(
            name: "Example",
            url: XCTUnwrap(URL(string: "https://example.com/app")),
            categoryID: MiniProgramCategoryID.tools,
            icon: .remote(URL(string: "https://example.com/icon.png")!)
        )

        XCTAssertEqual(store.program(id: id)?.displayName, "Example")
        XCTAssertEqual(store.program(id: id)?.normalizedURLString, "https://example.com/app")
        XCTAssertEqual(store.program(id: id)?.categoryID, MiniProgramCategoryID.tools)

        try store.updateCustomProgram(
            id: id,
            name: "Example App",
            url: XCTUnwrap(URL(string: "https://example.com/next")),
            categoryID: MiniProgramCategoryID.ai,
            icon: .local(relativePath: "MiniProgramIcons/example.png"),
            isVisible: false
        )

        XCTAssertEqual(store.program(id: id)?.displayName, "Example App")
        XCTAssertEqual(store.program(id: id)?.normalizedURLString, "https://example.com/next")
        XCTAssertEqual(store.program(id: id)?.categoryID, MiniProgramCategoryID.ai)
        XCTAssertEqual(store.program(id: id)?.icon, .local(relativePath: "MiniProgramIcons/example.png"))
        XCTAssertEqual(store.program(id: id)?.isVisible, false)

        XCTAssertTrue(store.deleteProgram(id: id))
        XCTAssertNil(store.program(id: id))
    }

    func testCategoryDeletionMovesProgramsToOtherWithoutDeletingThem() throws {
        let store = makeStore()
        let categoryID = store.addCategory(name: "阅读")
        let programID = try store.addCustomProgram(
            name: "Read",
            url: XCTUnwrap(URL(string: "https://read.example.com")),
            categoryID: categoryID,
            icon: .system(symbolName: "globe")
        )

        XCTAssertTrue(store.deleteCategory(id: categoryID))

        XCTAssertNil(store.category(id: categoryID))
        XCTAssertEqual(store.program(id: programID)?.categoryID, MiniProgramCategoryID.other)
    }

    func testProgramAndCategoryOrderingPersistsAcrossReloads() throws {
        let defaults = makeDefaults()
        let first = MiniProgramStore(defaults: defaults)
        let customID = try first.addCustomProgram(
            name: "Tool",
            url: XCTUnwrap(URL(string: "https://tool.example.com")),
            categoryID: MiniProgramCategoryID.tools,
            icon: .system(symbolName: "hammer")
        )
        first.moveProgram(id: customID, to: 0)
        let categoryID = first.addCategory(name: "Alpha")
        first.moveCategory(id: categoryID, to: 0)

        let reloaded = MiniProgramStore(defaults: defaults)

        XCTAssertEqual(reloaded.allPrograms().first?.id, customID)
        XCTAssertEqual(reloaded.allCategories().first?.id, categoryID)
    }

    func testRecentProgramsExcludeHiddenAndDeletedPrograms() throws {
        let store = makeStore()
        let customID = try store.addCustomProgram(
            name: "Temp",
            url: XCTUnwrap(URL(string: "https://temp.example.com")),
            categoryID: MiniProgramCategoryID.other,
            icon: .system(symbolName: "globe")
        )

        store.recordOpen(programID: MiniProgramID.ldc)
        store.recordOpen(programID: customID)
        store.setProgram(customID, isVisible: false)

        XCTAssertEqual(store.recentPrograms().map(\.id), [MiniProgramID.ldc])

        XCTAssertTrue(store.deleteProgram(id: customID))
        XCTAssertEqual(store.recentPrograms().map(\.id), [MiniProgramID.ldc])
    }

    func testRemoveRecentOnlyDropsHistoryEntry() {
        let store = makeStore()
        store.recordOpen(programID: MiniProgramID.ldc)
        store.recordOpen(programID: MiniProgramID.cdk)
        XCTAssertEqual(store.recentPrograms().map(\.id), [MiniProgramID.cdk, MiniProgramID.ldc])

        XCTAssertTrue(store.removeRecent(programID: MiniProgramID.cdk))
        XCTAssertEqual(store.recentPrograms().map(\.id), [MiniProgramID.ldc])
        // Program itself remains visible in the catalog.
        XCTAssertNotNil(store.program(id: MiniProgramID.cdk))
        XCTAssertTrue(store.program(id: MiniProgramID.cdk)?.isVisible == true)

        XCTAssertFalse(store.removeRecent(programID: MiniProgramID.cdk))
    }

    func testInitializationDoesNotPostCatalogChangeNotification() {
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: MiniProgramStore.catalogDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = makeStore()

        XCTAssertEqual(notificationCount, 0)
    }

    func testMutationsPostCatalogChangeNotification() {
        let store = makeStore()
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: MiniProgramStore.catalogDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.setProgram(MiniProgramID.ldc, isVisible: false)

        XCTAssertEqual(notificationCount, 1)
    }

    private func makeStore() -> MiniProgramStore {
        MiniProgramStore(defaults: makeDefaults())
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "MiniProgramStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
