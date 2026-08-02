import UIKit
import ObjectiveC
import CoreText

enum DexoAppFontOverrideState {
    static var didInstall = false
    static var didExchangeSystemFont = false
    static var didExchangeWeightedSystemFont = false
    static var didExchangeBoldSystemFont = false
    static var didExchangeItalicSystemFont = false
}

enum DexoAppFontAssociatedKeys {
    static var sourcePointSize: UInt8 = 0
    static var baseInterfaceFont: UInt8 = 0
}

extension UIView {
    var dexoBaseInterfaceFont: UIFont? {
        get {
            objc_getAssociatedObject(self, &DexoAppFontAssociatedKeys.baseInterfaceFont) as? UIFont
        }
        set {
            objc_setAssociatedObject(
                self,
                &DexoAppFontAssociatedKeys.baseInterfaceFont,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

extension UIFont {
    var dexoAppFontSourcePointSize: CGFloat? {
        (objc_getAssociatedObject(self, &DexoAppFontAssociatedKeys.sourcePointSize) as? NSNumber)
            .map { CGFloat(truncating: $0) }
    }

    func dexoMarkAppFontSourcePointSize(_ pointSize: CGFloat) -> UIFont {
        objc_setAssociatedObject(
            self,
            &DexoAppFontAssociatedKeys.sourcePointSize,
            pointSize,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return self
    }

    static func installDexoAppFontOverride() {
        guard !DexoAppFontOverrideState.didInstall else { return }
        DexoAppFontOverrideState.didInstall = true

        DexoAppFontOverrideState.didExchangeSystemFont = exchangeClassMethod(
            #selector(UIFont.systemFont(ofSize:)),
            with: #selector(UIFont.dexo_systemFont(ofSize:))
        )
        DexoAppFontOverrideState.didExchangeWeightedSystemFont = exchangeClassMethod(
            Selector(("systemFontOfSize:weight:")),
            with: #selector(UIFont.dexo_systemFont(ofSize:weight:))
        )
        DexoAppFontOverrideState.didExchangeBoldSystemFont = exchangeClassMethod(
            #selector(UIFont.boldSystemFont(ofSize:)),
            with: #selector(UIFont.dexo_boldSystemFont(ofSize:))
        )
        DexoAppFontOverrideState.didExchangeItalicSystemFont = exchangeClassMethod(
            #selector(UIFont.italicSystemFont(ofSize:)),
            with: #selector(UIFont.dexo_italicSystemFont(ofSize:))
        )
        exchangeClassMethod(Selector(("preferredFontForTextStyle:")), with: #selector(UIFont.dexo_preferredFont(forTextStyle:)))
        exchangeClassMethod(
            Selector(("preferredFontForTextStyle:compatibleWithTraitCollection:")),
            with: #selector(UIFont.dexo_preferredFont(forTextStyle:compatibleWith:))
        )
    }

    static func dexoOriginalSystemFont(ofSize pointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        if DexoAppFontOverrideState.didExchangeWeightedSystemFont {
            return UIFont.dexo_systemFont(ofSize: pointSize, weight: weight.rawValue)
        }
        if weight.rawValue >= UIFont.Weight.semibold.rawValue,
           DexoAppFontOverrideState.didExchangeBoldSystemFont {
            return UIFont.dexo_boldSystemFont(ofSize: pointSize)
        }
        if DexoAppFontOverrideState.didExchangeSystemFont {
            return UIFont.dexo_systemFont(ofSize: pointSize)
        }
        return UIFont.systemFont(ofSize: pointSize, weight: weight)
    }

    var dexoDetectedWeight: UIFont.Weight {
        if let traits = fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any],
           let weight = traits[.weight] as? CGFloat {
            return UIFont.Weight(rawValue: weight)
        }
        if fontDescriptor.symbolicTraits.contains(.traitBold) {
            return .semibold
        }
        return .regular
    }

    @discardableResult
    private static func exchangeClassMethod(_ originalSelector: Selector, with swizzledSelector: Selector) -> Bool {
        guard let originalMethod = class_getClassMethod(UIFont.self, originalSelector),
              let swizzledMethod = class_getClassMethod(UIFont.self, swizzledSelector)
        else { return false }
        method_exchangeImplementations(originalMethod, swizzledMethod)
        return true
    }

    @objc class func dexo_systemFont(ofSize pointSize: CGFloat) -> UIFont {
        let original = UIFont.dexo_systemFont(ofSize: pointSize)
        return AppSettings.shared.appInterfaceFont(ofSize: pointSize, weight: .regular, fallback: original)
    }

    @objc(dexo_systemFontOfSize:weight:)
    class func dexo_systemFont(ofSize pointSize: CGFloat, weight rawWeight: CGFloat) -> UIFont {
        let weight = UIFont.Weight(rawValue: rawWeight)
        let original = UIFont.dexo_systemFont(ofSize: pointSize, weight: rawWeight)
        return AppSettings.shared.appInterfaceFont(ofSize: pointSize, weight: weight, fallback: original)
    }

    @objc class func dexo_boldSystemFont(ofSize pointSize: CGFloat) -> UIFont {
        let original = UIFont.dexo_boldSystemFont(ofSize: pointSize)
        return AppSettings.shared.appInterfaceFont(ofSize: pointSize, weight: .bold, fallback: original)
    }

    @objc class func dexo_italicSystemFont(ofSize pointSize: CGFloat) -> UIFont {
        let original = UIFont.dexo_italicSystemFont(ofSize: pointSize)
        let font = AppSettings.shared.appInterfaceFont(ofSize: pointSize, weight: .regular, fallback: original)
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
            .dexoMarkAppFontSourcePointSize(pointSize)
    }

    @objc(dexo_preferredFontForTextStyle:)
    class func dexo_preferredFont(forTextStyle style: String) -> UIFont {
        let original = UIFont.dexo_preferredFont(forTextStyle: style)
        return AppSettings.shared.appInterfaceFont(matching: original)
    }

    @objc(dexo_preferredFontForTextStyle:compatibleWithTraitCollection:)
    class func dexo_preferredFont(forTextStyle style: String, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        let original = UIFont.dexo_preferredFont(forTextStyle: style, compatibleWith: traitCollection)
        return AppSettings.shared.appInterfaceFont(matching: original)
    }

    func applying(weight: UIFont.Weight) -> UIFont {
        guard weight.rawValue >= UIFont.Weight.semibold.rawValue,
              let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitBold))
        else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

final class RuntimeLanguageBundle {
    static let shared = RuntimeLanguageBundle()

    private var didInstallRuntimeBundle = false
    fileprivate var selectedBundle: Bundle?

    func apply(language: AppSettings.AppLanguage) {
        installRuntimeBundleIfNeeded()
        selectedBundle = language.preferredLanguageCodes.lazy.compactMap { code -> Bundle? in
            guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else { return nil }
            return Bundle(path: path)
        }.first
    }

    private func installRuntimeBundleIfNeeded() {
        guard !didInstallRuntimeBundle else { return }
        object_setClass(Bundle.main, RuntimeLocalizedBundle.self)
        didInstallRuntimeBundle = true
    }
}

final class RuntimeLocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = RuntimeLanguageBundle.shared.selectedBundle {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}
