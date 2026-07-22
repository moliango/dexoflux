import SwiftSoup
import UIKit

// MARK: - Connect report model

/// Parsed form of the trust-level card on https://connect.linux.do/.
/// Mirrors FluxDo's `TrustLevelData` (trust_level_requirements_page.dart).
struct ConnectTrustReport {
    enum BadgeKind {
        case success, warning, danger
    }

    struct Ring {
        let label: String
        let current: Int
        let max: Int
        let isMet: Bool
    }

    struct Bar {
        let label: String
        let currentText: String
        let progress: Double
        let isMet: Bool
    }

    struct Quota {
        let label: String
        let valueText: String
        let isMet: Bool
        let usedSlots: Int
    }

    struct Veto {
        let label: String
        let desc: String
        let value: String
        let isMet: Bool
    }

    var title: String
    var badgeText: String
    var badgeKind: BadgeKind
    var subtitle: String
    var rings: [Ring]
    var bars: [Bar]
    var quotas: [Quota]
    var vetos: [Veto]
    var footerHint: String
    var statusText: String
    var isStatusMet: Bool
    var isEmptyState: Bool
    var emptyParagraphs: [String]
}

// MARK: - Connect HTML parser

enum ConnectTrustParserError: Error {
    case cardNotFound
}

enum ConnectTrustParser {
    static func parse(html: String) throws -> ConnectTrustReport {
        let document = try SwiftSoup.parse(html)
        guard let card = try document.select("div.card").first() else {
            throw ConnectTrustParserError.cardNotFound
        }

        if card.hasClass("empty-state") {
            let title = text(card, "h2.card-title")
            let paragraphs = elements(card, "p")
                .compactMap { try? $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return ConnectTrustReport(
                title: title,
                badgeText: "",
                badgeKind: .warning,
                subtitle: paragraphs.first ?? "",
                rings: [],
                bars: [],
                quotas: [],
                vetos: [],
                footerHint: paragraphs.dropFirst().joined(separator: "\n"),
                statusText: "",
                isStatusMet: false,
                isEmptyState: true,
                emptyParagraphs: paragraphs
            )
        }

        let badgeElement = try? card.select(".badge").first()
        let badgeKind: ConnectTrustReport.BadgeKind
        if badgeElement?.hasClass("badge-success") == true {
            badgeKind = .success
        } else if badgeElement?.hasClass("badge-danger") == true {
            badgeKind = .danger
        } else {
            badgeKind = .warning
        }

        let rings = elements(card, ".tl3-ring").map { el -> ConnectTrustReport.Ring in
            let circle = try? el.select(".tl3-ring-circle").first()
            let style = circle.flatMap { try? $0.attr("style") } ?? ""
            return ConnectTrustReport.Ring(
                label: text(el, ".tl3-ring-label"),
                current: Int(cssVar(style, "--val")),
                max: Int(cssVar(style, "--max")),
                isMet: circle?.hasClass("met") ?? false
            )
        }

        let bars = elements(card, ".tl3-bar-item").map { el -> ConnectTrustReport.Bar in
            let fill = try? el.select(".tl3-bar-fill").first()
            let style = fill.flatMap { try? $0.attr("style") } ?? ""
            let val = cssVar(style, "--val")
            let max = cssVar(style, "--max")
            return ConnectTrustReport.Bar(
                label: text(el, ".tl3-bar-label"),
                currentText: text(el, ".tl3-bar-nums"),
                progress: max > 0 ? min(Swift.max(val / max, 0), 1) : 0,
                isMet: fill?.hasClass("met") ?? false
            )
        }

        let quotas = elements(card, ".tl3-quota-card").map { el -> ConnectTrustReport.Quota in
            ConnectTrustReport.Quota(
                label: text(el, ".tl3-quota-label"),
                valueText: text(el, ".tl3-quota-nums"),
                isMet: !el.hasClass("unmet"),
                usedSlots: elements(el, ".tl3-slot.used").count
            )
        }

        let vetos = elements(card, ".tl3-veto-item").map { el -> ConnectTrustReport.Veto in
            let isMet = !el.hasClass("unmet")
            let face = (try? el.select(isMet ? ".tl3-veto-front" : ".tl3-veto-back").first()) ?? nil
            return ConnectTrustReport.Veto(
                label: face.map { text($0, ".tl3-veto-label") } ?? "",
                desc: face.map { text($0, ".tl3-veto-desc") } ?? "",
                value: face.map { text($0, ".tl3-veto-value") } ?? "0",
                isMet: isMet
            )
        }

        let statusElement = try? card.select(".status-met, .status-unmet").first()

        return ConnectTrustReport(
            title: text(card, "h2.card-title"),
            badgeText: badgeElement.flatMap { try? $0.text() }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            badgeKind: badgeKind,
            subtitle: text(card, ".card-subtitle"),
            rings: rings,
            bars: bars,
            quotas: quotas,
            vetos: vetos,
            footerHint: text(card, ".text-hint"),
            statusText: statusElement.flatMap { try? $0.text() }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            isStatusMet: statusElement?.hasClass("status-met") ?? false,
            isEmptyState: false,
            emptyParagraphs: []
        )
    }

    private static func text(_ root: Element, _ selector: String) -> String {
        guard let el = try? root.select(selector).first() else { return "" }
        return (try? el.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func elements(_ root: Element, _ selector: String) -> [Element] {
        (try? root.select(selector).array()) ?? []
    }

    private static func cssVar(_ style: String, _ name: String) -> Double {
        guard let range = style.range(of: "\(name):\\s*([0-9.]+)", options: .regularExpression) else {
            return 0
        }
        let match = style[range]
        guard let numberRange = match.range(of: "[0-9.]+", options: .regularExpression) else {
            return 0
        }
        return Double(match[numberRange]) ?? 0
    }
}

// MARK: - Fallback requirements

/// One requirement row when connect data is unavailable; thresholds are FluxDo's
/// hardcoded linux.do defaults per current trust level.
struct TrustFallbackRequirement {
    let label: String
    let current: Int?
    let target: Int
    let unit: String
    let isReverse: Bool

    init(label: String, current: Int?, target: Int, unit: String = "", isReverse: Bool = false) {
        self.label = label
        self.current = current
        self.target = target
        self.unit = unit
        self.isReverse = isReverse
    }

    var isMet: Bool {
        guard let current else { return false }
        return isReverse ? current <= target : current >= target
    }

    var progress: Double {
        guard let current else { return 0 }
        if isReverse {
            if target == 0 { return current <= 0 ? 1 : 0 }
            return min(Swift.max(1 - Double(current) / Double(target), 0), 1)
        }
        if target <= 0 { return isMet ? 1 : 0 }
        return min(Double(current) / Double(target), 1)
    }

    var valueText: String {
        let currentText = current.map(String.init) ?? "-"
        let targetText = isReverse ? "≤ \(target)" : "\(target)"
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return "\(currentText) / \(targetText)\(suffix)"
    }
}

enum TrustFallbackCatalog {
    static func requirements(level: Int, summary: DiscourseUserSummary?) -> [TrustFallbackRequirement] {
        let readingMinutes = summary.map { $0.timeRead / 60 }
        let dayUnit = String(localized: "trust.unit.days", defaultValue: "天")
        let minuteUnit = String(localized: "trust.unit.minutes", defaultValue: "分钟")
        let topicsEntered = String(localized: "trust.req.topics_entered", defaultValue: "浏览话题")
        let postsRead = String(localized: "trust.req.posts_read", defaultValue: "已读帖子")
        let readingTime = String(localized: "trust.req.reading_time", defaultValue: "阅读时间")
        let replies = String(localized: "trust.req.replies", defaultValue: "回复")

        switch level {
        case 0:
            return [
                TrustFallbackRequirement(label: topicsEntered, current: summary?.topicsEntered, target: 5),
                TrustFallbackRequirement(label: postsRead, current: summary?.postsReadCount, target: 30),
                TrustFallbackRequirement(label: readingTime, current: readingMinutes, target: 10, unit: minuteUnit),
            ]
        case 1:
            return [
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.days_visited", defaultValue: "访问天数"),
                    current: summary?.daysVisited,
                    target: 15,
                    unit: dayUnit
                ),
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.likes_given", defaultValue: "送出赞"),
                    current: summary?.likesGiven,
                    target: 1
                ),
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.likes_received", defaultValue: "获赞"),
                    current: summary?.likesReceived,
                    target: 1
                ),
                TrustFallbackRequirement(label: replies, current: summary?.postCount, target: 3),
                TrustFallbackRequirement(label: topicsEntered, current: summary?.topicsEntered, target: 20),
                TrustFallbackRequirement(label: postsRead, current: summary?.postsReadCount, target: 100),
                TrustFallbackRequirement(label: readingTime, current: readingMinutes, target: 60, unit: minuteUnit),
            ]
        default:
            return [
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.visits", defaultValue: "访问次数"),
                    current: summary?.daysVisited,
                    target: 50
                ),
                TrustFallbackRequirement(label: replies, current: summary?.postCount, target: 10),
                TrustFallbackRequirement(label: topicsEntered, current: summary?.topicsEntered, target: 500),
                TrustFallbackRequirement(label: postsRead, current: summary?.postsReadCount, target: 20000),
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.likes_given_short", defaultValue: "点赞"),
                    current: summary?.likesGiven,
                    target: 30
                ),
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.likes_received", defaultValue: "获赞"),
                    current: summary?.likesReceived,
                    target: 20
                ),
                // ponytail: flag/suspension counters are not exposed by the summary
                // API; assume 0 like FluxDo does.
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.flagged_posts", defaultValue: "被举报帖子"),
                    current: 0,
                    target: 5,
                    isReverse: true
                ),
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.flagging_users", defaultValue: "发起举报用户"),
                    current: 0,
                    target: 5,
                    isReverse: true
                ),
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.silenced", defaultValue: "被禁言"),
                    current: 0,
                    target: 0,
                    isReverse: true
                ),
                TrustFallbackRequirement(
                    label: String(localized: "trust.req.suspended", defaultValue: "被封禁"),
                    current: 0,
                    target: 0,
                    isReverse: true
                ),
            ]
        }
    }
}

// MARK: - View controller

final class TrustRequirementsViewController: UIViewController {
    private enum DisplayState {
        case loading
        case report(ConnectTrustReport)
        case fallback(note: String, items: [TrustFallbackRequirement])
        case error(String)
    }

    private enum Palette {
        static let met = UIColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1) // #22c55e
        static let pending = UIColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1) // #f59e0b
        static let danger = UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1) // #ef4444
    }

    private static let connectURLString = "https://connect.linux.do/"

    private let api: DiscourseAPI
    private let username: String?
    private let trustLevel: Int
    private var state: DisplayState = .loading

    private static let connectSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.alwaysBounceVertical = true
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

    init(api: DiscourseAPI, username: String?, trustLevel: Int) {
        self.api = api
        self.username = username
        self.trustLevel = trustLevel
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "me.trust_requirements")
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

        reload(showLoading: true)
    }

    @objc private func refreshPulled() {
        reload(showLoading: false)
    }

    private func reload(showLoading: Bool) {
        if showLoading {
            state = .loading
            render()
        }
        Task {
            await load()
            refreshControl.endRefreshing()
            render()
        }
    }

    private var isLinuxDoForum: Bool {
        guard let host = URL(string: api.baseURL)?.host?.lowercased() else { return false }
        return host == "linux.do" || host.hasSuffix(".linux.do")
    }

    private func load() async {
        var fallbackNote = String(
            localized: "trust.fallback.note",
            defaultValue: "以下进度来自个人统计数据，非 Connect 实时数据。"
        )
        if isLinuxDoForum {
            if let report = await fetchConnectReport() {
                if !report.isEmptyState {
                    state = .report(report)
                    return
                }
                if let paragraph = report.emptyParagraphs.first, !paragraph.isEmpty {
                    fallbackNote = paragraph
                }
            }
        }
        await loadFallback(note: fallbackNote)
    }

    private func fetchConnectReport() async -> ConnectTrustReport? {
        guard let url = URL(string: Self.connectURLString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let cookieHeader = WebCookieStore.shared.cookieHeader(for: url)
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let userAgent = WebCookieStore.shared.userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        guard let (data, response) = try? await Self.connectSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        // ponytail: parse runs on the main actor; the connect page is ~tens of KB
        // so this stays well under a frame. Move to a nonisolated worker if it grows.
        return try? ConnectTrustParser.parse(html: html)
    }

    private func loadFallback(note: String) async {
        guard let username else {
            state = .error(String(localized: "trust.error.login", defaultValue: "登录后可查看信任等级进度"))
            return
        }
        do {
            let summary = try await api.fetchUserSummary(username: username)
            state = .fallback(note: note, items: TrustFallbackCatalog.requirements(level: trustLevel, summary: summary))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: Rendering

    private func render() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch state {
        case .loading:
            contentStack.addArrangedSubview(makeLoadingView())
        case .report(let report):
            renderReport(report)
        case .fallback(let note, let items):
            renderFallback(note: note, items: items)
        case .error(let message):
            contentStack.addArrangedSubview(makeErrorView(message: message))
        }
    }

    private func renderReport(_ report: ConnectTrustReport) {
        contentStack.addArrangedSubview(makeHeaderCard(report: report))
        if !report.rings.isEmpty {
            contentStack.addArrangedSubview(makeCard(
                title: String(localized: "trust.section.activity", defaultValue: "活动"),
                content: makeRingsRow(report.rings)
            ))
        }
        if !report.bars.isEmpty {
            let barsStack = UIStackView()
            barsStack.axis = .vertical
            barsStack.spacing = 14
            for bar in report.bars {
                barsStack.addArrangedSubview(makeBarRow(bar))
            }
            contentStack.addArrangedSubview(makeCard(
                title: String(localized: "trust.section.interaction", defaultValue: "互动"),
                content: barsStack
            ))
        }
        if !report.quotas.isEmpty || !report.vetos.isEmpty {
            let complianceStack = UIStackView()
            complianceStack.axis = .vertical
            complianceStack.spacing = 12
            if !report.quotas.isEmpty {
                complianceStack.addArrangedSubview(makeTileRow(report.quotas.map(makeQuotaTile)))
            }
            if !report.vetos.isEmpty {
                complianceStack.addArrangedSubview(makeTileRow(report.vetos.map(makeVetoTile)))
            }
            contentStack.addArrangedSubview(makeCard(
                title: String(localized: "trust.section.compliance", defaultValue: "合规"),
                content: complianceStack
            ))
        }
        if !report.footerHint.isEmpty {
            let hint = UILabel()
            hint.text = report.footerHint
            hint.font = .systemFont(ofSize: 12)
            hint.textColor = .tertiaryLabel
            hint.textAlignment = .center
            hint.numberOfLines = 0
            contentStack.addArrangedSubview(hint)
        }
        if !report.statusText.isEmpty {
            contentStack.addArrangedSubview(makeStatusBanner(text: report.statusText, isMet: report.isStatusMet))
        }
    }

    private func renderFallback(note: String, items: [TrustFallbackRequirement]) {
        let target = trustLevel + 1
        let titleText = target > 3
            ? String(localized: "trust.fallback.title.max", defaultValue: "信任级别参考要求")
            : String(
                format: String(localized: "trust.fallback.title", defaultValue: "升至信任级别 %d 的参考要求"),
                target
            )

        let noteLabel = UILabel()
        noteLabel.text = note
        noteLabel.font = .systemFont(ofSize: 12)
        noteLabel.textColor = .secondaryLabel
        noteLabel.numberOfLines = 0

        let rowsStack = UIStackView()
        rowsStack.axis = .vertical
        rowsStack.spacing = 14
        rowsStack.addArrangedSubview(noteLabel)
        for item in items {
            rowsStack.addArrangedSubview(makeFallbackRow(item))
        }
        contentStack.addArrangedSubview(makeCard(title: titleText, content: rowsStack))
    }

    // MARK: View builders

    private func makeLoadingView() -> UIView {
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        let container = UIView()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 120),
            spinner.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeErrorView(message: String) -> UIView {
        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        var config = UIButton.Configuration.gray()
        config.title = String(localized: "trust.error.retry", defaultValue: "重试")
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.addAction(UIAction { [weak self] _ in self?.reload(showLoading: true) }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 120, left: 16, bottom: 0, right: 16)
        return stack
    }

    private func makeCard(title: String, content: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [titleLabel, content])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
        ])
        return card
    }

    private func makeHeaderCard(report: ConnectTrustReport) -> UIView {
        let subtitleLabel = UILabel()
        subtitleLabel.text = report.subtitle
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0

        let titleLabel = UILabel()
        titleLabel.text = report.title
        titleLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        titleLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [subtitleLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 4

        if !report.badgeText.isEmpty {
            let color: UIColor
            switch report.badgeKind {
            case .success: color = Palette.met
            case .warning: color = Palette.pending
            case .danger: color = Palette.danger
            }
            let badge = PaddedLabel()
            badge.text = report.badgeText
            badge.font = .systemFont(ofSize: 12, weight: .semibold)
            badge.textColor = color
            badge.backgroundColor = color.withAlphaComponent(0.12)
            badge.layer.cornerRadius = 12
            badge.layer.cornerCurve = .continuous
            badge.clipsToBounds = true
            badge.contentInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            let badgeRow = UIStackView(arrangedSubviews: [badge, UIView()])
            badgeRow.axis = .horizontal
            stack.addArrangedSubview(badgeRow)
            stack.setCustomSpacing(10, after: titleLabel)
        }

        let container = UIView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    private func makeRingsRow(_ rings: [ConnectTrustReport.Ring]) -> UIView {
        let row = UIStackView(arrangedSubviews: rings.map { ring in
            let view = TrustRingView()
            view.configure(
                current: ring.current,
                max: ring.max,
                label: ring.label,
                color: ring.isMet ? Palette.met : Palette.pending
            )
            return view
        })
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.alignment = .top
        return row
    }

    private func makeBarRow(_ bar: ConnectTrustReport.Bar) -> UIView {
        let color = bar.isMet ? Palette.met : Palette.pending

        let label = UILabel()
        label.text = bar.label
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel

        let value = UILabel()
        value.text = bar.currentText
        value.font = .systemFont(ofSize: 14, weight: .semibold)
        value.textColor = color
        value.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [label, value])
        topRow.axis = .horizontal
        topRow.spacing = 8

        let track = UIView()
        track.backgroundColor = .tertiarySystemFill
        track.layer.cornerRadius = 4
        track.clipsToBounds = true
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let fill = UIView()
        fill.backgroundColor = color
        fill.layer.cornerRadius = 4
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        NSLayoutConstraint.activate([
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor, multiplier: CGFloat(bar.progress)),
        ])

        let stack = UIStackView(arrangedSubviews: [topRow, track])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func makeTileRow(_ tiles: [UIView]) -> UIView {
        let row = UIStackView(arrangedSubviews: tiles)
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }

    private func makeQuotaTile(_ quota: ConnectTrustReport.Quota) -> UIView {
        let tile = UIView()
        tile.layer.cornerRadius = 12
        tile.layer.cornerCurve = .continuous
        tile.layer.borderWidth = 1
        if quota.isMet {
            tile.backgroundColor = .tertiarySystemGroupedBackground
            tile.layer.borderColor = UIColor.separator.withAlphaComponent(0.4).cgColor
        } else {
            tile.backgroundColor = Palette.danger.withAlphaComponent(0.08)
            tile.layer.borderColor = Palette.danger.withAlphaComponent(0.3).cgColor
        }

        let label = UILabel()
        label.text = quota.label
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel

        let value = UILabel()
        value.text = quota.valueText
        value.font = .systemFont(ofSize: 12, weight: .semibold)
        value.textColor = quota.isMet ? .secondaryLabel : Palette.danger
        value.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [label, value])
        topRow.axis = .horizontal
        topRow.spacing = 6

        let slotsRow = UIStackView(arrangedSubviews: (0 ..< 5).map { index in
            let slot = UIView()
            let used = index < quota.usedSlots
            slot.backgroundColor = used
                ? Palette.danger.withAlphaComponent(0.9)
                : Palette.met.withAlphaComponent(0.2)
            slot.layer.cornerRadius = 3
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            return slot
        })
        slotsRow.axis = .horizontal
        slotsRow.distribution = .fillEqually
        slotsRow.spacing = 4

        let stack = UIStackView(arrangedSubviews: [topRow, slotsRow])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: tile.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -14),
        ])
        return tile
    }

    private func makeVetoTile(_ veto: ConnectTrustReport.Veto) -> UIView {
        let color = veto.isMet ? Palette.met : Palette.danger

        let tile = UIView()
        tile.layer.cornerRadius = 12
        tile.layer.cornerCurve = .continuous
        tile.layer.borderWidth = 1
        tile.backgroundColor = color.withAlphaComponent(0.08)
        tile.layer.borderColor = color.withAlphaComponent(0.25).cgColor

        let icon = UIImageView(image: UIImage(
            systemName: veto.isMet ? "checkmark" : "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        ))
        icon.tintColor = color
        icon.contentMode = .center
        icon.backgroundColor = color.withAlphaComponent(0.15)
        icon.layer.cornerRadius = 14
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
        ])

        let value = UILabel()
        value.text = veto.value
        value.font = .systemFont(ofSize: 22, weight: .semibold)
        value.textColor = color

        let topRow = UIStackView(arrangedSubviews: [icon, UIView(), value])
        topRow.axis = .horizontal
        topRow.alignment = .center

        let label = UILabel()
        label.text = veto.label
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.numberOfLines = 0

        let desc = UILabel()
        desc.text = veto.desc
        desc.font = .systemFont(ofSize: 10)
        desc.textColor = .secondaryLabel
        desc.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [topRow, label, desc])
        stack.axis = .vertical
        stack.spacing = 4
        stack.setCustomSpacing(12, after: topRow)
        stack.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: tile.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: tile.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: tile.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: tile.bottomAnchor, constant: -14),
        ])
        return tile
    }

    private func makeStatusBanner(text: String, isMet: Bool) -> UIView {
        let color = isMet ? Palette.met : Palette.danger
        let banner = UIView()
        banner.backgroundColor = color.withAlphaComponent(0.08)
        banner.layer.cornerRadius = 12
        banner.layer.cornerCurve = .continuous
        banner.layer.borderWidth = 1
        banner.layer.borderColor = color.withAlphaComponent(0.2).cgColor

        let icon = UIImageView(image: UIImage(systemName: isMet ? "checkmark.circle.fill" : "xmark.circle.fill"))
        icon.tintColor = color
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = color
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: banner.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: banner.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -14),
            stack.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
        ])
        return banner
    }

    private func makeFallbackRow(_ item: TrustFallbackRequirement) -> UIView {
        let color = item.isMet ? Palette.met : Palette.pending

        let icon = UIImageView(image: UIImage(
            systemName: item.isMet ? "checkmark.circle.fill" : "circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        ))
        icon.tintColor = color
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = item.label
        label.font = .systemFont(ofSize: 14, weight: .semibold)

        let value = UILabel()
        value.text = item.valueText
        value.font = .systemFont(ofSize: 13, weight: .semibold)
        value.textColor = color
        value.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topRow = UIStackView(arrangedSubviews: [icon, label, value])
        topRow.axis = .horizontal
        topRow.spacing = 8

        let progress = UIProgressView(progressViewStyle: .default)
        progress.progress = Float(item.progress)
        progress.progressTintColor = color
        progress.trackTintColor = .tertiarySystemFill
        progress.layer.cornerRadius = 3
        progress.clipsToBounds = true

        let stack = UIStackView(arrangedSubviews: [topRow, progress])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }
}

// MARK: - Ring view

private final class TrustRingView: UIView {
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let valueLabel = UILabel()
    private let maxLabel = UILabel()
    private let titleLabel = UILabel()
    private let ringContainer = UIView()
    private var progress: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)

        for layer in [trackLayer, progressLayer] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 8
            layer.lineCap = .round
            ringContainer.layer.addSublayer(layer)
        }
        trackLayer.strokeColor = UIColor.tertiarySystemFill.cgColor

        valueLabel.font = .systemFont(ofSize: 16, weight: .bold)
        valueLabel.textAlignment = .center
        maxLabel.font = .systemFont(ofSize: 10)
        maxLabel.textColor = .tertiaryLabel
        maxLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        let centerStack = UIStackView(arrangedSubviews: [valueLabel, maxLabel])
        centerStack.axis = .vertical
        centerStack.translatesAutoresizingMaskIntoConstraints = false
        ringContainer.addSubview(centerStack)
        ringContainer.translatesAutoresizingMaskIntoConstraints = false

        addSubview(ringContainer)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            ringContainer.topAnchor.constraint(equalTo: topAnchor),
            ringContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            ringContainer.widthAnchor.constraint(equalToConstant: 80),
            ringContainer.heightAnchor.constraint(equalToConstant: 80),

            centerStack.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            centerStack.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: ringContainer.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(current: Int, max: Int, label: String, color: UIColor) {
        valueLabel.text = "\(current)"
        maxLabel.text = "/\(max)"
        titleLabel.text = label
        progressLayer.strokeColor = color.cgColor
        progress = max > 0 ? CGFloat(Swift.min(Swift.max(Double(current) / Double(max), 0), 1)) : 0
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = ringContainer.bounds
        guard bounds.width > 0 else { return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = (bounds.width - 8) / 2
        let start = -CGFloat.pi / 2
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: start,
            endAngle: start + 2 * .pi,
            clockwise: true
        )
        trackLayer.frame = bounds
        progressLayer.frame = bounds
        trackLayer.path = path.cgPath
        progressLayer.path = path.cgPath
        progressLayer.strokeEnd = progress
    }
}

// MARK: - Helpers

private final class PaddedLabel: UILabel {
    var contentInsets: UIEdgeInsets = .zero

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }
}
