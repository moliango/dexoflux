import Foundation

enum MiniProgramID {
    static let ldc = "builtin.ldc"
    static let cdk = "builtin.cdk"
    static let newAPICheckIn = "builtin.newapi-check-in"
    static let ldcStore = "builtin.ldc-store"
}

enum MiniProgramCategoryID {
    static let tools = "tools"
    static let ai = "ai"
    static let community = "community"
    static let entertainment = "entertainment"
    static let other = "other"
}

enum MiniProgramIcon: Codable, Equatable, Hashable {
    case system(symbolName: String)
    case remote(URL)
    case local(relativePath: String)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case system
        case remote
        case local
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        switch kind {
        case .system:
            self = .system(symbolName: value)
        case .remote:
            self = .remote(URL(string: value) ?? URL(string: "https://invalid.local")!)
        case .local:
            self = .local(relativePath: value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
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
    var icon: MiniProgramIcon
    var isVisible: Bool
    var order: Int

    var isBuiltIn: Bool {
        kind == .builtIn
    }

    var normalizedURLString: String? {
        urlString
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
            return "Mini program not found"
        case .builtInCannotBeEditedAsCustom:
            return "Built-in mini programs cannot be edited as custom URL programs"
        case .invalidURL:
            return "Invalid mini program URL"
        }
    }
}
