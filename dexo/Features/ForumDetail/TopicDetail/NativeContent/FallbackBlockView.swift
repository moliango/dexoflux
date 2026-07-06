import UIKit

/// A placeholder view that asynchronously renders an HTML block via WebView snapshot.
/// Used for content blocks that have no native renderer (e.g. table, onebox, details).
final class FallbackBlockView: UIView {
    private let snapshotImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleToFill
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let placeholderView: UIView = {
        let v = UIView()
        v.backgroundColor = .tertiarySystemGroupedBackground
        v.layer.cornerRadius = 10
        v.layer.cornerCurve = .continuous
        v.layer.borderWidth = 1.0 / UIScreen.main.scale
        v.layer.borderColor = UIColor.separator.withAlphaComponent(0.25).cgColor
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var heightConstraint: NSLayoutConstraint!
    private var renderTask: Task<Void, Never>?
    private var placeholderBlocks: [SkeletonBlockView] = []

    init(html: String, containerWidth: CGFloat, baseURL: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(placeholderView)
        addSubview(snapshotImageView)
        setupPlaceholderSkeleton()

        heightConstraint = heightAnchor.constraint(equalToConstant: 80)
        heightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            placeholderView.topAnchor.constraint(equalTo: topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: bottomAnchor),

            snapshotImageView.topAnchor.constraint(equalTo: topAnchor),
            snapshotImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            snapshotImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            snapshotImageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            heightConstraint,
        ])

        renderTask = Task { @MainActor [weak self] in
            let rendered = await PostContentRenderer.shared.renderHTMLBlock(
                html: html,
                baseURL: baseURL,
                width: containerWidth
            )
            guard let self, !Task.isCancelled else { return }
            self.snapshotImageView.image = rendered.snapshot
            self.heightConstraint.constant = rendered.height
            self.placeholderBlocks.forEach { $0.stopAnimating() }
            self.placeholderView.isHidden = true

            // Walk up to find the owning UITableView and trigger a height update
            var view: UIView? = self.superview
            while let v = view {
                if let tableView = v as? UITableView {
                    tableView.beginUpdates()
                    tableView.endUpdates()
                    break
                }
                view = v.superview
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func cancelRender() {
        renderTask?.cancel()
        renderTask = nil
        placeholderBlocks.forEach { $0.stopAnimating() }
    }

    private func setupPlaceholderSkeleton() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.addSubview(stack)

        let line1 = SkeletonBlockView(cornerRadius: 5)
        let line2 = SkeletonBlockView(cornerRadius: 5)
        let line3 = SkeletonBlockView(cornerRadius: 5)
        placeholderBlocks = [line1, line2, line3]

        stack.addArrangedSubview(line1)
        stack.addArrangedSubview(line2)
        stack.addArrangedSubview(line3)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: placeholderView.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: placeholderView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: placeholderView.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: placeholderView.bottomAnchor, constant: -14),

            line1.heightAnchor.constraint(equalToConstant: 14),
            line2.heightAnchor.constraint(equalToConstant: 14),
            line3.widthAnchor.constraint(equalTo: stack.widthAnchor, multiplier: 0.58),
            line3.heightAnchor.constraint(equalToConstant: 14),
        ])

        placeholderBlocks.forEach { $0.startAnimating() }
    }
}
