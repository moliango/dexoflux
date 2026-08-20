import CookedHTML
import Photos
import UIKit

final class ShareImagePreviewViewController: UIViewController {
    struct Model {
        let topicId: Int
        let baseURL: String
        let title: String
        let brandName: String
        let authorName: String
        let username: String
        let createdAtText: String?
        let avatarURL: URL?
        /// Discourse cooked HTML only — never markdown `raw`.
        let cookedHTML: String
        /// On-screen parsed blocks from topic detail (preferred over re-parsing HTML).
        let contentBlocks: [ContentBlock]
        let shareURL: String
        let postNumber: Int

        init(
            topicId: Int,
            baseURL: String,
            title: String,
            brandName: String,
            authorName: String,
            username: String,
            createdAtText: String?,
            avatarURL: URL?,
            cookedHTML: String,
            contentBlocks: [ContentBlock] = [],
            shareURL: String,
            postNumber: Int
        ) {
            self.topicId = topicId
            self.baseURL = baseURL
            self.title = title
            self.brandName = brandName
            self.authorName = authorName
            self.username = username
            self.createdAtText = createdAtText
            self.avatarURL = avatarURL
            self.cookedHTML = cookedHTML
            self.contentBlocks = contentBlocks
            self.shareURL = shareURL
            self.postNumber = postNumber
        }
    }

    private let model: Model
    private var theme: ShareImageTheme = ShareImagePreferences.theme

    private let grabber: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .tertiaryLabel.withAlphaComponent(0.35)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String(localized: "share.image.title", defaultValue: "分享图片")
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.textAlignment = .center
        return label
    }()

    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = .label
        return button
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let cardHost: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 16
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        return v
    }()

    private let cardView = ShareImageCardView()

    private lazy var themeStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.distribution = .equalSpacing
        return stack
    }()

    private let saveButton: UIButton = {
        var config = UIButton.Configuration.bordered()
        config.title = String(localized: "share.image.save", defaultValue: "保存到相册")
        config.image = UIImage(systemName: "square.and.arrow.down")
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let shareButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "share.image.share", defaultValue: "分享")
        config.image = UIImage(systemName: "square.and.arrow.up")
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var actionStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [saveButton, shareButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        return stack
    }()

    private var themeButtons: [UIButton] = []
    private var isBodyReady = false
    private var bodyReadyTimeoutWork: DispatchWorkItem?
    private let bodyReadyTimeout: TimeInterval = 2.5

    init(model: Model) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = false
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupUI()
        rebuildThemeChips()
        cardView.onBodyImagesReady = { [weak self] in
            self?.markBodyReady()
        }
        setActionsEnabled(false)
        applyTheme()
    }

    private func setupUI() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)

        view.addSubview(grabber)
        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(scrollView)
        scrollView.addSubview(cardHost)
        cardHost.addSubview(cardView)
        view.addSubview(themeStack)
        view.addSubview(actionStack)

        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 42),
            grabber.heightAnchor.constraint(equalToConstant: 5),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: themeStack.topAnchor, constant: -12),

            cardHost.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            cardHost.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            cardHost.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            cardHost.widthAnchor.constraint(equalToConstant: 375),

            cardView.topAnchor.constraint(equalTo: cardHost.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),

            themeStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            themeStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            themeStack.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: -16),
            themeStack.heightAnchor.constraint(equalToConstant: 54),

            actionStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            actionStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            actionStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            actionStack.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func rebuildThemeChips() {
        themeStack.arrangedSubviews.forEach {
            themeStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        themeButtons = ShareImageTheme.allCases.map { item in
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = item.rawValue
            button.backgroundColor = item.backgroundColor
            button.layer.cornerRadius = 16
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.clear.cgColor
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            button.accessibilityLabel = item.title
            button.addTarget(self, action: #selector(themeTapped(_:)), for: .touchUpInside)

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = item.title
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textAlignment = .center
            label.textColor = .secondaryLabel

            let wrap = UIStackView(arrangedSubviews: [button, label])
            wrap.axis = .vertical
            wrap.alignment = .center
            wrap.spacing = 4
            themeStack.addArrangedSubview(wrap)
            return button
        }
        updateThemeSelection()
    }

    private func updateThemeSelection() {
        for button in themeButtons {
            let selected = button.tag == theme.rawValue
            button.layer.borderColor = (selected ? UIColor.systemBlue : UIColor.clear).cgColor
            if selected {
                button.setImage(UIImage(systemName: "checkmark"), for: .normal)
                button.tintColor = theme.isDark ? .white : .black
            } else {
                button.setImage(nil, for: .normal)
            }
        }
    }

    private func applyTheme() {
        isBodyReady = false
        setActionsEnabled(false)
        scheduleBodyReadyTimeout()
        cardView.configure(
            theme: theme,
            brandName: model.brandName,
            title: model.title,
            baseURL: model.baseURL,
            authorName: model.authorName,
            username: model.username,
            createdAt: model.createdAtText,
            avatarURL: model.avatarURL,
            cookedHTML: model.cookedHTML,
            contentBlocks: model.contentBlocks,
            shareURL: model.shareURL
        )
        cardHost.backgroundColor = theme.backgroundColor
        updateThemeSelection()
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func scheduleBodyReadyTimeout() {
        bodyReadyTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.markBodyReady()
        }
        bodyReadyTimeoutWork = work
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(bodyReadyTimeout * 1_000_000_000))
            work.perform()
        }
    }

    private func markBodyReady() {
        guard !isBodyReady else { return }
        isBodyReady = true
        bodyReadyTimeoutWork?.cancel()
        bodyReadyTimeoutWork = nil
        setActionsEnabled(true)
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func setActionsEnabled(_ enabled: Bool) {
        saveButton.isEnabled = enabled
        shareButton.isEnabled = enabled
        saveButton.alpha = enabled ? 1 : 0.45
        shareButton.alpha = enabled ? 1 : 0.45
    }

    @objc private func themeTapped(_ sender: UIButton) {
        guard let selected = ShareImageTheme(rawValue: sender.tag) else { return }
        theme = selected
        ShareImagePreferences.theme = selected
        applyTheme()
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        guard isBodyReady, let image = renderCardImage() else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized || status == .limited else {
                    self.presentSimpleAlert(
                        title: String(localized: "share.image.permission_denied", defaultValue: "无法保存"),
                        message: String(localized: "share.image.permission_message", defaultValue: "请在设置中允许写入相册。")
                    )
                    return
                }
                UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
            }
        }
    }

    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer?) {
        if let error {
            presentSimpleAlert(title: String(localized: "common.error", defaultValue: "错误"), message: error.localizedDescription)
        } else {
            presentSimpleAlert(
                title: String(localized: "share.image.saved", defaultValue: "已保存"),
                message: String(localized: "share.image.saved_message", defaultValue: "图片已保存到相册。")
            )
        }
    }

    @objc private func shareTapped() {
        guard isBodyReady, let image = renderCardImage() else { return }
        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = shareButton
        present(activity, animated: true)
    }

    private func renderCardImage() -> UIImage? {
        view.layoutIfNeeded()
        let size = cardView.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            cardView.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }

    private func presentSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok", defaultValue: "好"), style: .default))
        present(alert, animated: true)
    }
}
