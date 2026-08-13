import UIKit

protocol CapsuleBarViewDelegate: AnyObject {
    func capsuleBarDidTapMenu()
    func capsuleBarDidTapDismiss()
}

final class CapsuleBarView: UIView {
    weak var delegate: CapsuleBarViewDelegate?

    private let menuButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let divider: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let dismissButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .label
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.borderWidth = 0.5
        layer.borderColor = UIColor.separator.cgColor

        addSubview(menuButton)
        addSubview(divider)
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            menuButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            menuButton.topAnchor.constraint(equalTo: topAnchor),
            menuButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            menuButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),

            divider.centerXAnchor.constraint(equalTo: centerXAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            divider.widthAnchor.constraint(equalToConstant: 0.5),

            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            dismissButton.topAnchor.constraint(equalTo: topAnchor),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissButton.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
        ])

        menuButton.addTarget(self, action: #selector(menuTapped), for: .touchUpInside)
        dismissButton.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    @objc private func menuTapped() {
        delegate?.capsuleBarDidTapMenu()
    }

    @objc private func dismissTapped() {
        delegate?.capsuleBarDidTapDismiss()
    }
}
