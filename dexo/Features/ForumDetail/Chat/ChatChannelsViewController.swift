import UIKit

/// FluxDo-style site chat: channel list + open room.
final class ChatChannelsViewController: ObservableViewController {
    private let api: DiscourseAPI
    private var channels: [DiscourseChatChannel] = []
    private var isLoading = false
    private var errorMessage: String?

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "chat.channel")
        table.refreshControl = UIRefreshControl()
        table.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        return table
    }()

    private let emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .body)
        label.isHidden = true
        return label
    }()

    init(api: DiscourseAPI) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "chat.title", defaultValue: "站内聊天")
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tableView)
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
        Task { await loadChannels() }
    }

    override func updateUI() {
        tableView.reloadData()
        tableView.refreshControl?.endRefreshing()
        if isLoading && channels.isEmpty {
            emptyLabel.isHidden = true
        } else if let errorMessage {
            emptyLabel.isHidden = false
            emptyLabel.text = errorMessage
        } else if channels.isEmpty {
            emptyLabel.isHidden = false
            emptyLabel.text = String(localized: "chat.empty", defaultValue: "暂无聊天频道（站点可能未开启 Chat）")
        } else {
            emptyLabel.isHidden = true
        }
    }

    @objc private func refresh() {
        Task { await loadChannels() }
    }

    private func loadChannels() async {
        isLoading = true
        errorMessage = nil
        updateUI()
        do {
            let response = try await api.fetchChatChannels()
            channels = response.all.sorted {
                ($0.unreadCount, $0.displayTitle) > ($1.unreadCount, $1.displayTitle)
            }
        } catch {
            errorMessage = error.localizedDescription
            channels = []
        }
        isLoading = false
        updateUI()
    }
}

extension ChatChannelsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        channels.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat.channel", for: indexPath)
        let channel = channels[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = channel.displayTitle
        if channel.unreadCount > 0 {
            content.secondaryText = String(
                format: String(localized: "chat.unread_count", defaultValue: "%d 条未读"),
                channel.unreadCount
            )
        } else {
            content.secondaryText = channel.lastMessageSentAt
        }
        content.image = UIImage(systemName: "bubble.left.and.bubble.right.fill")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let channel = channels[indexPath.row]
        navigationController?.pushViewController(
            ChatRoomViewController(api: api, channel: channel),
            animated: true
        )
    }
}

final class ChatRoomViewController: ObservableViewController, UITableViewDataSource, UITextFieldDelegate {
    private let api: DiscourseAPI
    private let channel: DiscourseChatChannel
    private var messages: [DiscourseChatMessage] = []
    private var isLoading = false
    private var isSending = false

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "chat.msg")
        table.keyboardDismissMode = .interactive
        table.separatorStyle = .none
        return table
    }()

    private let inputField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .roundedRect
        field.placeholder = String(localized: "chat.input_placeholder", defaultValue: "输入消息…")
        field.returnKeyType = .send
        return field
    }()

    private let sendButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = String(localized: "reply.send")
        config.cornerStyle = .capsule
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    init(api: DiscourseAPI, channel: DiscourseChatChannel) {
        self.api = api
        self.channel = channel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = channel.displayTitle
        view.backgroundColor = .systemBackground
        inputField.delegate = self
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        let bar = UIStackView(arrangedSubviews: [inputField, sendButton])
        bar.axis = .horizontal
        bar.spacing = 8
        bar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tableView)
        view.addSubview(bar)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),

            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 72),
            bar.heightAnchor.constraint(equalToConstant: 40),
        ])
        Task { await loadMessages() }
    }

    override func updateUI() {
        tableView.reloadData()
        sendButton.isEnabled = !isSending
        inputField.isEnabled = !isSending
        if !messages.isEmpty {
            let last = IndexPath(row: messages.count - 1, section: 0)
            tableView.scrollToRow(at: last, at: .bottom, animated: false)
        }
    }

    private func loadMessages() async {
        isLoading = true
        do {
            messages = try await api.fetchChatMessages(channelId: channel.id)
        } catch {
            DexoFeedback.presentToast(error.localizedDescription, on: self)
            messages = []
        }
        isLoading = false
        updateUI()
    }

    @objc private func sendTapped() {
        let text = (inputField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        updateUI()
        Task { @MainActor in
            do {
                try await api.sendChatMessage(channelId: channel.id, message: text)
                inputField.text = ""
                await loadMessages()
            } catch {
                DexoFeedback.presentToast(error.localizedDescription, on: self)
            }
            isSending = false
            updateUI()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat.msg", for: indexPath)
        let msg = messages[indexPath.row]
        var content = cell.defaultContentConfiguration()
        let user = msg.user?.username ?? msg.user?.name ?? "…"
        content.text = user
        content.secondaryText = msg.displayBody
        content.textProperties.font = .preferredFont(forTextStyle: .caption1)
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.color = .label
        cell.contentConfiguration = content
        cell.selectionStyle = .none
        return cell
    }
}
