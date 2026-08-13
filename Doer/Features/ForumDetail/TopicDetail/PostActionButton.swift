import UIKit

final class PostActionButton: UIButton {
    static let iconSize = CGSize(width: 22, height: 22)

    private(set) lazy var fixedIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(fixedIconView)
        NSLayoutConstraint.activate([
            fixedIconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            fixedIconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            fixedIconView.widthAnchor.constraint(equalToConstant: Self.iconSize.width),
            fixedIconView.heightAnchor.constraint(equalToConstant: Self.iconSize.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setFixedIcon(_ image: UIImage?, tintColor: UIColor) {
        fixedIconView.image = image?.withRenderingMode(.alwaysTemplate)
        fixedIconView.tintColor = tintColor
    }
}
