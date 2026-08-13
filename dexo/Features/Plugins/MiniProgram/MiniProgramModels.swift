import Foundation

enum MiniProgramID {
    static let metaverse = "builtin.metaverse"
    static let ldc = "builtin.ldc"
    static let cdk = "builtin.cdk"
    static let newAPICheckIn = "builtin.newapi-check-in"
    static let ldcStore = "builtin.ldc-store"
    static let toolbox = "builtin.toolbox"
}

enum MiniProgramCategoryID {
    static let tools = "tools"
    static let ai = "ai"
    static let community = "community"
    static let entertainment = "entertainment"
    static let other = "other"
}

enum MiniProgramIcon: Codable, Equatable, Hashable {
    case none
    case system(symbolName: String)
    case remote(URL)
    case local(relativePath: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case none
        case system
        case remote
        case local
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Older / partial exports may omit kind entirely for custom programs.
        guard let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) else {
            self = .none
            return
        }
        let value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        switch kind {
        case .none:
            self = .none
        case .system:
            self = value.isEmpty ? .none : .system(symbolName: value)
        case .remote:
            if let url = URL(string: value), !value.isEmpty {
                self = .remote(url)
            } else {
                self = .none
            }
        case .local:
            self = value.isEmpty ? .none : .local(relativePath: value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case .system(let symbolName):
            try container.encode(Kind.system, forKey: .kind)
            try container.encode(symbolName, forKey: .value)
        case .remote(let url):
            try container.encode(Kind.remote, forKey: .kind)
            try container.encode(url.absoluteString, forKey: .value)
        case .local(let relativePath):
            try container.encode(Kind.local, forKey: .kind)
            try container.encode(relativePath, forKey: .value)
        }
    }
}

struct MiniProgramRecord: Codable, Equatable, Hashable, Identifiable {
    enum ProgramKind: String, Codable {
        case builtIn
        case url
    }

    let id: String
    var kind: ProgramKind
    var displayName: String
    var urlString: String?
    var categoryID: String
    /// Custom programs may have no icon (export/import must tolerate this).
    var icon: MiniProgramIcon
    var isVisible: Bool
    var order: Int

    var isBuiltIn: Bool {
        kind == .builtIn
    }

    var normalizedURLString: String? {
        urlString
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, displayName, urlString, categoryID, icon, isVisible, order
    }

    init(
        id: String,
        kind: ProgramKind,
        displayName: String,
        urlString: String?,
        categoryID: String,
        icon: MiniProgramIcon,
        isVisible: Bool,
        order: Int
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.urlString = urlString
        self.categoryID = categoryID
        self.icon = icon
        self.isVisible = isVisible
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(ProgramKind.self, forKey: .kind)
        displayName = try container.decode(String.self, forKey: .displayName)
        urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        categoryID = try container.decode(String.self, forKey: .categoryID)
        // Missing icon is valid for custom URL programs in export packages.
        icon = try container.decodeIfPresent(MiniProgramIcon.self, forKey: .icon) ?? .none
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}

/// Portable mini-program catalog for preferences backup / share packages.
/// Custom programs are allowed to omit icons; local logos may be embedded as base64.
struct MiniProgramCatalogExportPayload: Codable, Equatable {
    var version: Int
    var programs: [MiniProgramRecord]
    var categories: [MiniProgramCategory]
    var recentProgramIDs: [String]
    var favoriteProgramIDs: [String]
    /// Base64 image data for local icons, keyed by program id. Absent when no logo.
    var iconAssets: [String: String]

    init(
        version: Int,
        programs: [MiniProgramRecord],
        categories: [MiniProgramCategory],
        recentProgramIDs: [String],
        favoriteProgramIDs: [String] = [],
        iconAssets: [String: String] = [:]
    ) {
        self.version = version
        self.programs = programs
        self.categories = categories
        self.recentProgramIDs = recentProgramIDs
        self.favoriteProgramIDs = favoriteProgramIDs
        self.iconAssets = iconAssets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        programs = try container.decodeIfPresent([MiniProgramRecord].self, forKey: .programs) ?? []
        categories = try container.decodeIfPresent([MiniProgramCategory].self, forKey: .categories) ?? []
        recentProgramIDs = try container.decodeIfPresent([String].self, forKey: .recentProgramIDs) ?? []
        favoriteProgramIDs = try container.decodeIfPresent([String].self, forKey: .favoriteProgramIDs) ?? []
        iconAssets = try container.decodeIfPresent([String: String].self, forKey: .iconAssets) ?? [:]
    }
}

struct MiniProgramCategory: Codable, Equatable, Hashable, Identifiable {
    let id: String
    var name: String
    var order: Int
    var isBuiltIn: Bool
}

struct MiniProgramCatalogSnapshot: Codable, Equatable {
    var version: Int
    var programs: [MiniProgramRecord]
    var categories: [MiniProgramCategory]
    var recentProgramIDs: [String]
    /// 「我的小程序」收藏列表（首页「常用」区只展示这些，最多 8 个）。
    var favoriteProgramIDs: [String]

    init(
        version: Int,
        programs: [MiniProgramRecord],
        categories: [MiniProgramCategory],
        recentProgramIDs: [String],
        favoriteProgramIDs: [String] = []
    ) {
        self.version = version
        self.programs = programs
        self.categories = categories
        self.recentProgramIDs = recentProgramIDs
        self.favoriteProgramIDs = favoriteProgramIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        programs = try container.decode([MiniProgramRecord].self, forKey: .programs)
        categories = try container.decode([MiniProgramCategory].self, forKey: .categories)
        recentProgramIDs = try container.decodeIfPresent([String].self, forKey: .recentProgramIDs) ?? []
        favoriteProgramIDs = try container.decodeIfPresent([String].self, forKey: .favoriteProgramIDs) ?? []
    }
}

enum MiniProgramStoreError: LocalizedError, Equatable {
    case programNotFound
    case builtInCannotBeEditedAsCustom
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .programNotFound:
            return String(localized: "mini_program.error.not_found", defaultValue: "找不到该小程序")
        case .builtInCannotBeEditedAsCustom:
            return String(
                localized: "mini_program.error.builtin_locked",
                defaultValue: "内置小程序不能修改名称和网址"
            )
        case .invalidURL:
            return String(
                localized: "mini_program.error.invalid_url",
                defaultValue: "网址无效，请输入以 http:// 或 https:// 开头的地址"
            )
        }
    }
}
