import ObjectiveC
import CoreText
import UIKit

final class AppSettings: DexoObservableObject {
    static let shared = AppSettings()
    static let topicTitleReferencePointSize: CGFloat = 15
    static let minimumFontScalePercent = 30
    static let maximumFontScalePercent = 150
    static let fontScaleStepPercent = 5
    static let defaultFontScalePercent = 100
    static let defaultInterfaceFontScalePercent = 100
    static let legacyInterfaceFontDefaultPercent = 85
    /// Default visual size for a 15pt source interface label (Me tab body chrome, etc.).
    static let interfaceFontDefaultVisualPointSize: CGFloat = 14.67
    static let interfaceFontReferencePointSize: CGFloat = 15
    static let interfaceFontDefaultVisualMultiplier: CGFloat =
        interfaceFontDefaultVisualPointSize / interfaceFontReferencePointSize

    let defaults = UserDefaults.standard

    private override init() {
        super.init()
        migrateFontScaleSettingsIfNeeded()
        migrateLegacyCustomContentFontIfNeeded()
        registerStoredContentFonts()
        applyLanguage()
    }

    static func normalizedFontScalePercent(_ value: Int) -> Int {
        min(max(value, minimumFontScalePercent), maximumFontScalePercent)
    }

    private func migrateFontScaleSettingsIfNeeded() {
        if defaults.object(forKey: "contentFontScalePercent") == nil,
           defaults.object(forKey: "contentFontSize") != nil {
            let legacySize = ContentFontSize(rawValue: defaults.integer(forKey: "contentFontSize")) ?? .standard
            defaults.set(legacySize.legacyScalePercent, forKey: "contentFontScalePercent")
            defaults.set(ContentFontSize.standard.rawValue, forKey: "contentFontSize")
        }
        migrateInterfaceFontScaleBaselineIfNeeded()
    }

    private func migrateInterfaceFontScaleBaselineIfNeeded() {
        let migrationKey = "interfaceFontScaleBaselineV2"
        guard !defaults.bool(forKey: migrationKey) else { return }
        if defaults.object(forKey: "interfaceFontScalePercent") != nil {
            let oldValue = Self.normalizedFontScalePercent(defaults.integer(forKey: "interfaceFontScalePercent"))
            let migratedValue = Int((CGFloat(oldValue) / CGFloat(Self.legacyInterfaceFontDefaultPercent) * CGFloat(Self.defaultInterfaceFontScalePercent)).rounded())
            defaults.set(Self.normalizedFontScalePercent(migratedValue), forKey: "interfaceFontScalePercent")
        }
        defaults.set(true, forKey: migrationKey)
    }
}
