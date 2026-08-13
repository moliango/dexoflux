import UIKit

final class DohDebugLogViewController: UIViewController {
    private lazy var textView: UITextView = {
        let view = UITextView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.textColor = .label
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.isEditable = false
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "settings.about.app_logs", defaultValue: "应用日志")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "复制",
            style: .plain,
            target: self,
            action: #selector(copyLog)
        )

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
        reloadLog()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enableSettingsInteractiveBackSwipe()
        reloadLog()
    }

    private func reloadLog() {
        let log = DohDebugLog.snapshot()
        textView.text = log.isEmpty ? "暂无调试日志。刷新首页或重试网络请求。" : log
        if !textView.text.isEmpty {
            let length = (textView.text as NSString).length
            let bottom = NSRange(location: max(length - 1, 0), length: 1)
            textView.scrollRangeToVisible(bottom)
        }
    }

    @objc private func copyLog() {
        let log = DohDebugLog.snapshot()
        UIPasteboard.general.string = log.isEmpty ? textView.text : log
        let alert = UIAlertController(title: nil, message: "日志已复制", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok"), style: .default))
        present(alert, animated: true)
    }
}
