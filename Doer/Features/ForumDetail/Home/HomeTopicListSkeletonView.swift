import UIKit

final class HomeTopicListSkeletonView: DexoSkeletonPlaceholderView {
    private var cardSurfaces: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        skeletonContentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: skeletonContentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: skeletonContentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor, constant: -10),
        ])

        for _ in 0 ..< 7 {
            stack.addArrangedSubview(makeTopicRow())
        }
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        applySkeletonTheme(
            backgroundColor: themeStyle.topicListBackgroundColor,
            blockColor: themeStyle.accentColor.withAlphaComponent(0.12)
        )
        cardSurfaces.forEach {
            $0.backgroundColor = themeStyle.topicCardBackgroundColor
            $0.layer.borderColor = UIColor.separator.withAlphaComponent(0.18).cgColor
        }
    }

    private func makeTopicRow() -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0.5
        cardSurfaces.append(card)

        let title = makeSkeletonBlock(cornerRadius: 5)
        let titleShort = makeSkeletonBlock(cornerRadius: 5)
        let avatar = makeSkeletonBlock(cornerRadius: 16)
        let meta = makeSkeletonBlock(cornerRadius: 4)
        let count = makeSkeletonBlock(cornerRadius: 8)

        container.addSubview(card)
        [title, titleShort, avatar, meta, count].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 104),

            card.topAnchor.constraint(equalTo: container.topAnchor),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -70),
            title.heightAnchor.constraint(equalToConstant: 16),

            titleShort.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            titleShort.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            titleShort.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -118),
            titleShort.heightAnchor.constraint(equalToConstant: 16),

            avatar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            avatar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32),

            meta.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            meta.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            meta.widthAnchor.constraint(equalToConstant: 148),
            meta.heightAnchor.constraint(equalToConstant: 12),

            count.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            count.centerYAnchor.constraint(equalTo: avatar.centerYAnchor),
            count.widthAnchor.constraint(equalToConstant: 46),
            count.heightAnchor.constraint(equalToConstant: 20),
        ])

        return container
    }
}
