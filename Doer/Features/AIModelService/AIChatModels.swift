import Foundation

// MARK: - Chat messages

enum AIChatRole: String, Codable, Sendable {
    case user
    case assistant
}

struct AIChatMessage: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var role: AIChatRole
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: AIChatRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - Context scope (FluxDo ContextScope)

enum AIContextScope: String, Codable, CaseIterable, Sendable {
    case firstPostOnly
    case first5
    case first10
    case first20
    case all

    var label: String {
        switch self {
        case .firstPostOnly: return String(localized: "ai.context.first_post", defaultValue: "仅主帖")
        case .first5: return String(localized: "ai.context.first5", defaultValue: "前 5 楼")
        case .first10: return String(localized: "ai.context.first10", defaultValue: "前 10 楼")
        case .first20: return String(localized: "ai.context.first20", defaultValue: "前 20 楼")
        case .all: return String(localized: "ai.context.all", defaultValue: "全部楼层")
        }
    }

    var postLimit: Int? {
        switch self {
        case .firstPostOnly: return 1
        case .first5: return 5
        case .first10: return 10
        case .first20: return 20
        case .all: return nil
        }
    }
}

// MARK: - Sessions

struct AIChatSession: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var baseURL: String
    var topicId: Int
    var topicTitle: String
    var messages: [AIChatMessage]
    var modelName: String?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        baseURL: String,
        topicId: Int,
        topicTitle: String,
        messages: [AIChatMessage] = [],
        modelName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.baseURL = baseURL
        self.topicId = topicId
        self.topicTitle = topicTitle
        self.messages = messages
        self.modelName = modelName
        self.updatedAt = updatedAt
    }

    var lastMessagePreview: String? {
        messages.last.map { message in
            let trimmed = message.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
        }
    }
}

// MARK: - Prompt presets (FluxDo 快捷词)

struct AIPromptPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var prompt: String

    init(id: UUID = UUID(), title: String, prompt: String) {
        self.id = id
        self.title = title
        self.prompt = prompt
    }

    /// FluxDo 的四个默认快捷词（文案逐字对齐）。
    static func defaultPresets() -> [AIPromptPreset] {
        [
            AIPromptPreset(
                title: String(localized: "ai.preset.summarize", defaultValue: "总结这个话题"),
                prompt: String(
                    localized: "ai.preset.summarize.prompt",
                    defaultValue: "请简要总结这个话题的主要内容和讨论要点。"
                )
            ),
            AIPromptPreset(
                title: String(localized: "ai.preset.translate", defaultValue: "翻译主帖"),
                prompt: String(
                    localized: "ai.preset.translate.prompt",
                    defaultValue: "请将主帖内容翻译成英文。"
                )
            ),
            AIPromptPreset(
                title: String(localized: "ai.preset.viewpoints", defaultValue: "列出主要观点"),
                prompt: String(
                    localized: "ai.preset.viewpoints.prompt",
                    defaultValue: "请列出这个话题中各楼层的主要观点和立场。"
                )
            ),
            AIPromptPreset(
                title: String(localized: "ai.preset.highlights", defaultValue: "有什么值得关注的"),
                prompt: String(
                    localized: "ai.preset.highlights.prompt",
                    defaultValue: "这个话题中有哪些值得关注的信息或亮点？"
                )
            ),
        ]
    }
}

// MARK: - Chat settings

enum AIChatSettings {
    private static let contextScopeKey = "ai.chat.default_context_scope"
    private static let systemPromptKey = "ai.chat.custom_system_prompt"

    static var defaultContextScope: AIContextScope {
        get {
            UserDefaults.standard.string(forKey: contextScopeKey)
                .flatMap(AIContextScope.init(rawValue:)) ?? .first5
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: contextScopeKey)
        }
    }

    /// 追加在默认系统提示之后的自定义提示词；空表示不追加。
    static var customSystemPrompt: String {
        get {
            UserDefaults.standard.string(forKey: systemPromptKey) ?? ""
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: systemPromptKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: systemPromptKey)
            }
        }
    }
}
