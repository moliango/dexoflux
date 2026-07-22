import Foundation

/// AI 供应商类型（JSON 兼容 FluxDo ai_model_manager 的 type 命名）。
enum AIProviderType: String, Codable, CaseIterable, Sendable {
    case openai
    case openaiResponse
    case gemini
    case anthropic

    var label: String {
        switch self {
        case .openai: return "OpenAI"
        case .openaiResponse: return "OpenAI-Response"
        case .gemini: return "Gemini"
        case .anthropic: return "Anthropic"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openai, .openaiResponse: return "https://api.openai.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .anthropic: return "https://api.anthropic.com/v1"
        }
    }
}

/// AI 模型（字段与 FluxDo 的 AiModel JSON 保持兼容）。
struct AIModel: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String?
    var enabled: Bool
    /// 输入模态："text" / "image"
    var input: [String]
    /// 输出模态："text" / "image"
    var output: [String]
    /// 能力："tool" / "reasoning"
    var abilities: [String]
    var capabilitiesUserEdited: Bool

    init(
        id: String,
        name: String? = nil,
        enabled: Bool = true,
        input: [String] = ["text"],
        output: [String] = ["text"],
        abilities: [String] = [],
        capabilitiesUserEdited: Bool = false
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.input = input
        self.output = output
        self.abilities = abilities
        self.capabilitiesUserEdited = capabilitiesUserEdited
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        input = try container.decodeIfPresent([String].self, forKey: .input) ?? ["text"]
        output = try container.decodeIfPresent([String].self, forKey: .output) ?? ["text"]
        abilities = try container.decodeIfPresent([String].self, forKey: .abilities) ?? []
        capabilitiesUserEdited = try container.decodeIfPresent(Bool.self, forKey: .capabilitiesUserEdited) ?? false
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }

    var isVision: Bool { input.contains("image") }
    var isImageOutput: Bool { output.contains("image") }
    var isReasoning: Bool { abilities.contains("reasoning") }
    var isTool: Bool { abilities.contains("tool") }
}

/// AI 供应商（JSON 兼容 FluxDo：id/name/type/base_url/models/pinned）。
struct AIProvider: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var type: AIProviderType
    var baseURL: String
    var models: [AIModel]
    var pinned: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, type, models, pinned
        case baseURL = "base_url"
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        type: AIProviderType,
        baseURL: String,
        models: [AIModel] = [],
        pinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.baseURL = baseURL
        self.models = models
        self.pinned = pinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = (try? container.decode(AIProviderType.self, forKey: .type)) ?? .openai
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? type.defaultBaseURL
        models = try container.decodeIfPresent([AIModel].self, forKey: .models) ?? []
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    var enabledModels: [AIModel] {
        models.filter(\.enabled)
    }
}

/// 全局默认模型引用。
struct AIDefaultModelRef: Equatable, Sendable {
    let providerID: String
    let modelID: String

    var storageValue: String { "\(providerID)|\(modelID)" }

    init(providerID: String, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID
    }

    init?(storageValue: String?) {
        guard let storageValue else { return nil }
        let parts = storageValue.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        providerID = parts[0]
        modelID = parts[1]
    }
}

/// 基于模型 ID 的能力推断（正则表移植自 FluxDo model_capabilities.dart）。
enum AIModelCapabilities {
    private static let vision = makeRegex(
        "\\b(?:" +
            "gpt-4o(?:[-.\\w]*)?|gpt-4\\.1(?:[-.\\w]*)?|gpt-5(?!-chat)(?:[-.\\w]*)?|" +
            "chatgpt-4o(?:[-.\\w]*)?|o[1-9](?:[-.\\w]*)?|" +
            "claude-3(?:[-.\\w]*)?|claude-(?:haiku|sonnet|opus)-[4-9](?:[-.\\w]*)?|" +
            "gemini-(?:1\\.5|2\\.0|2\\.5|3)(?:[-.\\w]*)?|gemini-(?:flash|pro|flash-lite)-latest|" +
            "gemini-exp(?:[-.\\w]*)?|gemma-?[34](?:[-.\\w]*)?|" +
            "qwen[2-3]?(?:\\.\\d+)?-?vl(?:[-.\\w]*)?|qvq(?:[-.\\w]*)?|" +
            "qwen3\\.[5-9](?:[-.\\w]*)?|qwen-omni(?:[-.\\w]*)?|" +
            "doubao-seed-(?:1[.-][68]|2[.-]0|code)(?:[-.\\w]*)?|" +
            "kimi-vl(?:[-.\\w]*)?|kimi-k2\\.[56](?:[-.\\w]*)?|kimi-thinking-preview|kimi-latest|" +
            "step-1[ov](?:[-.\\w]*)?|" +
            "deepseek-vl(?:[-.\\w]*)?|" +
            "llama-4(?:[-.\\w]*)?|llama-guard-4(?:[-.\\w]*)?|" +
            "pixtral(?:[-.\\w]*)?|mistral-large-(?:2512|latest)|mistral-medium-(?:2508|latest)|mistral-small(?:[-.\\w]*)?|" +
            "grok-(?:vision-beta|4)(?:[-.\\w]*)?|" +
            "glm-4(?:\\.\\d+)?v(?:[-.\\w]*)?|glm-5v-turbo|" +
            "internvl2(?:[-.\\w]*)?|llava(?:[-.\\w]*)?|moondream(?:[-.\\w]*)?|minicpm(?:[-.\\w]*)?" +
            ")\\b"
    )

    private static let reasoning = makeRegex(
        "\\b(?:" +
            "o[1-9](?:[-.\\w]*)?|gpt-5(?!-chat)(?:[-.\\w]*)?|gpt-oss(?:[-.\\w]*)?|" +
            "gemini-(?:2\\.5|3)(?:[-.\\w]*)?|gemini-(?:flash|pro)-latest|" +
            "claude(?:[-.\\w]*thinking|[-.\\w]*-(?:sonnet|opus|haiku)-[4-9])(?:[-.\\w]*)?|" +
            "qwen-?3(?:[-.\\w]*)?|doubao-seed-1[.-][68](?:[-.\\w]*)?|kimi-k2(?:[-.\\w]*)?|kimi-thinking-preview|" +
            "grok-4(?:[-.\\w]*)?|step-3(?:[-.\\w]*)?|intern-s1(?:[-.\\w]*)?|" +
            "glm-(?:4\\.[5-9]|5|6|7)(?:[-.\\w]*)?|minimax-m2(?:[-.\\w]*)?|" +
            "deepseek-(?:r1|v3\\.[12]|v4|reasoner)(?:[-.\\w]*)?|" +
            "mimo-v2(?:[-.\\w]*)?|qvq(?:[-.\\w]*)?" +
            ")\\b"
    )

    private static let tool = makeRegex(
        "\\b(?:" +
            "gpt-4o(?:[-.\\w]*)?|gpt-4\\.1(?:[-.\\w]*)?|gpt-5(?!-chat)(?:[-.\\w]*)?|gpt-oss(?:[-.\\w]*)?|o[1-9](?:[-.\\w]*)?|" +
            "gemini(?:[-.\\w]*)?|claude(?:[-.\\w]*)?|" +
            "qwen-?3(?:[-.\\w]*)?|doubao-seed-1[.-][68](?:[-.\\w]*)?|grok-4(?:[-.\\w]*)?|" +
            "kimi-k2(?:[-.\\w]*)?|step-3(?:[-.\\w]*)?|intern-s1(?:[-.\\w]*)?|" +
            "glm-(?:4\\.[5-9]|5|6|7)(?:[-.\\w]*)?|minimax-m2(?:[-.\\w]*)?|" +
            "deepseek-(?:r1|v3|v3\\.[12]|v4|chat|reasoner)(?:[-.\\w]*)?|" +
            "mimo-v2(?:[-.\\w]*)?" +
            ")\\b"
    )

    private static let imageOutput = makeRegex(
        "\\b(?:" +
            "dall-e(?:[-.\\w]*)?|gpt-image(?:[-.\\w]*)?|chatgpt-image-latest|" +
            "imagen(?:[-.\\w]*)?|gemini-(?:2\\.0|2\\.5|3)(?:[-.\\w]*)?-(?:flash|pro)-image(?:[-.\\w]*)?|" +
            "flux(?:[-.\\w]*)?|stable-?diffusion(?:[-.\\w]*)?|stabilityai(?:[-.\\w]*)?|sdxl(?:[-.\\w]*)?|" +
            "cogview(?:[-.\\w]*)?|qwen-image(?:[-.\\w]*)?|midjourney(?:[-.\\w]*)?|mj-[\\w-]+|" +
            "grok-2-image(?:[-.\\w]*)?|seedream(?:[-.\\w]*)?|hunyuanimage(?:[-.\\w]*)?|" +
            "janus(?:[-.\\w]*)?|kandinsky(?:[-.\\w]*)?" +
            ")\\b"
    )

    private static let embedding = makeRegex(
        "(?:^|[-_/])embed(?:dings?)?(?:[-.]|$)|embedding"
    )

    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func matches(_ regex: NSRegularExpression?, _ value: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }

    /// 只增不减：在缺失时按模型 ID 推断能力；用户手动编辑过的模型直接跳过。
    static func infer(_ base: AIModel) -> AIModel {
        guard !base.capabilitiesUserEdited else { return base }
        let id = base.id.lowercased()
        guard !matches(embedding, id) else { return base }

        var model = base
        if matches(vision, id), !model.input.contains("image") {
            model.input.append("image")
        }
        if matches(imageOutput, id) {
            if !model.output.contains("image") { model.output.append("image") }
            if !model.input.contains("image") { model.input.append("image") }
        }
        if matches(reasoning, id), !model.abilities.contains("reasoning") {
            model.abilities.append("reasoning")
        }
        if matches(tool, id), !model.abilities.contains("tool") {
            model.abilities.append("tool")
        }
        return model
    }
}
