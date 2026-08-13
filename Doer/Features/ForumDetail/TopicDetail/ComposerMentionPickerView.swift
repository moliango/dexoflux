import SDWebImage
import UIKit

/// Floating @-mention candidate list shown above the composer caret.
final class ComposerMentionPickerView: UIView {
    var onSelect: ((DiscourseMentionUser) -> Void)?

    private var users: [DiscourseMentionUser] = []
    private var baseURL: String = ""

    private let tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = 52
        table.showsVerticalScrollIndicator = false
        table.keyboardDismissMode = .none
        table.alwaysBounceVertical = false
        return table
    }()

    private var heightConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = true
        backgroundColor = UIColor.secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)
        // Keep above the text view for hit-testing while typing.
        layer.zPosition = 50
        clipsToBounds = false

        let clip = UIView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.backgroundColor = .clear
        clip.layer.cornerRadius = 16
        clip.layer.cornerCurve = .continuous
        clip.clipsToBounds = true
        clip.isUserInteractionEnabled = true
        addSubview(clip)
        clip.addSubview(tableView)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsSelection = true
        tableView.delaysContentTouches = false
        tableView.canCancelContentTouches = false
        tableView.register(ComposerMentionCell.self, forCellReuseIdentifier: ComposerMentionCell.reuseID)

        let height = heightAnchor.constraint(equalToConstant: 0)
        heightConstraint = height

        NSLayoutConstraint.activate([
            height,
            widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            clip.topAnchor.constraint(equalTo: topAnchor),
            clip.leadingAnchor.constraint(equalTo: leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: trailingAnchor),
            clip.bottomAnchor.constraint(equalTo: bottomAnchor),

            tableView.topAnchor.constraint(equalTo: clip.topAnchor, constant: 6),
            tableView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: clip.bottomAnchor, constant: -6),
        ])

        isHidden = true
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(baseURL: String) {
        self.baseURL = baseURL
    }

    func update(users: [DiscourseMentionUser], animated: Bool = true) {
        self.users = users
        tableView.reloadData()

        let rowCount = min(users.count, 6)
        let contentHeight = CGFloat(rowCount) * tableView.rowHeight + 12
        heightConstraint?.constant = users.isEmpty ? 0 : contentHeight

        let shouldShow = !users.isEmpty
        if shouldShow == !isHidden, alpha == (shouldShow ? 1 : 0) {
            return
        }

        if shouldShow {
            isHidden = false
        }
        let changes = {
            self.alpha = shouldShow ? 1 : 0
            self.transform = shouldShow ? .identity : CGAffineTransform(translationX: 0, y: -4)
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                changes()
            } completion: { _ in
                if !shouldShow {
                    self.isHidden = true
                }
            }
        } else {
            changes()
            if !shouldShow {
                isHidden = true
            }
        }
    }

    func hide(animated: Bool = true) {
        update(users: [], animated: animated)
    }
}

extension ComposerMentionPickerView: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        users.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: ComposerMentionCell.reuseID,
            for: indexPath
        ) as! ComposerMentionCell
        cell.configure(user: users[indexPath.row], baseURL: baseURL)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard users.indices.contains(indexPath.row) else { return }
        onSelect?(users[indexPath.row])
    }
}

private final class ComposerMentionCell: UITableViewCell {
    static let reuseID = "ComposerMentionCell"

    private let avatarView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 16
        view.backgroundColor = .tertiarySystemFill
        return view
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let textStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        return stack
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .default
        contentView.addSubview(avatarView)
        textStack.addArrangedSubview(usernameLabel)
        textStack.addArrangedSubview(nameLabel)
        contentView.addSubview(textStack)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            textStack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            textStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            textStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Cancel in-flight SD loads so recycled cells don't flash wrong avatars.
        avatarView.sd_cancelCurrentImageLoad()
        avatarView.image = nil
        usernameLabel.text = nil
        nameLabel.text = nil
        nameLabel.isHidden = false
    }

    func configure(user: DiscourseMentionUser, baseURL: String) {
        usernameLabel.text = "@\(user.username)"
        let trimmedName = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedName.isEmpty || trimmedName.caseInsensitiveCompare(user.username) == .orderedSame {
            nameLabel.isHidden = true
            nameLabel.text = nil
        } else {
            nameLabel.isHidden = false
            nameLabel.text = trimmedName
        }

        // Reuse the app-wide avatar pipeline (memory + disk + CF cookie context)
        // with the same pixel size as home/topic lists so keys hit warm cache.
        AvatarImageLoader.setImage(
            on: avatarView,
            template: user.avatarTemplate,
            baseURL: baseURL,
            size: AvatarImageLoader.primaryAvatarPixelSize,
            placeholder: AvatarImageLoader.defaultPlaceholder
        )
    }
}
