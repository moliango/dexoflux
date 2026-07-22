import Foundation

enum AIChatServiceError: LocalizedError {
    case noDefaultModel
    case invalidURL
    case http(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .noDefaultModel:
            return String(localized: "ai.chat.no_model", defaultValue: "请先在 AI 模型服务中配置并选择默认模型")
        case .invalidURL:
            return String(localized: "ai.error.invalid_url", defaultValue: "API 地址无效")
        case .http(let statusCode, let message):
            return AIProviderAPIError.http(statusCode: statusCode, message: message).errorDescription
        }
    }
}

/// 话题 AI 聊天：上下文构建（格式与 FluxDo 逐字对齐）+ 各协议的对话请求。
enum AIChatService {
    // MARK: - Context building (FluxDo parity)

    struct TopicContext: Sendable {
        let title: String
        /// (postNumber, username, cookedHTML)
        let posts: [(Int, String, String)]
    }

    static func systemPrompt(topicTitle: String?) -> String {
        var lines = ["你是一个有帮助的 AI 助手，正在帮助用户理解和讨论一个论坛话题。"]
        if let topicTitle, !topicTitle.isEmpty {
            lines.append("话题标题：\(topicTitle)")
            lines.append("用户可能会就话题内容向你提问，请基于提供的上下文回答。")
        }
        lines.append("请用 Markdown 格式回复。")
        let custom = AIChatSettings.customSystemPrompt
        if !custom.isEmpty {
            lines.append(custom)
        }
        return lines.joined(separator: "\n")
    }

    /// 「#N @user:\n正文」楼层拼接。
    static func contextText(posts: [(Int, String, String)], scope: AIContextScope) -> String {
        let selected = scope.postLimit.map { Array(posts.prefix($0)) } ?? posts
        guard !selected.isEmpty else { return "" }
        var buffer = ""
        for (postNumber, username, cooked) in selected {
            buffer += "#\(postNumber) @\(username):\n"
            buffer += stripHTML(cooked)
            buffer += "\n\n"
        }
        return buffer
    }

    /// FluxDo 的注入方式：用一对 user/assistant 消息把上下文塞进对话历史，
    /// 避免过长的 systemPrompt 被部分网关截断。
    static func contextMessagePair(contextText: String) -> [AIChatMessage] {
        guard !contextText.isEmpty else { return [] }
        return [
            AIChatMessage(role: .user, content: "以下是话题内容：\n\(contextText)"),
            AIChatMessage(role: .assistant, content: "好的，我已经阅读了话题内容。请问你有什么问题？"),
        ]
    }

    static func stripHTML(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<p>", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Chat requests

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()

    /// 发送对话并以增量文本流返回。
    /// openai / openaiResponse 走 SSE 流式；gemini / anthropic 为单次请求
    /// （ponytail: 两家的流式协议差异较大，先整段返回，后续需要再补）。
    static func streamChat(
        providerType: AIProviderType,
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [AIChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch providerType {
                    case .openai:
                        try await streamOpenAI(
                            baseURL: baseURL, apiKey: apiKey, model: model,
                            systemPrompt: systemPrompt, messages: messages,
                            continuation: continuation
                        )
                    case .openaiResponse:
                        try await streamOpenAIResponses(
                            baseURL: baseURL, apiKey: apiKey, model: model,
                            systemPrompt: systemPrompt, messages: messages,
                            continuation: continuation
                        )
                    case .gemini:
                        let text = try await requestGemini(
                            baseURL: baseURL, apiKey: apiKey, model: model,
                            systemPrompt: systemPrompt, messages: messages
                        )
                        continuation.yield(text)
                    case .anthropic:
                        let text = try await requestAnthropic(
                            baseURL: baseURL, apiKey: apiKey, model: model,
                            systemPrompt: systemPrompt, messages: messages
                        )
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: OpenAI chat/completions (SSE)

    private static func streamOpenAI(
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [AIChatMessage],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var payloadMessages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        payloadMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let request = try makeJSONRequest(
            urlString: "\(AIProviderAPIService.formatAPIHost(baseURL))/chat/completions",
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: ["model": model, "messages": payloadMessages, "stream": true]
        )

        let (bytes, response) = try await session.bytes(for: request)
        try await ensureOK(response, bytes: bytes)
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String,
                  !content.isEmpty
            else { continue }
            continuation.yield(content)
        }
    }

    // MARK: OpenAI /responses (SSE)

    private static func streamOpenAIResponses(
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [AIChatMessage],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var input: [[String: Any]] = [["role": "system", "content": systemPrompt]]
        input += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let request = try makeJSONRequest(
            urlString: "\(AIProviderAPIService.formatAPIHost(baseURL))/responses",
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: ["model": model, "input": input, "stream": true]
        )

        let (bytes, response) = try await session.bytes(for: request)
        try await ensureOK(response, bytes: bytes)
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else {
                continue
            }
            if json["type"] as? String == "response.output_text.delta",
               let delta = json["delta"] as? String, !delta.isEmpty {
                continuation.yield(delta)
            }
        }
    }

    // MARK: Gemini generateContent（单次）

    private static func requestGemini(
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [AIChatMessage]
    ) async throws -> String {
        let host = AIProviderAPIService.formatAPIHost(baseURL, apiVersion: "v1beta")
        guard var components = URLComponents(string: "\(host)/models/\(model):generateContent") else {
            throw AIChatServiceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw AIChatServiceError.invalidURL }

        let contents: [[String: Any]] = messages.map { message in
            [
                "role": message.role == .assistant ? "model" : "user",
                "parts": [["text": message.content]],
            ]
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": systemPrompt]]],
            "contents": contents,
        ])

        let json = try await performJSON(request)
        guard let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { return "" }
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    // MARK: Anthropic /messages（单次）

    private static func requestAnthropic(
        baseURL: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        messages: [AIChatMessage]
    ) async throws -> String {
        let request = try makeJSONRequest(
            urlString: "\(AIProviderAPIService.formatAPIHost(baseURL))/messages",
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            ],
            body: [
                "model": model,
                "max_tokens": 4096,
                "system": systemPrompt,
                "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            ]
        )
        let json = try await performJSON(request)
        guard let content = json["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { $0["text"] as? String }.joined()
    }

    // MARK: - Plumbing

    private static func makeJSONRequest(
        urlString: String,
        headers: [String: String],
        body: [String: Any]
    ) throws -> URLRequest {
        guard let url = URL(string: urlString) else { throw AIChatServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func ensureOK(_ response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard !(200 ..< 300).contains(statusCode) else { return }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > 4096 { break }
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        throw AIChatServiceError.http(statusCode: statusCode, message: Self.extractErrorMessage(json))
    }

    private static func performJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200 ..< 300).contains(statusCode) else {
            throw AIChatServiceError.http(statusCode: statusCode, message: extractErrorMessage(json))
        }
        return json ?? [:]
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
