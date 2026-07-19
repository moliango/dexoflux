import UIKit

@MainActor
final class AppUpdateViewController: UIViewController {
    private let currentVersion: AppVersion
    private let release: AppRelease

    init(currentVersion: AppVersion, release: AppRelease) {
        self.currentVersion = currentVersion
        self.release = release
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "update.available.title", defaultValue: "发现新版本")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 28, right: 18)

        let hero = makeHeroCard()
        let notes = makeReleaseNotesCard()
        let updateButton = makeUpdateButton()
        let laterButton = UIButton(type: .system)
        laterButton.setTitle(String(localized: "update.later", defaultValue: "稍后"), for: .normal)
        laterButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        laterButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        laterButton.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        let actionPanel = UIView()
        actionPanel.translatesAutoresizingMaskIntoConstraints = false
        actionPanel.backgroundColor = .secondarySystemGroupedBackground
        actionPanel.layer.borderWidth = 1.0 / UIScreen.main.scale
        actionPanel.layer.borderColor = UIColor.separator.withAlphaComponent(0.22).cgColor

        let actionStack = UIStackView(arrangedSubviews: [updateButton, laterButton])
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .vertical
        actionStack.spacing = 4
        actionPanel.addSubview(actionStack)

        view.addSubview(scrollView)
        view.addSubview(actionPanel)
        scrollView.addSubview(stack)
        stack.addArrangedSubview(hero)
        stack.addArrangedSubview(notes)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionPanel.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            actionPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            actionPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            actionPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            actionStack.topAnchor.constraint(equalTo: actionPanel.topAnchor, constant: 12),
            actionStack.leadingAnchor.constraint(equalTo: actionPanel.leadingAnchor, constant: 18),
            actionStack.trailingAnchor.constraint(equalTo: actionPanel.trailingAnchor, constant: -18),
            actionStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
    }

    private func makeHeroCard() -> UIView {
        let card = UIView()
        card.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        card.layer.cornerRadius = 26
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1.0 / UIScreen.main.scale
        card.layer.borderColor = UIColor.separator.withAlphaComponent(0.22).cgColor

        let icon = UIImageView(image: UIImage(systemName: "arrow.down.app.fill"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = AppSettings.shared.themeStyle.accentColor
        icon.contentMode = .scaleAspectFit
        icon.backgroundColor = AppSettings.shared.themeStyle.accentColor.withAlphaComponent(0.12)
        icon.layer.cornerRadius = 18
        icon.layer.cornerCurve = .continuous
        icon.isAccessibilityElement = false

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = String(localized: "update.available.title", defaultValue: "发现新版本")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 2

        let releaseNameLabel = UILabel()
        releaseNameLabel.translatesAutoresizingMaskIntoConstraints = false
        releaseNameLabel.text = release.name.isEmpty ? release.version.marketingDisplayString : release.name
        releaseNameLabel.font = .systemFont(ofSize: 14, weight: .medium)
        releaseNameLabel.textColor = .secondaryLabel
        releaseNameLabel.numberOfLines = 2

        let currentVersionLabel = makeVersionLabel(
            caption: String(localized: "settings.update.current_version", defaultValue: "当前版本"),
            version: currentVersion.releaseDisplayString,
            emphasized: false
        )
        let nextVersionLabel = makeVersionLabel(
            caption: String(localized: "update.available.title", defaultValue: "发现新版本"),
            version: release.version.releaseDisplayString,
            emphasized: true
        )
        let arrow = UIImageView(image: UIImage(systemName: "arrow.right"))
        arrow.tintColor = .tertiaryLabel
        arrow.contentMode = .scaleAspectFit
        arrow.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let versionRow = UIStackView(arrangedSubviews: [currentVersionLabel, arrow, nextVersionLabel])
        versionRow.translatesAutoresizingMaskIntoConstraints = false
        versionRow.axis = .horizontal
        versionRow.alignment = .center
        versionRow.distribution = .fill
        versionRow.spacing = 12

        let sizeLabel = UILabel()
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.font = .preferredFont(forTextStyle: .caption1)
        sizeLabel.textColor = .secondaryLabel
        if let asset = release.ipaAsset {
            sizeLabel.text = ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file)
        } else {
            sizeLabel.text = String(localized: "update.asset.unavailable", defaultValue: "Release 页面未附带 IPA")
        }

        card.addSubview(icon)
        card.addSubview(titleLabel)
        card.addSubview(releaseNameLabel)
        card.addSubview(versionRow)
        card.addSubview(sizeLabel)
        card.translatesAutoresizingMaskIntoConstraints = false
        card.isAccessibilityElement = true
        card.accessibilityLabel = "\(titleLabel.text ?? ""), \(currentVersion.releaseDisplayString), \(release.version.releaseDisplayString)"
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            icon.widthAnchor.constraint(equalToConstant: 58),
            icon.heightAnchor.constraint(equalToConstant: 58),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 15),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            titleLabel.topAnchor.constraint(equalTo: icon.topAnchor, constant: 3),
            releaseNameLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            releaseNameLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            releaseNameLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            versionRow.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 22),
            versionRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            versionRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            sizeLabel.topAnchor.constraint(equalTo: versionRow.bottomAnchor, constant: 16),
            sizeLabel.leadingAnchor.constraint(equalTo: versionRow.leadingAnchor),
            sizeLabel.trailingAnchor.constraint(equalTo: versionRow.trailingAnchor),
            sizeLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])
        return card
    }

    private func makeVersionLabel(caption: String, version: String, emphasized: Bool) -> UIView {
        let container = UIView()
        container.backgroundColor = emphasized
            ? AppSettings.shared.themeStyle.accentColor.withAlphaComponent(0.12)
            : UIColor.secondarySystemFill
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous

        let captionLabel = UILabel()
        captionLabel.text = caption
        captionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        captionLabel.textColor = .secondaryLabel

        let versionLabel = UILabel()
        versionLabel.text = version
        versionLabel.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        versionLabel.adjustsFontSizeToFitWidth = true
        versionLabel.minimumScaleFactor = 0.78
        versionLabel.textColor = emphasized ? AppSettings.shared.themeStyle.accentColor : .label

        let stack = UIStackView(arrangedSubviews: [captionLabel, versionLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 108),
        ])
        return container
    }

    private func makeReleaseNotesCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = AppSettings.shared.themeStyle.topicCardBackgroundColor
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous

        let heading = UILabel()
        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.text = String(localized: "update.release_notes", defaultValue: "更新内容")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.textColor = AppSettings.shared.themeStyle.accentColor

        let body = UILabel()
        body.translatesAutoresizingMaskIntoConstraints = false
        body.text = release.releaseNotes.isEmpty
            ? String(localized: "update.release_notes.empty", defaultValue: "本次 Release 暂无更新说明。")
            : release.releaseNotes
        body.font = .preferredFont(forTextStyle: .body)
        body.textColor = .secondaryLabel
        body.numberOfLines = 0
        body.attributedText = formattedReleaseNotes()

        card.addSubview(heading)
        card.addSubview(body)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            heading.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            heading.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            body.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func formattedReleaseNotes() -> NSAttributedString {
        let fallback = String(localized: "update.release_notes.empty", defaultValue: "本次 Release 暂无更新说明。")
        let source = release.releaseNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = source.isEmpty ? fallback : source
        guard let markdown = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .full)
        ) else {
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.secondaryLabel,
                ]
            )
        }
        let result = NSMutableAttributedString(markdown)
        result.addAttributes(
            [
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: releaseNotesParagraphStyle,
            ],
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private var releaseNotesParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 9
        return style
    }

    private func makeUpdateButton() -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "update.now", defaultValue: "立即更新")
        configuration.image = UIImage(systemName: "arrow.up.right.square.fill")
        configuration.imagePadding = 8
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = AppSettings.shared.themeStyle.accentColor
        let button = UIButton(configuration: configuration)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        button.accessibilityHint = String(localized: "settings.update.release_page", defaultValue: "打开 GitHub Releases")
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            AppUpdateCoordinator.openReleasePage(release.htmlURL)
            dismiss(animated: true)
        }, for: .touchUpInside)
        return button
    }
}
