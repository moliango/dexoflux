import UIKit
import WebKit

final class MermaidViewerViewController: UIViewController {
    private let source: String
    private let webView = WKWebView(frame: .zero)
    private let textView = UITextView()

    init(source: String) {
        self.source = source
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Mermaid"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "common.done", defaultValue: "完成"),
            style: .done,
            target: self,
            action: #selector(close)
        )
        webView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.text = source
        textView.isHidden = true
        view.addSubview(webView)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        loadMermaid()
    }

    @objc private func close() { dismiss(animated: true) }

    private func loadMermaid() {
        let escaped = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script type="module">
          import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
          mermaid.initialize({ startOnLoad: false, theme: 'neutral' });
          try {
            const out = await mermaid.render('mmd', `\(escaped)`);
            document.getElementById('root').innerHTML = out.svg;
          } catch (e) {
            document.getElementById('root').innerText = 'Render failed: ' + e;
          }
        </script>
        </head><body style="margin:12px;font-family:-apple-system">
        <div id="root">Rendering…</div>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net"))
    }
}
