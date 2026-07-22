import UIKit

/// FluxDo-style invite links page (invite_links_page.dart), rendered with the
/// app's native card look: create card + collapsible advanced options card +
/// latest-link result card.
final class InviteLinksViewController: UIViewController {
    private enum ExpiryPreset: CaseIterable {
        case days1, days7, days30, days90, never

        var days: Int? {
            switch self {
            case .days1: return 1
            case .days7: return 7
            case .days30: return 30
            case .days90: return 90
            case .never: return nil
            }
        }

        var label: String {
            guard let days else {
                return String(localized: "invites.expiry.never", defaultValue: "永久")
            }
            return String(
                format: String(localized: "invites.expiry.days_chip", defaultValue: "%d 天"),
                days
            )
        }
    }

    private let api: DiscourseAPI
    private let username: String

    private var latestInvite: DiscourseInviteLink?
    private var isSubmitting = false
    private var isLoadingLatest = false
    private var showsAdvancedOptions = false
    private var selectedPreset: ExpiryPreset = .days1
    private var errorMessage: String?

    // Inputs live outside render() so text survives card rebuilds.
    private let descriptionField: UITextField = {
        let field = UITextField()
        field.placeholder = String(localized: "invites.description.placeholder")
        field.borderStyle = .roundedRect
        field.clearButtonMode = .whileEditing
        return field
    }()

    private let emailField: UITextField = {
        let field = UITextField()
        field.placeholder = String(localized: "invites.email.placeholder", defaultValue: "限制邮箱（可选）")
        field.borderStyle = .roundedRect
        field.keyboardType = .emailAddress
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.clearButtonMode = .whileEditing
        return field
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .onDrag
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let contentStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 16
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let control = UIRefreshControl()
        control.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        return control
    }()

    private var accentColor: UIColor {
        AppSettings.shared.themeStyle.accentColor
    }

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.invite_links")
        view.backgroundColor = .systemGroupedBackground
        scrollView.refreshControl = refreshControl

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        isLoadingLatest = true
        render()
        Task { await loadLatestInvite() }
    }

    @objc private func refreshPulled() {
        Task { await loadLatestInvite() }
    }

    // MARK: Data

    private func loadLatestInvite() async {
        isLoadingLatest = true
        do {
            let invites = try await api.fetchPendingInvites(username: username)
            // ISO8601 timestamps from the same server compare correctly as strings.
            latestInvite = invites.max { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        } catch {
            // Keep whatever we already show; pending list is only a recovery path.
        }
        isLoadingLatest = false
        refreshControl.endRefreshing()
        render()
    }

    private func createInvite(useAdvancedOptions: Bool) {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        render()
        view.endEditing(true)

        let description = useAdvancedOptions ? descriptionField.text : nil
        let email = useAdvancedOptions ? emailField.text : nil
        let expiresAt = selectedPreset.days.flatMap {
            Calendar.current.date(byAdding: .day, value: $0, to: Date())
        }
        Task {
            do {
                let invite = try await api.createInvite(
                    description: description,
                    expiresAt: expiresAt,
                    email: email
                )
                latestInvite = invite
                if let url = invite.effectiveURLString(baseURL: api.baseURL) {
                    UIPasteboard.general.string = url
                }
            } catch {
                if let apiError = error as? DiscourseAPIError, apiError.isRateLimited {
                    errorMessage = String(
                        localized: "invites.error.rate_limited",
                        defaultValue: "创建过于频繁，邀请链接约每 24 小时可创建一次。"
                    )
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isSubmitting = false
            render()
        }
    }

    // MARK: Rendering

    private func render() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        contentStack.addArrangedSubview(makeCreateCard())
        if showsAdvancedOptions {
            contentStack.addArrangedSubview(makeAdvancedCard())
        }
        if let errorMessage {
            contentStack.addArrangedSubview(makeErrorBanner(errorMessage))
        }
        if latestInvite != nil {
            contentStack.addArrangedSubview(makeResultCard())
        } else if !isLoadingLatest {
            contentStack.addArrangedSubview(makeEmptyCard())
        }
    }

    private var summaryText: String {
        if let days = selectedPreset.days {
            return String(
                format: String(
                    localized: "invites.summary.days",
                    defaultValue: "创建一个 %d 天有效的邀请链接，最多可使用 1 次，成功后自动复制。"
                ),
                days
            )
        }
        return String(
            localized: "invites.summary.never",
            defaultValue: "创建一个永久有效的邀请链接，最多可使用 1 次，成功后自动复制。"
        )
    }

    private func makeCreateCard() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = String(localized: "invites.create.title")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let summaryLabel = UILabel()
        summaryLabel.text = summaryText
        summaryLabel.font = .systemFont(ofSize: 13)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 0

        var toggleConfig = UIButton.Configuration.plain()
        toggleConfig.title = showsAdvancedOptions
            ? String(localized: "invites.options.collapse", defaultValue: "收起选项")
            : String(localized: "invites.options.expand", defaultValue: "展开选项")
        toggleConfig.contentInsets = .zero
        toggleConfig.baseForegroundColor = accentColor
        toggleConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            return outgoing
        }
        let toggleButton = UIButton(configuration: toggleConfig)
        toggleButton.contentHorizontalAlignment = .leading
        toggleButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            showsAdvancedOptions.toggle()
            render()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, summaryLabel, toggleButton])
        stack.axis = .vertical
        stack.spacing = 8
        if !showsAdvancedOptions {
            stack.addArrangedSubview(makeSubmitButton(useAdvancedOptions: false))
            stack.setCustomSpacing(12, after: toggleButton)
        }
        return wrapInCard(stack)
    }

    private func makeAdvancedCard() -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = String(localized: "invites.advanced.title", defaultValue: "邀请成员")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let emailHelper = UILabel()
        emailHelper.text = String(
            localized: "invites.email.helper",
            defaultValue: "填写后仅该邮箱可使用此邀请"
        )
        emailHelper.font = .systemFont(ofSize: 12)
        emailHelper.textColor = .tertiaryLabel

        let redemptionTitle = makeFieldTitle(
            String(localized: "invites.max_redemptions", defaultValue: "可使用次数")
        )
        let redemptionRow = makeReadOnlyRow(
            value: "1",
            note: String(localized: "invites.fixed", defaultValue: "固定")
        )

        let expiryTitle = makeFieldTitle(
            String(localized: "invites.expiry.title", defaultValue: "有效期")
        )

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            descriptionField,
            emailField,
            emailHelper,
            redemptionTitle,
            redemptionRow,
            expiryTitle,
            makeExpiryChips(),
            makeSubmitButton(useAdvancedOptions: true),
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(16, after: titleLabel)
        stack.setCustomSpacing(6, after: emailField)
        stack.setCustomSpacing(16, after: emailHelper)
        stack.setCustomSpacing(8, after: redemptionTitle)
        stack.setCustomSpacing(16, after: redemptionRow)
        stack.setCustomSpacing(8, after: expiryTitle)
        stack.setCustomSpacing(20, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
        return wrapInCard(stack)
    }

    private func makeExpiryChips() -> UIView {
        let buttons = ExpiryPreset.allCases.map { preset -> UIButton in
            let selected = preset == selectedPreset
            var config = UIButton.Configuration.plain()
            config.title = preset.label
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
            config.baseForegroundColor = selected ? .white : .label
            config.background.backgroundColor = selected ? accentColor : .tertiarySystemFill
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
                return outgoing
            }
            let button = UIButton(configuration: config)
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                selectedPreset = preset
                render()
            }, for: .touchUpInside)
            return button
        }

        // ponytail: fixed 3+2 split instead of a measuring flow layout — five short
        // chip titles fit two rows on every supported width.
        let firstRow = UIStackView(arrangedSubviews: Array(buttons.prefix(3)) + [UIView()])
        let secondRow = UIStackView(arrangedSubviews: Array(buttons.dropFirst(3)) + [UIView()])
        for row in [firstRow, secondRow] {
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .center
        }
        let wrap = UIStackView(arrangedSubviews: [firstRow, secondRow])
        wrap.axis = .vertical
        wrap.spacing = 8
        return wrap
    }

    private func makeSubmitButton(useAdvancedOptions: Bool) -> UIView {
        var config = UIButton.Configuration.filled()
        config.title = isSubmitting
            ? String(localized: "invites.creating", defaultValue: "创建中…")
            : String(localized: "invites.create.title")
        config.image = isSubmitting ? nil : UIImage(systemName: "link")
        config.imagePadding = 6
        config.cornerStyle = .large
        config.baseBackgroundColor = accentColor
        config.baseForegroundColor = .white
        config.showsActivityIndicator = isSubmitting
        let button = UIButton(configuration: config)
        button.isEnabled = !isSubmitting
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        button.addAction(UIAction { [weak self] _ in
            self?.createInvite(useAdvancedOptions: useAdvancedOptions)
        }, for: .touchUpInside)
        return button
    }

    private func makeResultCard() -> UIView {
        guard let invite = latestInvite else { return UIView() }
        let urlString = invite.effectiveURLString(baseURL: api.baseURL)
            ?? String(localized: "invites.unknown")

        let titleLabel = UILabel()
        titleLabel.text = String(localized: "invites.latest.title", defaultValue: "最新邀请链接")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let linkLabel = UILabel()
        linkLabel.text = urlString
        linkLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        linkLabel.numberOfLines = 0

        let linkContainer = UIView()
        linkContainer.backgroundColor = .tertiarySystemFill
        linkContainer.layer.cornerRadius = 12
        linkContainer.layer.cornerCurve = .continuous
        linkLabel.translatesAutoresizingMaskIntoConstraints = false
        linkContainer.addSubview(linkLabel)
        NSLayoutConstraint.activate([
            linkLabel.topAnchor.constraint(equalTo: linkContainer.topAnchor, constant: 12),
            linkLabel.leadingAnchor.constraint(equalTo: linkContainer.leadingAnchor, constant: 12),
            linkLabel.trailingAnchor.constraint(equalTo: linkContainer.trailingAnchor, constant: -12),
            linkLabel.bottomAnchor.constraint(equalTo: linkContainer.bottomAnchor, constant: -12),
        ])

        let usageChip = makeMetaChip(
            symbolName: "repeat",
            text: String(localized: "invites.meta.usage", defaultValue: "可使用 1 次")
        )
        let expiryChip: UIView
        if let expiryText = Self.formatExpiry(invite.expiresAt) {
            expiryChip = makeMetaChip(
                symbolName: "clock",
                text: String(
                    format: String(localized: "invites.meta.expiry", defaultValue: "%@ 到期"),
                    expiryText
                )
            )
        } else {
            expiryChip = makeMetaChip(
                symbolName: "infinity",
                text: String(localized: "invites.meta.never", defaultValue: "永久有效")
            )
        }
        let chipsRow = UIStackView(arrangedSubviews: [usageChip, expiryChip, UIView()])
        chipsRow.axis = .horizontal
        chipsRow.spacing = 8
        chipsRow.alignment = .center

        var copyConfig = UIButton.Configuration.gray()
        copyConfig.title = String(localized: "invites.copy")
        copyConfig.image = UIImage(systemName: "doc.on.doc")
        copyConfig.imagePadding = 6
        copyConfig.cornerStyle = .large
        let copyButton = UIButton(configuration: copyConfig)
        copyButton.addAction(UIAction { [weak copyButton] _ in
            UIPasteboard.general.string = urlString
            copyButton?.configuration?.title = String(localized: "invites.copied", defaultValue: "已复制")
            copyButton?.configuration?.image = UIImage(systemName: "checkmark")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak copyButton] in
                copyButton?.configuration?.title = String(localized: "invites.copy")
                copyButton?.configuration?.image = UIImage(systemName: "doc.on.doc")
            }
        }, for: .touchUpInside)

        var shareConfig = UIButton.Configuration.filled()
        shareConfig.title = String(localized: "invites.share")
        shareConfig.image = UIImage(systemName: "square.and.arrow.up")
        shareConfig.imagePadding = 6
        shareConfig.cornerStyle = .large
        shareConfig.baseBackgroundColor = accentColor
        shareConfig.baseForegroundColor = .white
        let shareButton = UIButton(configuration: shareConfig)
        shareButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let activity = UIActivityViewController(activityItems: [urlString], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = view
            present(activity, animated: true)
        }, for: .touchUpInside)

        let buttonsRow = UIStackView(arrangedSubviews: [copyButton, shareButton])
        buttonsRow.axis = .horizontal
        buttonsRow.spacing = 12
        buttonsRow.distribution = .fillEqually
        buttonsRow.translatesAutoresizingMaskIntoConstraints = false
        buttonsRow.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, linkContainer, chipsRow, buttonsRow])
        stack.axis = .vertical
        stack.spacing = 12
        return wrapInCard(stack)
    }

    private func makeEmptyCard() -> UIView {
        let label = UILabel()
        label.text = String(localized: "invites.empty")
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return wrapInCard(label)
    }

    private func makeErrorBanner(_ message: String) -> UIView {
        let banner = UIView()
        banner.backgroundColor = UIColor.systemRed.withAlphaComponent(0.08)
        banner.layer.cornerRadius = 12
        banner.layer.cornerCurve = .continuous

        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 13)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: banner.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -12),
        ])
        return banner
    }

    // MARK: Small builders

    private func wrapInCard(_ content: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func makeFieldTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        return label
    }

    private func makeReadOnlyRow(value: String, note: String) -> UIView {
        let row = UIView()
        row.backgroundColor = .tertiarySystemFill
        row.layer.cornerRadius = 10
        row.layer.cornerCurve = .continuous

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 15)

        let noteLabel = UILabel()
        noteLabel.text = note
        noteLabel.font = .systemFont(ofSize: 12, weight: .medium)
        noteLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [valueLabel, UIView(), noteLabel])
        stack.axis = .horizontal
        stack.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
        ])
        return row
    }

    private func makeMetaChip(symbolName: String, text: String) -> UIView {
        let chip = UIView()
        chip.backgroundColor = .tertiarySystemFill
        chip.layer.cornerRadius = 14

        let icon = UIImageView(image: UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        ))
        icon.tintColor = .secondaryLabel
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: chip.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -6),
        ])
        return chip
    }

    private static func formatExpiry(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: iso)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: iso)
        }
        guard let date else { return iso }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
