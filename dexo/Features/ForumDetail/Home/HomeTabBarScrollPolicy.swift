import CoreGraphics

/// Pure rules for Home tab-bar auto-hide while scrolling.
enum HomeTabBarScrollPolicy {
    static let topRevealY: CGFloat = 48
    static let hideVelocityY: CGFloat = -40
    static let showVelocityY: CGFloat = 40

    static func shouldForceShow(contentY: CGFloat) -> Bool {
        contentY <= topRevealY
    }

    static func preferredHidden(
        contentY: CGFloat,
        userDriven: Bool,
        velocityY: CGFloat
    ) -> Bool? {
        if shouldForceShow(contentY: contentY) {
            return false
        }
        guard userDriven else { return nil }
        if velocityY < hideVelocityY { return true }
        if velocityY > showVelocityY { return false }
        return nil
    }
}
