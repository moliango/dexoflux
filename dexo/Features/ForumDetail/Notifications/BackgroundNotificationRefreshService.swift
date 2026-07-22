import BackgroundTasks
import Foundation

enum BackgroundNotificationRefreshPolicy {
    static let taskIdentifier = "com.naine.dexoflux.notificationRefresh"
    static let minimumInterval: TimeInterval = 15 * 60

    static func earliestBeginDate(now: Date = Date()) -> Date {
        now.addingTimeInterval(minimumInterval)
    }

    static func completionSuccess(workSucceeded: Bool, didExpire: Bool) -> Bool {
        workSucceeded && !didExpire
    }
}

@MainActor
final class BackgroundNotificationRefreshService {
    static let shared = BackgroundNotificationRefreshService()

    private struct ActiveRun {
        let id: UUID
        let systemTask: BGAppRefreshTask
        let work: Task<Bool, Never>
        var didExpire: Bool
    }

    private let scheduler = BGTaskScheduler.shared
    private let syncEngine = BackgroundNotificationSyncEngine.shared
    private var isRegistered = false
    private var activeRun: ActiveRun?

    private init() {}

    func register() {
        guard !isRegistered else { return }
        isRegistered = scheduler.register(
            forTaskWithIdentifier: BackgroundNotificationRefreshPolicy.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                BackgroundNotificationRefreshService.shared.handle(refreshTask)
            }
        }
        if !isRegistered {
            DohDebugLog.record("background task registration failed", subsystem: "BackgroundRefresh")
        }
    }

    func scheduleIfNeeded() {
        guard isRegistered else { return }
        guard syncEngine.hasEligibleForums() else {
            scheduler.cancel(taskRequestWithIdentifier: BackgroundNotificationRefreshPolicy.taskIdentifier)
            BackgroundNotificationDeliveryPipeline.shared.retainBadgeBaseURLs([])
            return
        }

        scheduler.cancel(taskRequestWithIdentifier: BackgroundNotificationRefreshPolicy.taskIdentifier)
        let request = BGAppRefreshTaskRequest(identifier: BackgroundNotificationRefreshPolicy.taskIdentifier)
        request.earliestBeginDate = BackgroundNotificationRefreshPolicy.earliestBeginDate()
        do {
            try scheduler.submit(request)
            DohDebugLog.record("background task scheduled", subsystem: "BackgroundRefresh")
        } catch {
            DohDebugLog.record(
                "background task schedule failed: \(error.localizedDescription)",
                subsystem: "BackgroundRefresh"
            )
        }
    }

    private func handle(_ systemTask: BGAppRefreshTask) {
        scheduleIfNeeded()
        guard activeRun == nil else {
            systemTask.setTaskCompleted(success: false)
            return
        }

        let runID = UUID()
        let work = Task { @MainActor in
            await BackgroundNotificationDeliveryPipeline.shared.refreshInBackground()
        }
        activeRun = ActiveRun(id: runID, systemTask: systemTask, work: work, didExpire: false)

        systemTask.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.expire(runID: runID)
            }
        }

        Task { @MainActor [weak self] in
            let success = await work.value
            self?.finish(runID: runID, success: success)
        }
    }

    private func expire(runID: UUID) {
        guard let activeRun, activeRun.id == runID else { return }
        self.activeRun?.didExpire = true
        activeRun.work.cancel()
        syncEngine.cancelCurrentRefresh()
    }

    private func finish(runID: UUID, success: Bool) {
        guard let activeRun, activeRun.id == runID else { return }
        let completionSuccess = BackgroundNotificationRefreshPolicy.completionSuccess(
            workSucceeded: success,
            didExpire: activeRun.didExpire
        )
        self.activeRun = nil
        activeRun.systemTask.setTaskCompleted(success: completionSuccess)
        DohDebugLog.record(
            "background task completed success=\(completionSuccess)",
            subsystem: "BackgroundRefresh"
        )
    }

}
