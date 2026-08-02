import UIKit

/// Full-screen mini-program shell with WeChat-style capsule (··· / close).
@MainActor
final class MiniProgramHostViewController: UIViewController {
    private var content: UIViewController
    private let program: MiniProgramDescriptor
    private let api: DiscourseAPI
    private let username: String?

    private let chromeView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        return view
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 14
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        return imageView
    }()

    /// WeChat-like capsule: white bar, black ··· | ◎ (ring + solid dot).
    private let capsuleView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .white
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1.0 / UIScreen.main.scale
        view.layer.borderColor = UIColor.black.withAlphaComponent(0.12).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.08
        view.layer.shadowRadius = 6
        view.layer.shadowOffset = CGSize(width: 0, height: 1)
        return view
    }()

    private lazy var moreButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        button.setImage(UIImage(systemName: "ellipsis", withConfiguration: config), for: .normal)
        button.tintColor = .black
        button.accessibilityLabel = String(localized: "mini_program.more", defaultValue: "更多")
        button.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        return button
    }()

    private let capsuleDivider: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        return view
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        // Outer ring + solid inner dot (WeChat mini-program close).
        button.setImage(Self.wechatCloseIcon(size: 18, color: .black), for: .normal)
        button.tintColor = .black
        button.accessibilityLabel = String(localized: "mini_program.close", defaultValue: "关闭")
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }()

    private let contentContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemBackground
        return view
    }()

    init(
        content: UIViewController,
        program: MiniProgramDescriptor,
        api: DiscourseAPI,
        username: String?,
        icon: UIImage? = nil
    ) {
        self.content = content
        self.program = program
        self.api = api
        self.username = username
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        titleLabel.text = program.displayName
        iconView.image = icon
        iconView.isHidden = icon == nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        view.addSubview(chromeView)
        view.addSubview(contentContainer)
        chromeView.addSubview(iconView)
        chromeView.addSubview(titleLabel)
        chromeView.addSubview(capsuleView)
        capsuleView.addSubview(moreButton)
        capsuleView.addSubview(capsuleDivider)
        capsuleView.addSubview(closeButton)

        embedContent(content)

        NSLayoutConstraint.activate([
            chromeView.topAnchor.constraint(equalTo: view.topAnchor),
            chromeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chromeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chromeView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 52),

            capsuleView.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -12),
            capsuleView.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor, constant: -10),
            capsuleView.widthAnchor.constraint(equalToConstant: 87),
            capsuleView.heightAnchor.constraint(equalToConstant: 32),

            moreButton.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor),
            moreButton.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            moreButton.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),
            moreButton.widthAnchor.constraint(equalTo: capsuleView.widthAnchor, multiplier: 0.5),

            capsuleDivider.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            capsuleDivider.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            capsuleDivider.widthAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            capsuleDivider.heightAnchor.constraint(equalToConstant: 18),

            closeButton.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor),
            closeButton.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            closeButton.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),
            closeButton.widthAnchor.constraint(equalTo: capsuleView.widthAnchor, multiplier: 0.5),

            iconView.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor,
                constant: iconView.isHidden ? 0 : 10
            ),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: capsuleView.leadingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),

            contentContainer.topAnchor.constraint(equalTo: chromeView.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if iconView.isHidden {
            titleLabel.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: 16).isActive = true
        }
    }

    // MARK: - Capsule icon

    /// WeChat-style close glyph: thin outer ring with a solid filled center.
    private static func wechatCloseIcon(size: CGFloat, color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { _ in
            let lineWidth: CGFloat = max(1.4, size * 0.09)
            let outerInset = lineWidth / 2
            let outerRect = CGRect(
                x: outerInset,
                y: outerInset,
                width: size - lineWidth,
                height: size - lineWidth
            )
            let outer = UIBezierPath(ovalIn: outerRect)
            color.setStroke()
            outer.lineWidth = lineWidth
            outer.stroke()

            // Solid inner disc — roughly half the outer diameter, matching WeChat.
            let innerDiameter = size * 0.42
            let innerOrigin = (size - innerDiameter) / 2
            let innerRect = CGRect(
                x: innerOrigin,
                y: innerOrigin,
                width: innerDiameter,
                height: innerDiameter
            )
            color.setFill()
            UIBezierPath(ovalIn: innerRect).fill()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        destroyAndDismiss()
    }

    @objc private func moreTapped() {
        presentMoreSheet()
    }

    /// WeChat-style bottom icon panel (not system action sheet / select).
    private func presentMoreSheet() {
        let sheet = MiniProgramMoreSheetViewController(currentProgram: program)
        sheet.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .floatWindow:
                self.floatToBubble()
            case .reenter:
                self.reenterProgram()
            case .copyLink:
                self.copyLink()
            }
        }
        sheet.onSelectRecent = { [weak self] recent in
            guard let self else { return }
            // Switch to another recent mini-program from the more panel.
            MiniProgramFactory.present(
                program: recent,
                from: self,
                api: self.api,
                username: self.username
            )
        }
        present(sheet, animated: false)
    }

    private func floatToBubble() {
        MiniProgramFloatingManager.shared.float(
            host: self,
            program: program,
            api: api,
            username: username
        )
    }

    private func reenterProgram() {
        guard let fresh = MiniProgramFactory.makeContent(
            for: program.id,
            api: api,
            username: username
        ) else {
            presentToast(String(localized: "mini_program.reenter.failed", defaultValue: "无法重新进入"))
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        replaceContent(with: fresh)
        presentToast(String(localized: "mini_program.reenter.done", defaultValue: "已重新进入"))
    }

    private func copyLink() {
        guard let link = MiniProgramFactory.linkURL(for: program) else {
            presentToast(String(localized: "mini_program.copy_link.unavailable", defaultValue: "暂无链接可复制"))
            return
        }
        UIPasteboard.general.string = link.absoluteString
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        presentToast(String(localized: "mini_program.copy_link.done", defaultValue: "链接已复制"))
    }

    // MARK: - Content lifecycle

    private func embedContent(_ child: UIViewController) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            child.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            child.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }

    private func replaceContent(with newContent: UIViewController) {
        content.willMove(toParent: nil)
        content.view.removeFromSuperview()
        content.removeFromParent()
        content = newContent
        embedContent(newContent)
    }

    /// Close = destroy immediately. Floating keeps the instance via MiniProgramFloatingManager.
    func destroyAndDismiss() {
        let teardown = { [weak self] in
            guard let self else { return }
            self.content.willMove(toParent: nil)
            self.content.view.removeFromSuperview()
            self.content.removeFromParent()
        }

        if presentingViewController != nil {
            dismiss(animated: true, completion: teardown)
        } else {
            teardown()
            view.removeFromSuperview()
            removeFromParent()
        }
    }

    private func presentToast(_ message: String) {
        let banner = UIView()
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        banner.layer.cornerRadius = 14
        banner.layer.cornerCurve = .continuous
        banner.clipsToBounds = true

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center

        banner.addSubview(label)
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            banner.heightAnchor.constraint(equalToConstant: 36),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),

            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
        ])
        banner.alpha = 0
        UIView.animate(withDuration: 0.2, animations: {
            banner.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 1.1, options: [], animations: {
                banner.alpha = 0
            }, completion: { _ in
                banner.removeFromSuperview()
            })
        })
    }
}
