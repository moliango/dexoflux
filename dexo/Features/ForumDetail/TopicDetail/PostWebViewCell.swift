import UIKit
import SDWebImage

protocol PostCellDelegate: AnyObject {
    func postCell(didTapImageURL url: URL)
    func postCell(didTapLinkURL url: URL)
    func postCell(didTapShowRepliesForPostId postId: Int)
    func postCell(didTapToggleDetails detailsIndex: Int, postId: Int)
    func postCell(didTapReplyToPost post: DiscourseTopicDetail.Post)
    func postCell(didToggleBookmarkForPost post: DiscourseTopicDetail.Post, isBookmarked: Bool)
    func postCell(didTapBoostForPost post: DiscourseTopicDetail.Post)
    func postCell(didTapAvatarForUsername username: String)
    func postCell(didTapReaction reactionId: String, forPost post: DiscourseTopicDetail.Post)
}

final class PostWebViewCell: UITableViewCell {
    static let reuseIdentifier = "PostWebViewCell"
    static let headerHeight: CGFloat = 44
    static let bottomBarHeight: CGFloat = 30

    weak var delegate: PostCellDelegate?
    private var interactiveRegions: [InteractiveRegion] = []
    private var postId: Int = 0
    private var postLink: String?
    private var currentPost: DiscourseTopicDetail.Post?
    private var codeBlockViews: [UIScrollView] = []

    // MARK: - Header UI

    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 16
        iv.backgroundColor = .secondarySystemFill
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let floorLabel: UILabel = {
        let label = UILabel()
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .tertiaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let replyToLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // MARK: - Content

    private let snapshotImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleToFill
        iv.clipsToBounds = true
        iv.isUserInteractionEnabled = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    // MARK: - Bottom Bar

    private let showRepliesButton: UIButton = {
        let button = UIButton(type: .system)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.tintColor = .secondaryLabel
        button.contentHorizontalAlignment = .leading
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        return button
    }()

    private let copyLinkButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let replyButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.setImage(UIImage(systemName: "arrowshape.turn.up.left", withConfiguration: config), for: .normal)
        button.tintColor = .tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var imageViewHeightConstraint: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        contentView.addSubview(avatarImageView)
        contentView.addSubview(usernameLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(floorLabel)
        contentView.addSubview(replyToLabel)
        contentView.addSubview(snapshotImageView)
        contentView.addSubview(showRepliesButton)
        contentView.addSubview(replyButton)
        contentView.addSubview(copyLinkButton)
        contentView.addSubview(separatorLine)

        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            avatarImageView.widthAnchor.constraint(equalToConstant: 32),
            avatarImageView.heightAnchor.constraint(equalToConstant: 32),

            usernameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            usernameLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),

            timeLabel.centerYAnchor.constraint(equalTo: usernameLabel.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: usernameLabel.trailingAnchor, constant: 8),

            replyToLabel.centerYAnchor.constraint(equalTo: floorLabel.centerYAnchor),
            replyToLabel.trailingAnchor.constraint(equalTo: floorLabel.leadingAnchor, constant: -8),

            floorLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            floorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            snapshotImageView.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor),
            snapshotImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            snapshotImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            showRepliesButton.topAnchor.constraint(equalTo: snapshotImageView.bottomAnchor),
            showRepliesButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            showRepliesButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),

            copyLinkButton.topAnchor.constraint(equalTo: snapshotImageView.bottomAnchor),
            copyLinkButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            copyLinkButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            copyLinkButton.widthAnchor.constraint(equalToConstant: 28),
            copyLinkButton.bottomAnchor.constraint(equalTo: separatorLine.topAnchor, constant: -6),

            replyButton.topAnchor.constraint(equalTo: snapshotImageView.bottomAnchor),
            replyButton.trailingAnchor.constraint(equalTo: copyLinkButton.leadingAnchor),
            replyButton.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
            replyButton.widthAnchor.constraint(equalToConstant: 28),

            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        snapshotImageView.addGestureRecognizer(tap)

        showRepliesButton.addTarget(self, action: #selector(repliesButtonTapped), for: .touchUpInside)
        copyLinkButton.addTarget(self, action: #selector(copyLinkTapped), for: .touchUpInside)
        replyButton.addTarget(self, action: #selector(replyButtonTapped), for: .touchUpInside)

        avatarImageView.isUserInteractionEnabled = true
        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarImageView.addGestureRecognizer(avatarTap)
    }

    func configure(
        with post: DiscourseTopicDetail.Post,
        snapshot: UIImage?,
        contentHeight: CGFloat,
        interactiveRegions: [InteractiveRegion],
        codeBlocks: [CodeBlockInfo],
        baseURL: String,
        delegate: PostCellDelegate?,
        floorNumber: Int,
        postLink: String?
    ) {
        self.postId = post.id
        self.postLink = postLink
        self.currentPost = post
        usernameLabel.text = post.username
        timeLabel.text = Self.formatDate(post.createdAt)
        snapshotImageView.image = snapshot
        self.interactiveRegions = interactiveRegions
        self.delegate = delegate

        floorLabel.text = "#\(floorNumber)"

        if let replyUser = post.replyToUser {
            let attachment = NSTextAttachment()
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            attachment.image = UIImage(systemName: "arrowshape.turn.up.left.fill", withConfiguration: symbolConfig)?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
            let attrStr = NSMutableAttributedString(attachment: attachment)
            attrStr.append(NSAttributedString(string: " @\(replyUser.username)"))
            replyToLabel.attributedText = attrStr
            replyToLabel.isHidden = false
        } else {
            replyToLabel.isHidden = true
        }

        let hasReplies = post.replyCount > 0
        showRepliesButton.isHidden = !hasReplies
        if hasReplies {
            showRepliesButton.setTitle(String(localized: "post.replies \(post.replyCount)"), for: .normal)
        }

        imageViewHeightConstraint?.isActive = false
        let hc = snapshotImageView.heightAnchor.constraint(equalToConstant: contentHeight)
        imageViewHeightConstraint = hc
        hc.isActive = true

        // Overlay scrollable code blocks
        setupCodeBlockOverlays(codeBlocks)

        AvatarImageLoader.setImage(
            on: avatarImageView,
            template: post.avatarTemplate,
            baseURL: baseURL,
            size: 96
        )
    }

    // MARK: - Code Block Overlays

    private func setupCodeBlockOverlays(_ codeBlocks: [CodeBlockInfo]) {
        codeBlockViews.forEach { $0.removeFromSuperview() }
        codeBlockViews = []

        let codeFont = UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        let codeBg = UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(white: 0.165, alpha: 1)
            : UIColor(white: 0.957, alpha: 1)
        }

        for block in codeBlocks {
            let sv = UIScrollView(frame: block.frame)
            sv.showsHorizontalScrollIndicator = true
            sv.showsVerticalScrollIndicator = false
            sv.bounces = false
            sv.backgroundColor = codeBg
            sv.layer.cornerRadius = 6
            sv.clipsToBounds = true

            let label = UILabel()
            label.text = block.text
            label.font = codeFont
            label.textColor = .label
            label.numberOfLines = 0
            label.lineBreakMode = .byClipping

            let padding: CGFloat = 10
            let textSize = (block.text as NSString).boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: [.font: codeFont],
                context: nil
            ).size
            label.frame = CGRect(x: padding, y: padding, width: ceil(textSize.width), height: ceil(textSize.height))
            sv.addSubview(label)
            sv.contentSize = CGSize(width: ceil(textSize.width) + padding * 2, height: block.frame.height)

            snapshotImageView.addSubview(sv)
            codeBlockViews.append(sv)
        }
    }

    // MARK: - Tap Handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: snapshotImageView)
        for region in interactiveRegions {
            if region.frame.contains(location) {
                switch region.kind {
                case .image(let url):
                    delegate?.postCell(didTapImageURL: url)
                case .link(let url):
                    delegate?.postCell(didTapLinkURL: url)
                case .details(let index):
                    delegate?.postCell(didTapToggleDetails: index, postId: postId)
                }
                return
            }
        }
    }

    @objc private func repliesButtonTapped() {
        delegate?.postCell(didTapShowRepliesForPostId: postId)
    }

    @objc private func replyButtonTapped() {
        guard let post = currentPost else { return }
        delegate?.postCell(didTapReplyToPost: post)
    }

    @objc private func avatarTapped() {
        guard let username = currentPost?.username else { return }
        delegate?.postCell(didTapAvatarForUsername: username)
    }

    @objc private func copyLinkTapped() {
        guard let link = postLink else { return }
        UIPasteboard.general.string = link
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        copyLinkButton.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
        copyLinkButton.tintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.copyLinkButton.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
            self?.copyLinkButton.tintColor = .tertiaryLabel
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        snapshotImageView.image = nil
        interactiveRegions = []
        delegate = nil
        postId = 0
        postLink = nil
        currentPost = nil
        usernameLabel.text = nil
        timeLabel.text = nil
        floorLabel.text = nil
        replyToLabel.attributedText = nil
        replyToLabel.text = nil
        replyToLabel.isHidden = true
        showRepliesButton.isHidden = true
        avatarImageView.sd_cancelCurrentImageLoad()
        avatarImageView.image = nil
        codeBlockViews.forEach { $0.removeFromSuperview() }
        codeBlockViews = []
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        copyLinkButton.setImage(UIImage(systemName: "link", withConfiguration: config), for: .normal)
        copyLinkButton.tintColor = .tertiaryLabel
    }

    private static func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else { return isoString }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
