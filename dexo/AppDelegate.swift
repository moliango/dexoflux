//
//  AppDelegate.swift
//  dexo
//
//  Created by Eilgnaw on 3/21/26.
//

import SDWebImage
import SDWebImageSVGCoder
import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AppSettings.shared.applyLanguage()
        AppSettings.shared.installGlobalFontSupport()
        BackgroundNotificationRefreshService.shared.register()
        BackgroundNotificationRefreshService.shared.scheduleIfNeeded()
        UNUserNotificationCenter.current().delegate = self
        SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
        AvatarImageLoader.configureGlobalImageLoading()
        if AppSettings.shared.clearImageCacheOnLaunch {
            SDImageCache.shared.clearMemory()
            SDImageCache.shared.clearDisk {}
        }
        LightweightDohProxyService.shared.configureFromSettings()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let baseURL = userInfo[ForumNotificationRoute.UserInfoKey.baseURL] as? String else { return }
        let notificationId = userInfo[ForumNotificationRoute.UserInfoKey.notificationId] as? Int
        let topicId = userInfo[ForumNotificationRoute.UserInfoKey.topicId] as? Int
        let postNumber = userInfo[ForumNotificationRoute.UserInfoKey.postNumber] as? Int
        await MainActor.run {
            let route = ForumNotificationRoute(
                baseURL: baseURL,
                notificationId: notificationId,
                topicId: topicId,
                postNumber: postNumber
            )
            ForumNotificationRouteStore.shared.enqueue(route)
            ForumNotificationRoutePresenter.presentPendingRouteIfNeeded()
        }
    }
}
