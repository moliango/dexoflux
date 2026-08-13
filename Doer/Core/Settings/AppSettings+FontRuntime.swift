import UIKit
import ObjectiveC
import CoreText

nonisolated enum DoerAppFontOverrideState {
    nonisolated(unsafe) static var didInstall = false
    nonisolated(unsafe) static var didExchangeSystemFont = false
    nonisolated(unsafe) static var didExchangeWeightedSystemFont = false
    nonisolated(unsafe) static var didExchangeBoldSystemFont = false
    nonisolated(unsafe) static var didExchangeItalicSystemFont = false
}

/// Thread-local guard: UIFont system APIs can re-enter our swizzle while resolving
/// an app font (e.g. weight variant → size variant). Without this, the call chain
/// `systemFont → AppSettings → systemFont` blows the stack (EXC_BAD_ACCESS code=2).
private enum DoerFontResolveGuard {
    nonisolated private static let key = "doer.font.resolve.depth"

    nonisolated static var isResolving: Bool {
        currentDepth > 0
    }

    nonisolated private static var currentDepth: Int {
        get { Thread.current.threadDictionary[key] as? Int ?? 0 }
        set { Thread.current.threadDictionary[key] = newValue }
    }

    nonisolated static func withResolving<T>(_ body: () -> T) -> T {
        currentDepth += 1
        defer { currentDepth -= 1 }
        return body()
    }
}

nonisolated enum DoerAppFontAssociatedKeys {
    nonisolated(unsafe) static var sourcePointSize: UInt8 = 0
    nonisolated(unsafe) static var baseInterfaceFont: UInt8 = 0
}

extension UIView {
    var doerBaseInterfaceFont: UIFont? {
        get {
            objc_getAssociatedObject(self, &DoerAppFontAssociatedKeys.baseInterfaceFont) as? UIFont
        }
        set {
            objc_setAssociatedObject(
                self,
                &DoerAppFontAssociatedKeys.baseInterfaceFont,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

extension UIFont {
    nonisolated var doerAppFontSourcePointSize: CGFloat? {
        (objc_getAssociatedObject(self, &DoerAppFontAssociatedKeys.sourcePointSize) as? NSNumber)
            .map { CGFloat(truncating: $0) }
    }

    nonisolated func doerMarkAppFontSourcePointSize(_ pointSize: CGFloat) -> UIFont {
        objc_setAssociatedObject(
            self,
            &DoerAppFontAssociatedKeys.sourcePointSize,
            pointSize,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return self
    }

    static func installDoerAppFontOverride() {
        guard !DoerAppFontOverrideState.didInstall else { return }
        DoerAppFontOverrideState.didInstall = true

        DoerAppFontOverrideState.didExchangeSystemFont = exchangeClassMethod(
            #selector(UIFont.systemFont(ofSize:)),
            with: #selector(UIFont.doer_systemFont(ofSize:))
        )
        DoerAppFontOverrideState.didExchangeWeightedSystemFont = exchangeClassMethod(
            #selector(UIFont.systemFont(ofSize:weight:)),
            with: #selector(UIFont.doer_systemFont(ofSize:weight:))
        )
        DoerAppFontOverrideState.didExchangeBoldSystemFont = exchangeClassMethod(
            #selector(UIFont.boldSystemFont(ofSize:)),
            with: #selector(UIFont.doer_boldSystemFont(ofSize:))
        )
        DoerAppFontOverrideState.didExchangeItalicSystemFont = exchangeClassMethod(
            #selector(UIFont.italicSystemFont(ofSize:)),
            with: #selector(UIFont.doer_italicSystemFont(ofSize:))
        )
        exchangeClassMethod(
            #selector(UIFont.preferredFont(forTextStyle:)),
            with: #selector(UIFont.doer_preferredFont(forTextStyle:))
        )
        exchangeClassMethod(
            #selector(UIFont.preferredFont(forTextStyle:compatibleWith:)),
            with: #selector(UIFont.doer_preferredFont(forTextStyle:compatibleWith:))
        )
    }

    nonisolated static func doerOriginalSystemFont(ofSize pointSize: CGFloat, weight: UIFont.Weight) -> UIFont {
        // After install, ONLY call through swapped `doer_*` selectors (originals).
        // Calling `UIFont.systemFont` here re-enters our override and recurses.
        if DoerAppFontOverrideState.didExchangeWeightedSystemFont {
            return UIFont.doer_systemFont(ofSize: pointSize, weight: weight.rawValue)
        }
        if weight.rawValue >= UIFont.Weight.semibold.rawValue,
           DoerAppFontOverrideState.didExchangeBoldSystemFont {
            return UIFont.doer_boldSystemFont(ofSize: pointSize)
        }
        if DoerAppFontOverrideState.didExchangeSystemFont {
            return UIFont.doer_systemFont(ofSize: pointSize)
        }
        return UIFont.systemFont(ofSize: pointSize, weight: weight)
    }

    nonisolated private static func shouldApplyAppInterfaceFontOverride() -> Bool {
        DoerAppFontOverrideState.didInstall
            && !DoerFontResolveGuard.isResolving
            && AppSettingsRuntimeCache.hasSeed
    }

    nonisolated var doerDetectedWeight: UIFont.Weight {
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

    @objc nonisolated class func doer_systemFont(ofSize pointSize: CGFloat) -> UIFont {
        // Swapped: this body runs for UIFont.systemFont(ofSize:).
        // `doer_systemFont` selector now points at the real UIKit implementation.
        let original = UIFont.doer_systemFont(ofSize: pointSize)
        guard shouldApplyAppInterfaceFontOverride() else { return original }
        return DoerFontResolveGuard.withResolving {
            AppSettingsRuntimeCache.interfaceFont(ofSize: pointSize, weight: .regular, fallback: original)
        }
    }

    @objc(doer_systemFontOfSize:weight:)
    nonisolated class func doer_systemFont(ofSize pointSize: CGFloat, weight rawWeight: CGFloat) -> UIFont {
        let weight = UIFont.Weight(rawValue: rawWeight)
        let original = UIFont.doer_systemFont(ofSize: pointSize, weight: rawWeight)
        guard shouldApplyAppInterfaceFontOverride() else { return original }
        return DoerFontResolveGuard.withResolving {
            AppSettingsRuntimeCache.interfaceFont(ofSize: pointSize, weight: weight, fallback: original)
        }
    }

    @objc nonisolated class func doer_boldSystemFont(ofSize pointSize: CGFloat) -> UIFont {
        let original = UIFont.doer_boldSystemFont(ofSize: pointSize)
        guard shouldApplyAppInterfaceFontOverride() else { return original }
        return DoerFontResolveGuard.withResolving {
            AppSettingsRuntimeCache.interfaceFont(ofSize: pointSize, weight: .bold, fallback: original)
        }
    }

    @objc class func doer_italicSystemFont(ofSize pointSize: CGFloat) -> UIFont {
        let original = UIFont.doer_italicSystemFont(ofSize: pointSize)
        guard shouldApplyAppInterfaceFontOverride() else { return original }
        return DoerFontResolveGuard.withResolving {
            let font = AppSettingsRuntimeCache.interfaceFont(ofSize: pointSize, weight: .regular, fallback: original)
            guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) else {
                return font
            }
            return UIFont(descriptor: descriptor, size: font.pointSize)
                .doerMarkAppFontSourcePointSize(pointSize)
        }
    }

    @objc(doer_preferredFontForTextStyle:)
    class func doer_preferredFont(forTextStyle style: String) -> UIFont {
        let original = UIFont.doer_preferredFont(forTextStyle: style)
        guard shouldApplyAppInterfaceFontOverride() else { return original }
        return DoerFontResolveGuard.withResolving {
            AppSettingsRuntimeCache.interfaceFont(matching: original)
        }
    }

    @objc(doer_preferredFontForTextStyle:compatibleWithTraitCollection:)
    class func doer_preferredFont(forTextStyle style: String, compatibleWith traitCollection: UITraitCollection?) -> UIFont {
        let original = UIFont.doer_preferredFont(forTextStyle: style, compatibleWith: traitCollection)
        guard shouldApplyAppInterfaceFontOverride() else { return original }
        return DoerFontResolveGuard.withResolving {
            AppSettingsRuntimeCache.interfaceFont(matching: original)
        }
    }

    nonisolated func applying(weight: UIFont.Weight) -> UIFont {
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
