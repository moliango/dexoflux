import UIKit

enum DiscourseFontAwesomeIcon {
    static let fontName = "FontAwesome5Free-Solid"

    private static let supportedCharacterSet: CharacterSet? = {
        UIFont(name: fontName, size: 12)?
            .fontDescriptor
            .object(forKey: .characterSet) as? CharacterSet
    }()

    private static let solidGlyphs: [String: String] = [
        "arrow-pointer": "\u{f245}",
        "award": "\u{f559}",
        "blog": "\u{f781}",
        "book": "\u{f02d}",
        "book-open": "\u{f518}",
        "book-open-reader": "\u{f5da}",
        "bookmark": "\u{f02e}",
        "brain": "\u{f5dc}",
        "briefcase": "\u{f0b1}",
        "bug": "\u{f188}",
        "bullhorn": "\u{f0a1}",
        "bullseye": "\u{f140}",
        "calculator": "\u{f1ec}",
        "camera": "\u{f030}",
        "car": "\u{f1b9}",
        "certificate": "\u{f0a3}",
        "check": "\u{f00c}",
        "check-circle": "\u{f058}",
        "circle-question": "\u{f059}",
        "clone": "\u{f24d}",
        "code": "\u{f121}",
        "coins": "\u{f51e}",
        "comment": "\u{f075}",
        "comment-dollar": "\u{f651}",
        "comments": "\u{f086}",
        "crosshairs": "\u{f05b}",
        "database": "\u{f1c0}",
        "droplet": "\u{f043}",
        "droplet-slash": "\u{f5c7}",
        "ethernet": "\u{f796}",
        "eye": "\u{f06e}",
        "face-smile": "\u{f118}",
        "faucet": "\u{e005}",
        "file-code": "\u{f1c9}",
        "fire": "\u{f06d}",
        "flame": "\u{f06d}",
        "fist-raised": "\u{f6de}",
        "folder": "\u{f07b}",
        "gavel": "\u{f0e3}",
        "gamepad": "\u{f11b}",
        "gem": "\u{f3a5}",
        "graduation-cap": "\u{f19d}",
        "hand-holding-dollar": "\u{f4c0}",
        "hammer": "\u{f6e3}",
        "hand": "\u{f256}",
        "hand-fist": "\u{f6de}",
        "hand-paper": "\u{f256}",
        "hand-rock": "\u{f255}",
        "hands-praying": "\u{f684}",
        "hard-drive": "\u{f0a0}",
        "heart": "\u{f004}",
        "heart-pulse": "\u{f21e}",
        "headset": "\u{f590}",
        "laptop-code": "\u{f5fc}",
        "lightbulb": "\u{f0eb}",
        "magnifying-glass": "\u{f002}",
        "medal": "\u{f5a2}",
        "microchip": "\u{f2db}",
        "music": "\u{f001}",
        "network-wired": "\u{f6ff}",
        "newspaper": "\u{f1ea}",
        "palette": "\u{f53f}",
        "people-group": "\u{f0c0}",
        "pepper-hot": "\u{f816}",
        "piggy-bank": "\u{f4d3}",
        "radiation": "\u{f7b9}",
        "receipt": "\u{f543}",
        "route": "\u{f4d7}",
        "rocket": "\u{f135}",
        "rss": "\u{f09e}",
        "search": "\u{f002}",
        "seedling": "\u{f4d8}",
        "server": "\u{f233}",
        "share": "\u{f064}",
        "shield": "\u{f3ed}",
        "shield-alt": "\u{f3ed}",
        "shield-halved": "\u{f3ed}",
        "shuffle": "\u{f074}",
        "spider": "\u{f717}",
        "square-share-nodes": "\u{f1e1}",
        "star": "\u{f005}",
        "tag": "\u{f02b}",
        "target": "\u{f140}",
        "terminal": "\u{f120}",
        "thumbs-down": "\u{f165}",
        "thumbs-up": "\u{f164}",
        "tree": "\u{f1bb}",
        "triangle-exclamation": "\u{f071}",
        "trophy": "\u{f091}",
        "user": "\u{f007}",
        "user-check": "\u{f4fc}",
        "user-graduate": "\u{f501}",
        "user-injured": "\u{f728}",
        "user-secret": "\u{f21b}",
        "user-shield": "\u{f505}",
        "user-slash": "\u{f506}",
        "user-tag": "\u{f507}",
        "users": "\u{f0c0}",
        "venus": "\u{f221}",
        "video": "\u{f03d}",
        "wrench": "\u{f0ad}",
    ]

    static func glyph(for icon: String?) -> String? {
        guard let rawIcon = icon?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !rawIcon.isEmpty
        else { return nil }

        let normalizedIcon = rawIcon
            .replacingOccurrences(of: "fa-solid", with: "fas")
            .replacingOccurrences(of: "fa-regular", with: "far")
            .replacingOccurrences(of: "fa-brands", with: "fab")
        let components = normalizedIcon
            .split(whereSeparator: { $0 == " " || $0 == "." })
            .map(String.init)

        let candidates = ([normalizedIcon] + components).map { component in
            component
                .replacingOccurrences(of: "fa-", with: "")
                .replacingOccurrences(of: "fas-", with: "")
                .replacingOccurrences(of: "far-", with: "")
                .replacingOccurrences(of: "fab-", with: "")
                .replacingOccurrences(of: "fas ", with: "")
                .replacingOccurrences(of: "far ", with: "")
                .replacingOccurrences(of: "fab ", with: "")
                .replacingOccurrences(of: "fa ", with: "")
                .replacingOccurrences(of: "_", with: "-")
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        }

        for candidate in candidates where !candidate.isEmpty {
            if let glyph = solidGlyphs[solidAlias(for: candidate)], supports(glyph) {
                return glyph
            }
        }
        return nil
    }

    static func image(for icon: String?, color: UIColor, size: CGFloat) -> UIImage? {
        guard size > 0,
              let glyph = glyph(for: icon),
              let font = UIFont(name: fontName, size: size)
        else { return nil }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return renderer.image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let textSize = glyph.size(withAttributes: attributes)
            glyph.draw(
                at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2),
                withAttributes: attributes
            )
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func solidAlias(for icon: String) -> String {
        let normalized = icon
            .replacingOccurrences(of: "_", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        switch normalized {
        case "book-reader":
            return "book-open-reader"
        case "eye-low-vision":
            return "eye"
        case "fire-flame-curved", "fire-flame-simple":
            return "fire"
        case "hand-back-fist":
            return "hand-rock"
        case "hand-holding-usd":
            return "hand-holding-dollar"
        case "hdd":
            return "hard-drive"
        case "magnifying-glass", "magnifying-glass-arrow-right", "magnifying-glass-chart",
             "magnifying-glass-dollar", "magnifying-glass-location", "magnifying-glass-minus",
             "magnifying-glass-plus":
            return "search"
        case "people-arrows", "people-carry-box", "people-group", "people-line",
             "people-pulling", "people-roof", "user-group", "users-between-lines",
             "users-gear", "users-line", "users-rays", "users-rectangle", "users-viewfinder":
            return "users"
        case "shield-halved", "shield-heart", "shield-virus":
            return "shield-alt"
        case "solid-bookmark":
            return "bookmark"
        case "solid-comment":
            return "comment"
        case "solid-comments":
            return "comments"
        case "solid-eye":
            return "eye"
        case "solid-gem":
            return "gem"
        case "solid-hand", "hand":
            return "hand-paper"
        case "solid-hand-back-fist", "hand-fist":
            return "fist-raised"
        case "solid-hand-point-down", "solid-hand-point-left", "solid-hand-point-right",
             "solid-hand-point-up", "hand-point-down", "hand-point-left", "hand-point-right",
             "hand-point-up":
            return "hand"
        case "solid-heart":
            return "heart"
        case "solid-lightbulb":
            return "lightbulb"
        case "mouse-pointer":
            return "arrow-pointer"
        case "praying-hands":
            return "hands-praying"
        case "question-circle":
            return "circle-question"
        case "random":
            return "shuffle"
        case "share-alt-square":
            return "square-share-nodes"
        case "solid-star":
            return "star"
        case "solid-thumbs-down":
            return "thumbs-down"
        case "solid-thumbs-up":
            return "thumbs-up"
        case "tint":
            return "droplet"
        case "tint-slash":
            return "droplet-slash"
        default:
            return normalized
        }
    }

    private static func supports(_ glyph: String) -> Bool {
        guard let supportedCharacterSet else { return true }
        return glyph.unicodeScalars.allSatisfy(supportedCharacterSet.contains)
    }
}

struct TopicTagIconPresentation: Equatable {
    let iconName: String
    let colorHex: String
}

enum TopicTagIconCatalog {
    private static let presentations: [String: TopicTagIconPresentation] = [
        "公告": .init(iconName: "bullhorn", colorHex: "00aeff"),
        "精华神帖": .init(iconName: "thumbs-up", colorHex: "00aeff"),
        "快问快答": .init(iconName: "circle-question", colorHex: "669d34"),
        "nsfw": .init(iconName: "triangle-exclamation", colorHex: "f7941d"),
        "文档": .init(iconName: "book", colorHex: "75b6d7"),
        "碎碎碎念": .init(iconName: "droplet", colorHex: "00aeff"),
        "病友": .init(iconName: "user-injured", colorHex: "f7941d"),
        "人工智能": .init(iconName: "brain", colorHex: "bd93f9"),
        "游戏": .init(iconName: "gamepad", colorHex: "669d34"),
        "职场": .init(iconName: "briefcase", colorHex: "669d34"),
        "拼车": .init(iconName: "car", colorHex: "669d34"),
        "网络安全": .init(iconName: "user-secret", colorHex: "ff1111"),
        "金融经济": .init(iconName: "hand-holding-dollar", colorHex: "669d34"),
        "赏金任务": .init(iconName: "comment-dollar", colorHex: "669d34"),
        "音乐": .init(iconName: "music", colorHex: "669d34"),
        "影视": .init(iconName: "video", colorHex: "669d34"),
        "旅行": .init(iconName: "route", colorHex: "669d34"),
        "美食": .init(iconName: "pepper-hot", colorHex: "669d34"),
        "二次元": .init(iconName: "venus", colorHex: "669d34"),
        "动漫": .init(iconName: "face-smile", colorHex: "669d34"),
        "软件开发": .init(iconName: "file-code", colorHex: "669d34"),
        "配置优化": .init(iconName: "terminal", colorHex: "669d34"),
        "软件测试": .init(iconName: "bug", colorHex: "669d34"),
        "软件调试": .init(iconName: "spider", colorHex: "669d34"),
        "vps": .init(iconName: "server", colorHex: "669d34"),
        "硬件开发": .init(iconName: "file-code", colorHex: "669d34"),
        "硬件测试": .init(iconName: "bug", colorHex: "669d34"),
        "硬件调试": .init(iconName: "spider", colorHex: "669d34"),
        "摄影": .init(iconName: "camera", colorHex: "669d34"),
        "嵌入式": .init(iconName: "microchip", colorHex: "669d34"),
        "健身": .init(iconName: "heart-pulse", colorHex: "669d34"),
        "算法": .init(iconName: "calculator", colorHex: "669d34"),
        "抽奖": .init(iconName: "shuffle", colorHex: "f7941d"),
        "aff": .init(iconName: "arrow-pointer", colorHex: "f7941d"),
        "订阅节点": .init(iconName: "network-wired", colorHex: "669d34"),
        "数据库": .init(iconName: "database", colorHex: "669d34"),
        "计算机网络": .init(iconName: "ethernet", colorHex: "669d34"),
        "纯水": .init(iconName: "faucet", colorHex: "f7941d"),
        "求资源": .init(iconName: "hands-praying", colorHex: "669d34"),
        "禁水": .init(iconName: "droplet-slash", colorHex: "ff5555"),
        "树洞": .init(iconName: "tree", colorHex: "669d34"),
        "危险": .init(iconName: "radiation", colorHex: "ff1111"),
        "封禁": .init(iconName: "user-slash", colorHex: "ff4444"),
        "livestream": .init(iconName: "headset", colorHex: "00aeff"),
        "转载": .init(iconName: "share", colorHex: "669d34"),
        "推广": .init(iconName: "receipt", colorHex: "669d34"),
        "高级推广": .init(iconName: "coins", colorHex: "f5bf03"),
        "公益推广": .init(iconName: "receipt", colorHex: "669d34"),
        "优质博文": .init(iconName: "blog", colorHex: "00aeff"),
        "作品集": .init(iconName: "palette", colorHex: "669d34"),
        "原创": .init(iconName: "lightbulb", colorHex: "00aeff"),
        "集中帖": .init(iconName: "people-group", colorHex: "00aeff"),
    ]

    static func presentation(for tagName: String) -> TopicTagIconPresentation? {
        let normalized = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return presentations[normalized]
    }

    static var allPresentations: [String: TopicTagIconPresentation] {
        presentations
    }
}

enum LinuxDoCategoryCatalog {
    private static let categoriesById: [Int: DiscourseCategory] = {
        let categories = [
            category(id: 1, name: "未分类", slug: "", color: "0088CC", icon: nil),
            category(id: 4, name: "开发调优", slug: "develop", color: "32c3c3", icon: "code", logo: "//linuxdo-uploads.s3.ldstatic.com/original/3X/c/5/c59e612cafa47255927d8c73f90e8dac05f78b5c.png"),
            category(id: 98, name: "国产替代", slug: "domestic", color: "D12C25", icon: "seedling", logo: "//linuxdo-uploads.s3.ldstatic.com/original/4X/4/2/d/42db3e789b9c65694639e5cbcdebd5d7ebb238be.png"),
            category(id: 14, name: "资源荟萃", slug: "resource", color: "12A89D", icon: "square-share-nodes", logo: "//linuxdo-uploads.s3.ldstatic.com/original/1X/6334a38d6a816e61423f46a0399c160eaaf07321.png"),
            category(id: 94, name: "网盘资源", slug: "cloud-asset", color: "16b176", parentId: 14, icon: "hard-drive", logo: "//linuxdo-uploads.s3.ldstatic.com/original/4X/f/0/9/f09d3cb44fe18aa60cf205a8898885f6655c4b44.png"),
            category(id: 42, name: "文档共建", slug: "wiki", color: "9cb6c4", icon: "book", logo: "//linuxdo-uploads.s3.ldstatic.com/original/3X/c/b/cb17799169729bb83cdc252271a3621885ca33a8.png"),
            category(id: 27, name: "非我莫属", slug: "job", color: "a8c6fe", icon: "briefcase", logo: "//linuxdo-uploads.s3.ldstatic.com/original/2X/0/0ca85c534e813ae5ec9a86ca3334a8c4a99fcc51.png"),
            category(id: 32, name: "读书成诗", slug: "reading", color: "e0d900", icon: "book-open-reader", logo: "//linuxdo-uploads.s3.ldstatic.com/original/2X/8/82dd6190fc33a1bcbe88a2f2d4cf24f3c7966e8c.png"),
            category(id: 34, name: "前沿快讯", slug: "news", color: "BB8FCE", icon: "newspaper", logo: "//linuxdo-uploads.s3.ldstatic.com/original/3X/3/b/3bc85a6999925899bce84ac7feedd907c8b0be8f.png"),
            category(id: 92, name: "网络记忆", slug: "feeds", color: "F7941D", icon: "rss", logo: "//linuxdo-uploads.s3.ldstatic.com/original/4X/4/c/7/4c7ba1f00c28e1fe838386bb26e87ab4f29c424c.png"),
            category(id: 36, name: "福利羊毛", slug: "welfare", color: "E45735", icon: "piggy-bank", logo: "//linuxdo-uploads.s3.ldstatic.com/original/3X/b/4/b445e49d3e3bdab0cb726e4469f896d001d7188b.png"),
            category(id: 11, name: "搞七捻三", slug: "gossip", color: "3AB54A", icon: "droplet", logo: "//linuxdo-uploads.s3.ldstatic.com/original/1X/f73623406bea03a1f66c657859d80db47842b6b2.png"),
            category(id: 110, name: "虫洞广场", slug: "square", color: "ff00f7", icon: "hurricane", logo: "//linuxdo-uploads.s3.ldstatic.com/original/4X/a/6/0/a60b29099b83d51a949bccd708cbdacee40ada80.png"),
            category(id: 2, name: "运营反馈", slug: "feedback", color: "808281", icon: "comments", logo: "//linuxdo-uploads.s3.ldstatic.com/original/1X/078b3612909bedaf877f5b688a4b01833cc4a3cd.png"),
            category(id: 49, name: "公告", slug: "announcement", color: "F1592A", parentId: 2, icon: "bullhorn"),
            category(id: 123, name: "悬赏", slug: "bounty", color: "c4b512", parentId: 2, icon: "award"),
            category(id: 30, name: "活动", slug: "activity", color: "38571A", parentId: 2, icon: "users"),
            category(id: 124, name: "模板", slug: "template", color: "04a407", parentId: 2, icon: "clone"),
        ]
        return Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
    }()

    static func category(id: Int, baseURL: String) -> DiscourseCategory? {
        guard isLinuxDo(baseURL) else { return nil }
        return categoriesById[id]
    }

    private static func category(
        id: Int,
        name: String,
        slug: String,
        color: String,
        parentId: Int? = nil,
        icon: String?,
        logo: String? = nil
    ) -> DiscourseCategory {
        DiscourseCategory(
            id: id,
            name: name,
            slug: slug,
            color: color,
            parentCategoryId: parentId,
            uploadedLogo: logo,
            icon: icon
        )
    }

    private static func isLinuxDo(_ baseURL: String) -> Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return host == "linux.do" || host == "www.linux.do"
    }
}

struct TopicCategoryBadgePresentation: Equatable {
    enum IconSource: Equatable {
        case fontAwesome(String)
        case logo(String)
        case lock
        case dot
    }

    let categoryId: Int
    let name: String
    let colorHex: String
    let iconSource: IconSource

    static func resolve(
        category: DiscourseCategory?,
        parent: DiscourseCategory?,
        displayName: String? = nil,
        baseURL: String? = nil
    ) -> TopicCategoryBadgePresentation? {
        guard let category else { return nil }

        let resolvedName = nonEmpty(displayName) ?? nonEmpty(category.name) ?? category.name
        let seededCategory = baseURL.flatMap { LinuxDoCategoryCatalog.category(id: category.id, baseURL: $0) }
        let seededParent = parent.flatMap { parent in
            baseURL.flatMap { LinuxDoCategoryCatalog.category(id: parent.id, baseURL: $0) }
        }
        let categoryIcon = nonEmpty(category.icon) ?? nonEmpty(seededCategory?.icon)
        let categoryLogo = nonEmpty(category.uploadedLogo) ?? nonEmpty(seededCategory?.uploadedLogo)
        let parentIcon = nonEmpty(parent?.icon) ?? nonEmpty(seededParent?.icon)
        let parentLogo = nonEmpty(parent?.uploadedLogo) ?? nonEmpty(seededParent?.uploadedLogo)
        let iconSource: IconSource
        if let icon = categoryIcon, DiscourseFontAwesomeIcon.glyph(for: icon) != nil {
            iconSource = .fontAwesome(icon)
        } else if let logo = categoryLogo {
            iconSource = .logo(logo)
        } else if let icon = parentIcon, DiscourseFontAwesomeIcon.glyph(for: icon) != nil {
            iconSource = .fontAwesome(icon)
        } else if let logo = parentLogo {
            iconSource = .logo(logo)
        } else if category.readRestricted {
            iconSource = .lock
        } else {
            iconSource = .dot
        }

        return TopicCategoryBadgePresentation(
            categoryId: category.id,
            name: resolvedName,
            colorHex: category.color,
            iconSource: iconSource
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
