import UIKit

/// Built-in「工具箱」mini-program: FluxDo-style crypto encrypt / decrypt workspace.
@MainActor
final class ToolboxMiniProgramViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "toolbox.title", defaultValue: "加解密工具箱")
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(
            localized: "crypto.settings",
            defaultValue: "加解密设置"
        )

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 18, bottom: 28, right: 18)

        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        stack.addArrangedSubview(makeHero())
        stack.addArrangedSubview(makeIntro())
        stack.addArrangedSubview(makeActionCard(
            title: String(localized: "crypto.encrypt.title", defaultValue: "加密内容"),
            subtitle: String(localized: "crypto.toolbox.encrypt.subtitle", defaultValue: "明文 → 密文，可复制或插入编辑器"),
            symbol: "lock.fill",
            action: #selector(openEncrypt)
        ))
        stack.addArrangedSubview(makeActionCard(
            title: String(localized: "crypto.decrypt.title", defaultValue: "解密内容"),
            subtitle: String(localized: "crypto.toolbox.decrypt.subtitle", defaultValue: "自动识别算法，解出来可复制"),
            symbol: "lock.open.fill",
            action: #selector(openDecrypt)
        ))
        applyChrome()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyChrome()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyChrome()
    }

    private func applyChrome() {
        view.backgroundColor = CryptoChrome.screen
        view.tintColor = CryptoChrome.accent
        navigationController?.navigationBar.tintColor = CryptoChrome.accent
    }

    private func makeHero() -> UIView {
        let badge = CryptoChrome.iconBadge(symbolName: "key.fill", size: 56)
        let title = UILabel()
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.text = String(localized: "toolbox.title", defaultValue: "加解密工具箱")
        let subtitle = UILabel()
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        subtitle.text = String(
            localized: "crypto.toolbox.hero",
            defaultValue: "帖子划词解密，编辑器一键加密，与 openssl 密文互通。"
        )
        let text = UIStackView(arrangedSubviews: [title, subtitle])
        text.axis = .vertical
        text.spacing = 6
        let row = UIStackView(arrangedSubviews: [badge, text])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        return row
    }

    private func makeIntro() -> UIView {
        let card = UIView()
        CryptoChrome.applyCard(card)
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.text = String(
            localized: "crypto.toolbox.intro",
            defaultValue: "选中帖子里的疑似密文会出现「解密」。编辑器里点钥匙或「+」菜单即可加密插回。算法覆盖 AES、3DES、ChaCha20、Base64/Hex/ROT13、哈希、RSA 与经典密码。"
        )
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])
        return card
    }

    private func makeActionCard(title: String, subtitle: String, symbol: String, action: Selector) -> UIControl {
        let card = UIControl()
        CryptoChrome.applyCard(card)
        card.addTarget(self, action: action, for: .touchUpInside)
        let badge = CryptoChrome.iconBadge(symbolName: symbol, size: 44)
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.text = title
        let subtitleLabel = UILabel()
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.text = subtitle
        let text = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        text.axis = .vertical
        text.spacing = 3
        text.isUserInteractionEnabled = false
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.isUserInteractionEnabled = false
        let row = UIStackView(arrangedSubviews: [badge, text, chevron])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isUserInteractionEnabled = false
        card.addSubview(row)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 84),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    @objc private func openEncrypt() {
        CryptoSheetViewController.present(mode: .encrypt, text: "", from: self)
    }

    @objc private func openDecrypt() {
        let paste = UIPasteboard.general.string ?? ""
        CryptoSheetViewController.present(mode: .decrypt, text: paste, from: self)
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(CryptoSettingsViewController(), animated: true)
    }
}

final class CryptoSettingsViewController: UIViewController {
    private let rememberRow = ReadingToggleRowView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "crypto.settings.group", defaultValue: "加解密")

        rememberRow.onValueChanged = { isOn in
            AppSettings.shared.cryptoRememberPassword = isOn
        }

        let clear = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .large
        config.baseBackgroundColor = CryptoChrome.card
        config.baseForegroundColor = .systemRed
        config.image = UIImage(systemName: "trash")
        config.imagePadding = 8
        config.title = String(localized: "crypto.settings.clear", defaultValue: "清除已记住的密码")
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var next = incoming
            next.font = .systemFont(ofSize: 16, weight: .semibold)
            return next
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        clear.configuration = config
        clear.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clear.layer.cornerRadius = 18
        clear.layer.cornerCurve = .continuous
        clear.layer.borderWidth = 1
        clear.layer.borderColor = CryptoChrome.border.cgColor
        clear.clipsToBounds = true

        let stack = UIStackView(arrangedSubviews: [rememberRow, clear])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
        ])
        applyChrome()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyChrome()
        rememberRow.configure(
            title: String(localized: "crypto.settings.remember", defaultValue: "记住加密密码"),
            subtitle: String(
                localized: "crypto.settings.remember.desc",
                defaultValue: "密码保存在系统钥匙串，仅本机可用。"
            ),
            symbolName: "key.fill",
            isOn: AppSettings.shared.cryptoRememberPassword,
            accentColor: CryptoChrome.accent,
            backgroundColor: CryptoChrome.card
        )
    }

    private func applyChrome() {
        view.backgroundColor = CryptoChrome.screen
        view.tintColor = CryptoChrome.accent
        navigationController?.navigationBar.tintColor = CryptoChrome.accent
    }

    @objc private func clearTapped() {
        CryptoKeyStore.clear()
        DoerFeedback.presentToast(
            String(localized: "crypto.settings.clear.done", defaultValue: "已清除记住的密码"),
            on: self
        )
    }
}
