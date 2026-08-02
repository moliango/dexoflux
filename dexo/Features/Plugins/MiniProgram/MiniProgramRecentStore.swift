import Foundation

/// UserDefaults-backed recent mini-program opens, capped and newest-first.
enum MiniProgramRecentStore {
    static func recentIDs() -> [String] {
        MiniProgramStore.shared.recentPrograms().map(\.id)
    }

    static func recentPrograms() -> [MiniProgramDescriptor] {
        MiniProgramStore.shared.recentPrograms().map(MiniProgramDescriptor.init(record:))
    }

    static func recordOpen(programID: String) {
        MiniProgramStore.shared.recordOpen(programID: programID)
    }

    @discardableResult
    static func remove(programID: String) -> Bool {
        MiniProgramStore.shared.removeRecent(programID: programID)
    }
}
