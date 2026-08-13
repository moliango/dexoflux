import Foundation

enum HomeConnectivityRecoveryPolicy {
    /// Flapping networks (subway Wi-Fi / LTE) must not rebuild a healthy Home list.
    static func shouldReloadTopicList(topicsEmpty: Bool, hasError: Bool) -> Bool {
        topicsEmpty || hasError
    }
}
