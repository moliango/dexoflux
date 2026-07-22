import Foundation

enum AIProviderAPIError: LocalizedError {
    case invalidURL
    case http(statusCode: Int, message: String?)
    case network(Error)
    case badPayload

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "ai.error.invalid_url", defaultValue: "API 地址无效")
        case .http(let statusCode, let message):
            if let message, !message.isEmpty { return message }
            switch statusCode {
            case 401: return String(localized: "ai.error.key_invalid", defaultValue: "API Key 无效或已过期")
            case 403: return String(localized: "ai.error.forbidden", defaultValue: "没有访问权限")
            case 404: return String(localized: "ai.error.not_found", defaultValue: "接口不存在，请检查 API 地址")
            case 429: return String(localized: "ai.error.rate_limited", defaultValue: "请求过于频繁，请稍后再试")
            case 500...: return String(
                format: String(localized: "ai.error.server", defaultValue: "服务器错误（%d）"),
                statusCode
            )
            default: return String(
                format: String(localized: "ai.error.request_failed", defaultValue: "请求失败（%d）"),
                statusCode
            )
            }
        case .network(let error):
            return error.localizedDescription
        case .badPayload:
            return String(localized: "ai.error.bad_payload", defaultValue: "响应格式无法解析")
        }
    }
}

/// 拉取模型列表 / 连通性测试（移植自 FluxDo AiProviderApiService）。
enum AIProviderAPIService {
    /// Anthropic 不提供公开的模型列表接口，使用预置列表（同 FluxDo）。
    static let anthropicModels: [AIModel] = [
        AIModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4"),
        AIModel(id: "claude-opus-4-20250514", name: "Claude Opus 4"),
        AIModel(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku"),
    ]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// 规范化 baseURL（同 FluxDo ApiHostFormatter）：
    /// 1. 以 `#` 结尾 → 严格模式，只去掉 `#`
    /// 2. 路径已含 /v<N>[alpha|beta] → 不重复补
    /// 3. 否则补 `/v1`（Gemini 补 `/v1beta`）
    static func formatAPIHost(_ host: String, apiVersion: String = "v1") -> String {
        var trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.hasSuffix("#") {
            return String(trimmed.dropLast())
        }
        let path = URL(string: trimmed)?.path ?? trimmed
        if path.range(of: "/v\\d+(?:alpha|beta)?(?:/|$)", options: [.regularExpression, .caseInsensitive]) != nil {
            return trimmed
        }
        return "\(trimmed)/\(apiVersion)"
    }

    // MARK: - Fetch models

    static func fetchModels(type: AIProviderType, baseURL: String, apiKey: String) async throws -> [AIModel] {
        let models: [AIModel]
        switch type {
        case .openai, .openaiResponse:
            models = try await fetchOpenAIModels(baseURL: baseURL, apiKey: apiKey)
        case .gemini:
            models = try await fetchGeminiModels(baseURL: baseURL, apiKey: apiKey)
        case .anthropic:
            models = anthropicModels
        }
        return models.map(AIModelCapabilities.infer)
    }

    private static func fetchOpenAIModels(baseURL: String, apiKey: String) async throws -> [AIModel] {
        guard let url = URL(string: "\(formatAPIHost(baseURL))/models") else {
            throw AIProviderAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let json = try await performJSON(request)
        guard let list = json["data"] as? [[String: Any]] else {
            throw AIProviderAPIError.badPayload
        }
        return list
            .compactMap { item -> AIModel? in
                guard let id = item["id"] as? String, !id.isEmpty else { return nil }
                return AIModel(id: id)
            }
            .sorted { $0.id < $1.id }
    }

    private static func fetchGeminiModels(baseURL: String, apiKey: String) async throws -> [AIModel] {
        let host = formatAPIHost(baseURL, apiVersion: "v1beta")
        guard var components = URLComponents(string: "\(host)/models") else {
            throw AIProviderAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw AIProviderAPIError.invalidURL }
        let json = try await performJSON(URLRequest(url: url))
        guard let list = json["models"] as? [[String: Any]] else {
            throw AIProviderAPIError.badPayload
        }
        return list
            .compactMap { item -> AIModel? in
                guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                let id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                return AIModel(id: id, name: item["displayName"] as? String)
            }
            .sorted { $0.id < $1.id }
    }

    // MARK: - Test

    /// 发送最小请求验证模型可用；成功返回 nil，失败返回错误描述。
    static func testModel(
        type: AIProviderType,
        baseURL: String,
        apiKey: String,
        modelID: String
    ) async -> String? {
        do {
            var request: URLRequest
            switch type {
            case .openai:
                request = try makePOST(
                    urlString: "\(formatAPIHost(baseURL))/chat/completions",
                    headers: ["Authorization": "Bearer \(apiKey)"],
                    body: [
                        "model": modelID,
                        "messages": [["role": "user", "content": "hi"]],
                        "max_tokens": 1,
                    ]
                )
            case .openaiResponse:
                request = try makePOST(
                    urlString: "\(formatAPIHost(baseURL))/responses",
                    headers: ["Authorization": "Bearer \(apiKey)"],
                    body: [
                        "model": modelID,
                        "input": "hi",
                        "max_output_tokens": 1,
                    ]
                )
            case .gemini:
                let host = formatAPIHost(baseURL, apiVersion: "v1beta")
                guard var components = URLComponents(string: "\(host)/models/\(modelID):generateContent") else {
                    throw AIProviderAPIError.invalidURL
                }
                components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
                guard let url = components.url else { throw AIProviderAPIError.invalidURL }
                request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "contents": [["parts": [["text": "hi"]]]],
                    "generationConfig": ["maxOutputTokens": 1],
                ])
            case .anthropic:
                request = try makePOST(
                    urlString: "\(formatAPIHost(baseURL))/messages",
                    headers: [
                        "x-api-key": apiKey,
                        "anthropic-version": "2023-06-01",
                    ],
                    body: [
                        "model": modelID,
                        "max_tokens": 1,
                        "messages": [["role": "user", "content": "hi"]],
                    ]
                )
            }
            _ = try await performJSON(request)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Plumbing

    private static func makePOST(
        urlString: String,
        headers: [String: String],
        body: [String: Any]
    ) throws -> URLRequest {
        guard let url = URL(string: urlString) else { throw AIProviderAPIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func performJSON(_ request: URLRequest) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIProviderAPIError.network(error)
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200 ..< 300).contains(statusCode) else {
            throw AIProviderAPIError.http(statusCode: statusCode, message: extractErrorMessage(json))
        }
        guard let json else { throw AIProviderAPIError.badPayload }
        return json
    }

    private static func extractErrorMessage(_ json: [String: Any]?) -> String? {
        guard let json else { return nil }
        if let errorObject = json["error"] as? [String: Any],
           let message = errorObject["message"] as? String, !message.isEmpty {
            return message
        }
        if let message = json["error"] as? String, !message.isEmpty { return message }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        return nil
    }
}
