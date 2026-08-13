import Foundation
import UIKit

enum APNsPushRegistration {
    private static let tokenKey = "apns.deviceToken"

    /// Personal (free) teams cannot enable Push Notifications. Set `true` after
    /// switching to a paid Apple Developer account and restoring `aps-environment`.
    static let isEnabled = false

    static var deviceTokenHex: String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static func register() {
        guard isEnabled else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func hexString(from token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    static func storeDeviceToken(_ token: Data) {
        let hex = hexString(from: token)
        UserDefaults.standard.set(hex, forKey: tokenKey)
        DohDebugLog.record("apns token length=\(token.count)", subsystem: "Push")
    }

    static func handleRemoteNotification(
        userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            DohDebugLog.record("apns remote keys=\(userInfo.count)", subsystem: "Push")
            let success = await BackgroundNotificationDeliveryPipeline.shared.refreshInBackground()
            completionHandler(success ? .newData : .noData)
        }
    }
}
