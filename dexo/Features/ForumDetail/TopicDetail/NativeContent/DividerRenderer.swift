import UIKit
import CookedHTML

enum DividerRenderer: BlockRenderer {
    static func canRender(_ block: ContentBlock) -> Bool {
        if case .divider = block { return true }
        return false
    }

    static func render(_ block: ContentBlock, config: NativeRenderConfig, delegate: PostCellDelegate?) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let line = UIView()
        line.backgroundColor = UIColor.separator.withAlphaComponent(0.35)
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            container.heightAnchor.constraint(equalToConstant: 24),
        ])

        return container
    }
}
