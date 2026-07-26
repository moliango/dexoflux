import UIKit
import WebKit

final class PostRevisionViewController: UIViewController {
    private let api: DiscourseAPI
    private let postId: Int
    private var revision: DiscoursePostRevision?
    private let webView = WKWebView(frame: .zero)
    private let metaLabel = UILabel()
    private let loading = UIActivityIndicatorView(style: .medium)

    init(api: DiscourseAPI, postId: Int) {
        self.api = api
        self.postId = postId
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "revision.title", defaultValue: "编辑历史")
        view.backgroundColor = .systemBackground
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        metaLabel.font = .preferredFont(forTextStyle: .footnote)
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 0
        webView.translatesAutoresizingMaskIntoConstraints = false
        loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(metaLabel)
        view.addSubview(webView)
        view.addSubview(loading)
        NSLayoutConstraint.activate([
            metaLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            metaLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            metaLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            webView.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: String(localized: "common.done", defaultValue: "完成"), style: .done, target: self, action: #selector(close))
        loadLatest()
    }

    @objc private func close() { dismiss(animated: true) }

    private func loadLatest() {
        loading.startAnimating()
        Task {
            do {
                let rev = try await api.fetchPostRevision(postId: postId, revision: "latest")
                await MainActor.run {
                    self.loading.stopAnimating()
                    self.revision = rev
                    let user = rev.username.map { "@\($0)" } ?? ""
                    let ver = rev.currentRevision.map(String.init) ?? "?"
                    self.metaLabel.text = "\(user) · rev \(ver) · \(rev.createdAt ?? "")"
                    let html = """
                    <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
                    <style>body{font-family:-apple-system;padding:12px;color:#111} ins{background:#d4fcbc} del{background:#fbb6c2}</style>
                    </head><body>\(rev.displayHTML)</body></html>
                    """
                    self.webView.loadHTMLString(html, baseURL: nil)
                }
            } catch {
                await MainActor.run {
                    self.loading.stopAnimating()
                    self.metaLabel.text = error.localizedDescription
                }
            }
        }
    }
}
