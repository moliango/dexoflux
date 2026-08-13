import UIKit

final class SkeletonBlockView: UIView {
    init(cornerRadius: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.secondarySystemFill.withAlphaComponent(0.8)
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimating() {}

    func stopAnimating() {}
}

import UIKit

final class TopicDetailSkeletonView: DoerSkeletonPlaceholderView {
    private var cardSurfaces: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        skeletonContentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: skeletonContentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: skeletonContentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: skeletonContentView.trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: skeletonContentView.bottomAnchor),
        ])

        stack.addArrangedSubview(makeTitleCard())
        for _ in 0 ..< 4 {
            stack.addArrangedSubview(makePostCard())
        }
        applyThemeStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyThemeStyle() {
        let themeStyle = AppSettings.shared.themeStyle
        // Chat detail (WeChat / Telegram) uses canvas color so skeleton matches the page.
        let background = ChatTopicStyle.current?.chatBackgroundColor ?? themeStyle.topicListBackgroundColor
        let block = ChatTopicStyle.current != nil
            ? UIColor.label.withAlphaComponent(0.10)
            : themeStyle.accentColor.withAlphaComponent(0.12)
        applySkeletonTheme(backgroundColor: background, blockColor: block)
        cardSurfaces.forEach {
            $0.backgroundColor = themeStyle.topicCardBackgroundColor
            $0.layer.borderColor = UIColor.separator.withAlphaComponent(0.20).cgColor
        }
    }

    private func makeCard(height: CGFloat, cornerRadius: CGFloat = 16) -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = cornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0.5
        cardSurfaces.append(card)
        card.heightAnchor.constraint(equalToConstant: height).isActive = true
        return card
    }

    private func makeTitleCard() -> UIView {
        let card = makeCard(height: 118)
        let title = makeSkeletonBlock(cornerRadius: 6)
        let titleShort = makeSkeletonBlock(cornerRadius: 6)
        let chipOne = makeSkeletonBlock(cornerRadius: 11)
        let chipTwo = makeSkeletonBlock(cornerRadius: 11)
        let meta = makeSkeletonBlock(cornerRadius: 5)

        [title, titleShort, chipOne, chipTwo, meta].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -26),
            title.heightAnchor.constraint(equalToConstant: 20),

            titleShort.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 9),
            titleShort.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            titleShort.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -94),
            titleShort.heightAnchor.constraint(equalToConstant: 20),

            chipOne.topAnchor.constraint(equalTo: titleShort.bottomAnchor, constant: 14),
            chipOne.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            chipOne.widthAnchor.constraint(equalToConstant: 72),
            chipOne.heightAnchor.constraint(equalToConstant: 22),

            chipTwo.leadingAnchor.constraint(equalTo: chipOne.trailingAnchor, constant: 8),
            chipTwo.centerYAnchor.constraint(equalTo: chipOne.centerYAnchor),
            chipTwo.widthAnchor.constraint(equalToConstant: 56),
            chipTwo.heightAnchor.constraint(equalTo: chipOne.heightAnchor),

            meta.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            meta.topAnchor.constraint(equalTo: chipOne.bottomAnchor, constant: 12),
            meta.widthAnchor.constraint(equalToConstant: 188),
            meta.heightAnchor.constraint(equalToConstant: 12),
        ])

        return card
    }

    private func makePostCard() -> UIView {
        let card = makeCard(height: 132)
        let avatar = makeSkeletonBlock(cornerRadius: 16)
        let name = makeSkeletonBlock(cornerRadius: 5)
        let time = makeSkeletonBlock(cornerRadius: 4)
        let lineOne = makeSkeletonBlock(cornerRadius: 5)
        let lineTwo = makeSkeletonBlock(cornerRadius: 5)
        let lineThree = makeSkeletonBlock(cornerRadius: 5)
        let actionOne = makeSkeletonBlock(cornerRadius: 10)
        let actionTwo = makeSkeletonBlock(cornerRadius: 10)

        [avatar, name, time, lineOne, lineTwo, lineThree, actionOne, actionTwo].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            avatar.widthAnchor.constraint(equalToConstant: 32),
            avatar.heightAnchor.constraint(equalToConstant: 32),

            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            name.topAnchor.constraint(equalTo: avatar.topAnchor, constant: 2),
            name.widthAnchor.constraint(equalToConstant: 126),
            name.heightAnchor.constraint(equalToConstant: 14),

            time.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            time.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 7),
            time.widthAnchor.constraint(equalToConstant: 82),
            time.heightAnchor.constraint(equalToConstant: 11),

            lineOne.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            lineOne.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            lineOne.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 18),
            lineOne.heightAnchor.constraint(equalToConstant: 13),

            lineTwo.leadingAnchor.constraint(equalTo: lineOne.leadingAnchor),
            lineTwo.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -52),
            lineTwo.topAnchor.constraint(equalTo: lineOne.bottomAnchor, constant: 9),
            lineTwo.heightAnchor.constraint(equalToConstant: 13),

            lineThree.leadingAnchor.constraint(equalTo: lineOne.leadingAnchor),
            lineThree.widthAnchor.constraint(equalToConstant: 190),
            lineThree.topAnchor.constraint(equalTo: lineTwo.bottomAnchor, constant: 9),
            lineThree.heightAnchor.constraint(equalToConstant: 13),

            actionOne.leadingAnchor.constraint(equalTo: lineOne.leadingAnchor),
            actionOne.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
            actionOne.widthAnchor.constraint(equalToConstant: 52),
            actionOne.heightAnchor.constraint(equalToConstant: 20),

            actionTwo.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            actionTwo.centerYAnchor.constraint(equalTo: actionOne.centerYAnchor),
            actionTwo.widthAnchor.constraint(equalToConstant: 84),
            actionTwo.heightAnchor.constraint(equalTo: actionOne.heightAnchor),
        ])

        return card
    }
}
