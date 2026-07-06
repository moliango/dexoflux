import UIKit

final class AddForumViewController: ObservableViewController {
    var onForumAdded: (() -> Void)?

    private let viewModel = AddForumViewModel()

    private let urlTextField: UITextField = {
        let tf = UITextField()
        tf.placeholder = "https://forum.example.com"
        tf.borderStyle = .roundedRect
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.keyboardType = .URL
        tf.returnKeyType = .done
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()

    private let addButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "add_forum.button")
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.hidesWhenStopped = true
        ai.translatesAutoresizingMaskIntoConstraints = false
        return ai
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "add_forum.title")
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        view.addSubview(urlTextField)
        view.addSubview(addButton)
        view.addSubview(activityIndicator)
        view.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            urlTextField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            urlTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            urlTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            urlTextField.heightAnchor.constraint(equalToConstant: 44),

            addButton.topAnchor.constraint(equalTo: urlTextField.bottomAnchor, constant: 16),
            addButton.leadingAnchor.constraint(equalTo: urlTextField.leadingAnchor),
            addButton.trailingAnchor.constraint(equalTo: urlTextField.trailingAnchor),
            addButton.heightAnchor.constraint(equalToConstant: 44),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: addButton.bottomAnchor, constant: 16),

            errorLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: urlTextField.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: urlTextField.trailingAnchor),
        ])

        addButton.addTarget(self, action: #selector(addTapped), for: .touchUpInside)
        urlTextField.delegate = self
    }

    override func updateUI() {
        addButton.isEnabled = !viewModel.isLoading
        urlTextField.isEnabled = !viewModel.isLoading
        errorLabel.text = viewModel.errorMessage

        if viewModel.isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func addTapped() {
        viewModel.urlString = urlTextField.text ?? ""
        Task {
            let success = await viewModel.addForum()
            if success {
                onForumAdded?()
                dismiss(animated: true)
            }
        }
    }
}

extension AddForumViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        addTapped()
        return true
    }
}
