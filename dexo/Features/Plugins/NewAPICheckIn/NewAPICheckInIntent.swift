import Foundation

#if canImport(AppIntents)
import AppIntents

@available(iOS 16.0, *)
struct NewAPICheckInAllIntent: AppIntent {
    static var title: LocalizedStringResource = "NewAPI 全部签到"
    static var description = IntentDescription("执行 DexoFlux 中配置的全部 NewAPI 平台签到。")
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await NewAPICheckInRuntime.shared.service.signInAll()
        return .result(dialog: IntentDialog(stringLiteral: summary.localizedSummary))
    }
}

@available(iOS 16.0, *)
struct NewAPICheckInShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewAPICheckInAllIntent(),
            phrases: [
                "用 \(.applicationName) NewAPI 全部签到",
                "用 \(.applicationName) 签到全部 NewAPI",
            ],
            shortTitle: "NewAPI 签到",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
#endif
