import UIKit
import ObjectiveC
import CoreText

// MARK: - Reading
extension AppSettings {

    var readingComfortMode: Bool {
        get { defaults.bool(forKey: "readingComfortMode") }
        set {
            defaults.set(newValue, forKey: "readingComfortMode")
            notifyChanged()
        }
    }

    var hideScrollIndicators: Bool {
        get { bool(forKey: "hideScrollIndicators", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "hideScrollIndicators")
            notifyChanged()
        }
    }

    var homeIncomingTopicsBannerFloatingEnabled: Bool {
        get { bool(forKey: "homeIncomingTopicsBannerFloatingEnabled", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "homeIncomingTopicsBannerFloatingEnabled")
            notifyChanged()
        }
    }

    var openExternalLinksInAppBrowser: Bool {
        get { bool(forKey: "openExternalLinksInAppBrowser", defaultValue: true) }
        set {
            defaults.set(newValue, forKey: "openExternalLinksInAppBrowser")
            notifyChanged()
        }
    }
}
