import UIKit

/// WeChat-style mini-program more panel: icon grid + cancel (not system action sheet).
@MainActor
final class MiniProgramMoreSheetViewController: UIViewController {
    enum Action: Int {
        case floatWindow
        case reenter
        case copyLink
        /// Save / remove current page in internal browser bookmarks.
        case bookmark
        /// Toggle page lock (anti shake / pinch zoom).
        case toggleInteractionLock
    }

    var onAction: ((Action) -> Void)?
    var onSelectRecent: ((MiniProgramDescriptor) -> Void)?

    private let currentProgram: MiniProgramDescriptor
    /// Whether the host currently locks bounce + zoom.
    private let isInteractionLocked: Bool
    /// Whether the current embedded page is already bookmarked.
    private let isPageBookmarked: Bool
    private var panelBottomConstraint: NSLayoutConstraint?

    private let dimmingView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.alpha = 0
        return view
    }()

    private let panelView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .fill
        return stack
    }()

    init(
        currentProgram: MiniProgramDescriptor,
        isInteractionLocked: Bool = false,
        isPageBookmarked: Bool = false
    ) {
        self.currentProgram = currentProgram
        self.isInteractionLocked = isInteractionLocked
        self.isPageBookmarked = isPageBookmarked
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        view.addSubview(dimmingView)
        view.addSubview(panelView)
        panelView.addSubview(contentStack)

        let bottom = panelView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 420)
        panelBottomConstraint = bottom

        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            panelView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panelView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom,

            contentStack.topAnchor.constraint(equalTo: panelView.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: panelView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: panelView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: panelView.safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])

        buildContent()

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmingTapped))
        dimmingView.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        panelBottomConstraint?.constant = 0
        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0.5,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.dimmingView.alpha = 1
            self.view.layoutIfNeeded()
        }
    }

    private func buildContent() {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // —— 最近使用的小程序（横向）——
        let recent = MiniProgramRecentStore.recentPrograms()
            .filter { $0.id != currentProgram.id }
        let recentRow = Array(recent.prefix(8))
        if !recentRow.isEmpty {
            contentStack.addArrangedSubview(makeSectionPadding(top: 10, bottom: 4) {
                self.makeRecentStrip(programs: recentRow)
            })
            contentStack.addArrangedSubview(makeSeparator())
        }

        // —— 操作图标行（浮窗 / 重新进入 / 复制链接）——
        contentStack.addArrangedSubview(makeSectionPadding(top: 18, bottom: 18) {
            self.makeActionGrid()
        })

        contentStack.addArrangedSubview(makeSeparator(thick: true))

        // —— 取消 ——
        contentStack.addArrangedSubview(makeCancelButton())
    }

    // MARK: - Sections

    private func makeRecentStrip(programs: [MiniProgramDescriptor]) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 16

        for program in programs {
            row.addArrangedSubview(makeRecentTile(program: program))
        }

        scroll.addSubview(row)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 78),

            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        return container
    }

    private func makeRecentTile(program: MiniProgramDescriptor) -> UIView {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.accessibilityLabel = program.displayName
        control.accessibilityTraits = .button

        let iconBadge = MiniProgramIconBadge.view(for: program.id, size: 48)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = program.displayName
        title.font = .systemFont(ofSize: 11, weight: .regular)
        title.textColor = .secondaryLabel
        title.textAlignment = .center
        title.numberOfLines = 1
        title.lineBreakMode = .byTruncatingTail
        title.isUserInteractionEnabled = false

        control.addSubview(iconBadge)
        control.addSubview(title)

        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(equalToConstant: 56),

            iconBadge.topAnchor.constraint(equalTo: control.topAnchor),
            iconBadge.centerXAnchor.constraint(equalTo: control.centerXAnchor),

            title.topAnchor.constraint(equalTo: iconBadge.bottomAnchor, constant: 6),
            title.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            title.bottomAnchor.constraint(equalTo: control.bottomAnchor),
        ])

        control.addAction(UIAction { [weak self] _ in
            self?.dismissSheet {
                self?.onSelectRecent?(program)
            }
        }, for: .touchUpInside)
        return control
    }

    private func makeActionGrid() -> UIView {
        // When locked, show「不锁定」; otherwise「锁定」— one tile toggles host bounce/zoom lock.
        let lockSymbol = isInteractionLocked ? "lock.open.fill" : "lock.fill"
        let lockTitle = isInteractionLocked
            ? String(localized: "mini_program.action.unlock", defaultValue: "不锁定")
            : String(localized: "mini_program.action.lock", defaultValue: "锁定")

        let bookmarkSymbol = isPageBookmarked ? "bookmark.fill" : "bookmark"
        let bookmarkTitle = isPageBookmarked
            ? String(localized: "me.browser.remove_bookmark", defaultValue: "取消收藏")
            : String(localized: "me.browser.add_bookmark", defaultValue: "收藏此页")

        let items: [(Action, String, String)] = [
            (
                .floatWindow,
                "doc.on.doc",
                String(localized: "mini_program.action.float", defaultValue: "浮窗")
            ),
            (
                .reenter,
                "arrow.clockwise",
                String(localized: "mini_program.action.reenter", defaultValue: "重新进入小程序")
            ),
            (
                .copyLink,
                "link",
                String(localized: "mini_program.action.copy_link", defaultValue: "复制链接")
            ),
            (
                .bookmark,
                bookmarkSymbol,
                bookmarkTitle
            ),
            (
                .toggleInteractionLock,
                lockSymbol,
                lockTitle
            ),
        ]

        let row = UIStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 8

        for item in items {
            row.addArrangedSubview(makeActionTile(action: item.0, symbol: item.1, title: item.2))
        }

        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: wrap.topAnchor),
            row.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        return wrap
    }

    private func makeActionTile(action: Action, symbol: String, title: String) -> UIView {
        let control = UIControl()
        control.translatesAutoresizingMaskIntoConstraints = false
        control.accessibilityLabel = title
        control.accessibilityTraits = .button

        let iconBg = UIView()
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        iconBg.backgroundColor = .white
        iconBg.layer.cornerRadius = 14
        iconBg.layer.cornerCurve = .continuous
        iconBg.isUserInteractionEnabled = false

        let icon = UIImageView(
            image: UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            )
        )
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = UIColor(white: 0.2, alpha: 1)
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = title
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 2
        label.isUserInteractionEnabled = false

        control.addSubview(iconBg)
        iconBg.addSubview(icon)
        control.addSubview(label)

        NSLayoutConstraint.activate([
            iconBg.topAnchor.constraint(equalTo: control.topAnchor),
            iconBg.centerXAnchor.constraint(equalTo: control.centerXAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 56),
            iconBg.heightAnchor.constraint(equalToConstant: 56),

            icon.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),

            label.topAnchor.constraint(equalTo: iconBg.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: control.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: control.trailingAnchor, constant: -2),
            label.bottomAnchor.constraint(equalTo: control.bottomAnchor),
        ])

        control.addAction(UIAction { [weak self] _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.dismissSheet {
                self?.onAction?(action)
            }
        }, for: .touchUpInside)

        // Press feedback
        control.addAction(UIAction { _ in
            UIView.animate(withDuration: 0.12) {
                iconBg.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
                iconBg.backgroundColor = UIColor.white.withAlphaComponent(0.7)
            }
        }, for: .touchDown)
        let reset = UIAction { _ in
            UIView.animate(withDuration: 0.12) {
                iconBg.transform = .identity
                iconBg.backgroundColor = .white
            }
        }
        control.addAction(reset, for: [.touchUpInside, .touchUpOutside, .touchCancel])

        return control
    }

    private func makeCancelButton() -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(String(localized: "common.cancel", defaultValue: "取消"), for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .regular)
        button.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1)
        button.heightAnchor.constraint(equalToConstant: 56).isActive = true
        button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return button
    }

    private func makeSeparator(thick: Bool = false) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.06)
        view.heightAnchor.constraint(equalToConstant: thick ? 8 : 1.0 / UIScreen.main.scale).isActive = true
        return view
    }

    private func makeSectionPadding(top: CGFloat, bottom: CGFloat, content: () -> UIView) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        let inner = content()
        wrap.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: wrap.topAnchor, constant: top),
            inner.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -bottom),
        ])
        return wrap
    }

    // MARK: - Dismiss

    @objc private func dimmingTapped() {
        dismissSheet()
    }

    @objc private func cancelTapped() {
        dismissSheet()
    }

    private func dismissSheet(completion: (() -> Void)? = nil) {
        panelBottomConstraint?.constant = 420
        UIView.animate(
            withDuration: 0.26,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction],
            animations: {
                self.dimmingView.alpha = 0
                self.view.layoutIfNeeded()
            },
            completion: { _ in
                self.dismiss(animated: false, completion: completion)
            }
        )
    }
}
