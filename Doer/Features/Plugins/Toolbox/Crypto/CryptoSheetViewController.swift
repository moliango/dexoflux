import UIKit

enum CryptoSheetMode {
    case encrypt
    case decrypt

    var title: String {
        switch self {
        case .encrypt:
            return String(localized: "crypto.encrypt.title", defaultValue: "加密内容")
        case .decrypt:
            return String(localized: "crypto.decrypt.title", defaultValue: "解密内容")
        }
    }

    var actionTitle: String {
        switch self {
        case .encrypt:
            return String(localized: "crypto.encrypt.action", defaultValue: "加密")
        case .decrypt:
            return String(localized: "crypto.decrypt.action", defaultValue: "解密")
        }
    }

    var symbolName: String {
        switch self {
        case .encrypt: return "lock.fill"
        case .decrypt: return "lock.open.fill"
        }
    }

    var inputCaption: String {
        switch self {
        case .encrypt:
            return String(localized: "crypto.plaintext", defaultValue: "明文")
        case .decrypt:
            return String(localized: "crypto.ciphertext", defaultValue: "密文")
        }
    }
}

final class CryptoSheetViewController: UIViewController, UITextViewDelegate {
    var onFinished: ((String) -> Void)?
    var onQuoteReply: ((String) -> Void)?

    private let mode: CryptoSheetMode
    private let initialText: String

    private var algorithmId = CryptoToolbox.defaultAlgorithmId
    private var outputFormat: CryptoOutputFormat = .enc1
    private var autoDetected = false
    private var obscurePassword = true
    private var rememberPassword = AppSettings.shared.cryptoRememberPassword
    private var resultText: String?

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let payloadTextView = UITextView()
    private let passwordField = UITextField()
    private let pemView = UITextView()
    private let caesarField = UITextField()
    private let vigenereField = UITextField()
    private let railField = UITextField()
    private let algorithmNameLabel = UILabel()
    private let algorithmMetaLabel = UILabel()
    private let formatControl = UISegmentedControl(items: [
        String(localized: "crypto.format.enc1.short", defaultValue: "ENC1"),
        String(localized: "crypto.format.openssl.short", defaultValue: "OpenSSL"),
    ])
    private let rememberSwitch = UISwitch()
    private let resultLabel = UILabel()
    private let errorBanner = UILabel()
    private let extraStack = UIStackView()
    private let extrasCard = UIView()
    private let resultCard = UIView()
    private let actionBar = UIView()
    private let quoteButton = CryptoChrome.secondaryButton(
        title: String(localized: "crypto.quote_reply", defaultValue: "引用回复"),
        symbolName: "text.quote"
    )
    private let insertButton = CryptoChrome.secondaryButton(
        title: String(localized: "crypto.insert", defaultValue: "插入编辑器"),
        symbolName: "square.and.pencil"
    )
    private lazy var runButton = CryptoChrome.primaryButton(title: mode.actionTitle, symbolName: mode.symbolName)
    private var lastFittedSheetHeight: CGFloat = 0

    init(mode: CryptoSheetMode, initialText: String = "") {
        self.mode = mode
        self.initialText = initialText
        super.init(nibName: nil, bundle: nil)
        if mode == .decrypt {
            let suggestion = CryptoToolbox.suggestDecrypt(initialText)
            algorithmId = suggestion.algorithmId ?? CryptoToolbox.defaultAlgorithmId
            autoDetected = suggestion.algorithmId != nil
        } else if let recent = AppSettings.shared.cryptoRecentAlgorithms.first,
                  CryptoToolbox.byId(recent) != nil {
            algorithmId = recent
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyChrome()
        title = mode.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeTapped)
        )

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 16, right: 16)
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        let hairline = UIView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.backgroundColor = CryptoChrome.border
        actionBar.addSubview(hairline)
        actionBar.addSubview(runButton)
        view.addSubview(scrollView)
        view.addSubview(actionBar)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionBar.topAnchor),
            actionBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            hairline.topAnchor.constraint(equalTo: actionBar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            runButton.topAnchor.constraint(equalTo: actionBar.topAnchor, constant: 10),
            runButton.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor, constant: 16),
            runButton.trailingAnchor.constraint(equalTo: actionBar.trailingAnchor, constant: -16),
            runButton.bottomAnchor.constraint(equalTo: actionBar.bottomAnchor, constant: -10),
            runButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        CryptoChrome.styleTextView(payloadTextView)
        payloadTextView.text = initialText
        payloadTextView.delegate = self
        payloadTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 128).isActive = true

        CryptoChrome.styleField(passwordField)
        passwordField.isSecureTextEntry = true
        passwordField.placeholder = String(localized: "crypto.password", defaultValue: "密码")
        passwordField.textContentType = .password
        let eye = UIButton(type: .system)
        eye.tintColor = CryptoChrome.accent
        eye.setImage(UIImage(systemName: "eye"), for: .normal)
        eye.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        eye.addAction(UIAction { [weak self, weak eye] _ in
            guard let self else { return }
            self.obscurePassword.toggle()
            self.passwordField.isSecureTextEntry = self.obscurePassword
            eye?.setImage(UIImage(systemName: self.obscurePassword ? "eye" : "eye.slash"), for: .normal)
        }, for: .touchUpInside)
        passwordField.rightView = eye
        passwordField.rightViewMode = .always
        if rememberPassword, let last = CryptoKeyStore.readPasswords().first {
            passwordField.text = last
        }

        CryptoChrome.styleTextView(pemView)
        pemView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        pemView.heightAnchor.constraint(equalToConstant: 96).isActive = true

        [caesarField, vigenereField, railField].forEach(CryptoChrome.styleField)
        caesarField.keyboardType = .numberPad
        caesarField.text = "3"
        caesarField.placeholder = String(localized: "crypto.caesar.shift", defaultValue: "移位")
        vigenereField.placeholder = String(localized: "crypto.vigenere.key", defaultValue: "维吉尼亚密钥")
        vigenereField.autocapitalizationType = .allCharacters
        railField.keyboardType = .numberPad
        railField.text = "2"
        railField.placeholder = String(localized: "crypto.rail.count", defaultValue: "栅栏数")

        formatControl.selectedSelectedSegmentTintColorIfAvailable()
        formatControl.selectedSegmentIndex = 0
        formatControl.addTarget(self, action: #selector(formatChanged), for: .valueChanged)

        rememberSwitch.onTintColor = CryptoChrome.accent
        rememberSwitch.isOn = rememberPassword
        rememberSwitch.addTarget(self, action: #selector(rememberChanged), for: .valueChanged)

        extraStack.axis = .vertical
        extraStack.spacing = 12

        resultLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        resultLabel.numberOfLines = 0
        resultLabel.textColor = .label
        errorBanner.font = .systemFont(ofSize: 13, weight: .medium)
        errorBanner.textColor = .systemRed
        errorBanner.numberOfLines = 0
        errorBanner.isHidden = true

        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)
        quoteButton.addTarget(self, action: #selector(quoteTapped), for: .touchUpInside)
        insertButton.addTarget(self, action: #selector(insertTapped), for: .touchUpInside)
        quoteButton.isHidden = onQuoteReply == nil || mode == .encrypt
        insertButton.isHidden = onFinished == nil || mode == .decrypt

        stack.addArrangedSubview(makeHero())
        stack.addArrangedSubview(makeLabeledCard(caption: mode.inputCaption, body: payloadTextView))
        stack.addArrangedSubview(makeAlgorithmCard())
        CryptoChrome.applyCard(extrasCard)
        let extrasInner = padded(extraStack)
        extrasCard.addSubview(extrasInner)
        pin(extrasInner, to: extrasCard)
        stack.addArrangedSubview(extrasCard)
        stack.addArrangedSubview(errorBanner)
        stack.addArrangedSubview(makeResultCard())
        resultCard.isHidden = true

        rebuildExtras()
        refreshAlgorithmTitle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyChrome()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyChrome()
    }

    static func present(
        mode: CryptoSheetMode,
        text: String,
        from host: UIViewController,
        onFinished: ((String) -> Void)? = nil,
        onQuoteReply: ((String) -> Void)? = nil
    ) {
        let sheet = CryptoSheetViewController(mode: mode, initialText: text)
        sheet.onFinished = onFinished
        sheet.onQuoteReply = onQuoteReply
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .pageSheet
        nav.navigationBar.tintColor = CryptoChrome.accent
        if let page = nav.sheetPresentationController {
            if #available(iOS 16.0, *) {
                let form = UISheetPresentationController.Detent.custom(
                    identifier: .init("crypto.form")
                ) { [weak sheet] context in
                    let fitted = sheet?.preferredSheetHeight ?? 620
                    return min(max(fitted, 560), context.maximumDetentValue * 0.92)
                }
                page.detents = [form, .large()]
                page.selectedDetentIdentifier = form.identifier
            } else {
                page.detents = [.large()]
            }
            page.prefersGrabberVisible = true
        }
        host.present(nav, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let fitted = preferredSheetHeight
        guard abs(fitted - lastFittedSheetHeight) > 8 else { return }
        lastFittedSheetHeight = fitted
        if #available(iOS 16.0, *) {
            navigationController?.sheetPresentationController?.invalidateDetents()
        }
    }

    private var preferredSheetHeight: CGFloat {
        let width = view.bounds.width > 0 ? view.bounds.width : UIScreen.main.bounds.width
        let fitting = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        let content = stack.systemLayoutSizeFitting(
            fitting,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let footer = actionBar.systemLayoutSizeFitting(
            fitting,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let navigationChrome: CGFloat = 56
        let grabber: CGFloat = 20
        let safeBottom = view.safeAreaInsets.bottom > 0 ? view.safeAreaInsets.bottom : 34
        return content + footer + navigationChrome + grabber + safeBottom
    }

    private func applyChrome() {
        view.backgroundColor = CryptoChrome.screen
        actionBar.backgroundColor = CryptoChrome.screen
        view.tintColor = CryptoChrome.accent
        navigationController?.navigationBar.tintColor = CryptoChrome.accent
    }

    private func makeHero() -> UIView {
        let badge = CryptoChrome.iconBadge(symbolName: mode.symbolName, size: 52)
        let title = UILabel()
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.text = mode.title
        let subtitle = UILabel()
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        subtitle.text = mode == .encrypt
            ? String(localized: "crypto.encrypt.hero", defaultValue: "选择算法后加密，可复制或插回编辑器。")
            : String(localized: "crypto.decrypt.hero", defaultValue: "自动识别密文算法，解出来可复制或引用回复。")
        let textStack = UIStackView(arrangedSubviews: [title, subtitle])
        textStack.axis = .vertical
        textStack.spacing = 4
        let row = UIStackView(arrangedSubviews: [badge, textStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 14
        return row
    }

    private func makeLabeledCard(caption: String, body: UIView) -> UIView {
        let card = UIView()
        CryptoChrome.applyCard(card)
        let inner = UIStackView(arrangedSubviews: [CryptoChrome.sectionLabel(caption), body])
        inner.axis = .vertical
        inner.spacing = 8
        let paddedStack = padded(inner)
        card.addSubview(paddedStack)
        pin(paddedStack, to: card)
        return card
    }

    private func makeAlgorithmCard() -> UIView {
        let card = UIView()
        CryptoChrome.applyCard(card)
        algorithmNameLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        algorithmMetaLabel.font = .systemFont(ofSize: 12, weight: .medium)
        algorithmMetaLabel.textColor = CryptoChrome.accent
        let text = UIStackView(arrangedSubviews: [algorithmNameLabel, algorithmMetaLabel])
        text.axis = .vertical
        text.spacing = 2
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = .tertiaryLabel
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        let icon = CryptoChrome.iconBadge(symbolName: "key.fill", size: 36)
        let row = UIStackView(arrangedSubviews: [icon, text, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        let inner = UIStackView(arrangedSubviews: [CryptoChrome.sectionLabel(String(localized: "crypto.algorithm", defaultValue: "算法")), row])
        inner.axis = .vertical
        inner.spacing = 10
        let paddedStack = padded(inner)
        card.addSubview(paddedStack)
        pin(paddedStack, to: card)
        let tap = UITapGestureRecognizer(target: self, action: #selector(pickAlgorithm))
        card.addGestureRecognizer(tap)
        card.isUserInteractionEnabled = true
        return card
    }

    private func makeResultCard() -> UIView {
        CryptoChrome.applyCard(resultCard)
        let copy = CryptoChrome.secondaryButton(
            title: String(localized: "crypto.copy", defaultValue: "复制"),
            symbolName: "doc.on.doc"
        )
        copy.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [copy, quoteButton, insertButton])
        actions.axis = .horizontal
        actions.spacing = 8
        actions.distribution = .fillEqually
        let inner = UIStackView(arrangedSubviews: [
            CryptoChrome.sectionLabel(String(localized: "crypto.result", defaultValue: "结果")),
            resultLabel,
            actions,
        ])
        inner.axis = .vertical
        inner.spacing = 10
        let paddedStack = padded(inner)
        resultCard.addSubview(paddedStack)
        pin(paddedStack, to: resultCard)
        return resultCard
    }

    private func padded(_ view: UIView) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 14),
            view.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 14),
            view.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -14),
            view.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -14),
        ])
        return wrap
    }

    private func pin(_ child: UIView, to parent: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    private var currentAlgorithm: (any CryptoAlgorithm)? { CryptoToolbox.byId(algorithmId) }

    private func rebuildExtras() {
        extraStack.arrangedSubviews.forEach {
            extraStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        guard let algo = currentAlgorithm else {
            extrasCard.isHidden = true
            return
        }
        if algo.requiresPassword {
            extraStack.addArrangedSubview(fieldRow(
                caption: String(localized: "crypto.password", defaultValue: "密码"),
                field: passwordField
            ))
            let remembered = CryptoKeyStore.readPasswords()
            if !remembered.isEmpty {
                let chips = UIStackView()
                chips.axis = .horizontal
                chips.spacing = 8
                chips.alignment = .center
                remembered.prefix(3).forEach { password in
                    var config = UIButton.Configuration.tinted()
                    config.cornerStyle = .capsule
                    config.baseForegroundColor = CryptoChrome.accent
                    config.baseBackgroundColor = CryptoChrome.accent
                    config.title = password.count > 10 ? "\(password.prefix(8))…" : password
                    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                        var next = incoming
                        next.font = .systemFont(ofSize: 12, weight: .medium)
                        return next
                    }
                    let button = UIButton(configuration: config)
                    button.addAction(UIAction { [weak self] _ in
                        self?.passwordField.text = password
                    }, for: .touchUpInside)
                    chips.addArrangedSubview(button)
                }
                extraStack.addArrangedSubview(chips)
            }
            let rememberLabel = UILabel()
            rememberLabel.text = String(localized: "crypto.remember_password", defaultValue: "记住密码")
            rememberLabel.font = .systemFont(ofSize: 15, weight: .medium)
            let rememberRow = UIStackView(arrangedSubviews: [rememberLabel, rememberSwitch])
            rememberRow.axis = .horizontal
            extraStack.addArrangedSubview(rememberRow)
        }
        if algo.requiresPem {
            extraStack.addArrangedSubview(CryptoChrome.sectionLabel(String(localized: "crypto.pem", defaultValue: "PEM 密钥")))
            extraStack.addArrangedSubview(pemView)
        }
        if algo.id == "caesar" {
            extraStack.addArrangedSubview(fieldRow(
                caption: String(localized: "crypto.caesar.shift", defaultValue: "移位"),
                field: caesarField
            ))
        }
        if algo.id == "vigenere" {
            extraStack.addArrangedSubview(fieldRow(
                caption: String(localized: "crypto.vigenere.key", defaultValue: "维吉尼亚密钥"),
                field: vigenereField
            ))
        }
        if algo.id == "railfence" {
            extraStack.addArrangedSubview(fieldRow(
                caption: String(localized: "crypto.rail.count", defaultValue: "栅栏数"),
                field: railField
            ))
        }
        if mode == .encrypt, let sym = algo as? SymmetricCryptoAlgorithm, sym.openSslCompatible {
            extraStack.addArrangedSubview(CryptoChrome.sectionLabel(String(localized: "crypto.format", defaultValue: "输出格式")))
            extraStack.addArrangedSubview(formatControl)
        }
        extrasCard.isHidden = extraStack.arrangedSubviews.isEmpty
    }

    private func fieldRow(caption: String, field: UITextField) -> UIView {
        let label = CryptoChrome.sectionLabel(caption)
        let stack = UIStackView(arrangedSubviews: [label, field])
        stack.axis = .vertical
        stack.spacing = 4
        return stack
    }

    private func refreshAlgorithmTitle() {
        algorithmNameLabel.text = currentAlgorithm?.displayName ?? algorithmId
        algorithmMetaLabel.text = autoDetected
            ? String(localized: "crypto.auto_detected", defaultValue: "已自动识别")
            : (currentAlgorithm?.id ?? "")
        algorithmMetaLabel.textColor = autoDetected ? CryptoChrome.accent : .tertiaryLabel
    }

    private func params() -> CryptoParams {
        CryptoParams(
            password: passwordField.text,
            rsaPem: pemView.text,
            caesarShift: Int(caesarField.text ?? "") ?? 3,
            vigenereKey: vigenereField.text,
            railCount: Int(railField.text ?? "") ?? 2
        )
    }

    @objc private func pickAlgorithm() {
        let picker = CryptoAlgorithmPickerViewController(currentAlgorithmId: algorithmId)
        picker.onSelect = { [weak self] id in
            self?.algorithmId = id
            self?.autoDetected = false
            self?.rebuildExtras()
            self?.refreshAlgorithmTitle()
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        nav.navigationBar.tintColor = CryptoChrome.accent
        if let page = nav.sheetPresentationController {
            page.detents = [.medium(), .large()]
            page.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    @objc private func formatChanged() {
        outputFormat = formatControl.selectedSegmentIndex == 1 ? .openssl : .enc1
    }

    @objc private func rememberChanged() {
        rememberPassword = rememberSwitch.isOn
    }

    @objc private func runTapped() {
        errorBanner.isHidden = true
        errorBanner.text = nil
        let text = payloadTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorBanner.text = String(localized: "crypto.error.empty", defaultValue: "请输入内容")
            errorBanner.isHidden = false
            return
        }
        do {
            let output: String
            if mode == .encrypt {
                output = try CryptoToolbox.encrypt(
                    plaintext: text,
                    algorithmId: algorithmId,
                    params: params(),
                    format: outputFormat
                )
            } else {
                output = try CryptoToolbox.decrypt(
                    ciphertext: text,
                    algorithmId: algorithmId,
                    params: params()
                )
            }
            resultText = output
            resultLabel.text = output
            resultCard.isHidden = false
            expandSheetForResult()
            if rememberPassword, currentAlgorithm?.requiresPassword == true, let password = passwordField.text {
                CryptoKeyStore.rememberPassword(password)
            }
        } catch {
            resultCard.isHidden = true
            errorBanner.text = error.localizedDescription
            errorBanner.isHidden = false
        }
    }

    @objc private func copyTapped() {
        guard let resultText, !resultText.isEmpty else { return }
        UIPasteboard.general.string = resultText
        DoerFeedback.presentToast(String(localized: "crypto.copied", defaultValue: "已复制"), on: self)
    }

    @objc private func quoteTapped() {
        guard let resultText else { return }
        let callback = onQuoteReply
        dismiss(animated: true) { callback?(resultText) }
    }

    @objc private func insertTapped() {
        guard let resultText else { return }
        let callback = onFinished
        dismiss(animated: true) { callback?(resultText) }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    private func expandSheetForResult() {
        guard let page = navigationController?.sheetPresentationController else { return }
        if #available(iOS 16.0, *) {
            page.animateChanges {
                page.selectedDetentIdentifier = .large
            }
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        guard mode == .decrypt, textView === payloadTextView else { return }
        let suggestion = CryptoToolbox.suggestDecrypt(textView.text)
        if let id = suggestion.algorithmId {
            algorithmId = id
            autoDetected = true
            rebuildExtras()
            refreshAlgorithmTitle()
        }
    }
}

private extension UISegmentedControl {
    func selectedSelectedSegmentTintColorIfAvailable() {
        selectedSegmentTintColor = CryptoChrome.accent.withAlphaComponent(0.22)
        setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
        setTitleTextAttributes([.foregroundColor: CryptoChrome.accent, .font: UIFont.systemFont(ofSize: 13, weight: .semibold)], for: .selected)
    }
}
