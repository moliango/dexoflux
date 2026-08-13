import Foundation

enum AIPostReviewService {
    static func reviewDraft(title: String?, content: String, categoryName: String?) async throws -> String {
        guard let ref = AIModelServiceStore.defaultModelRef() else {
            throw AIChatServiceError.noDefaultModel
        }
        let store = AIModelServiceStore.shared
        guard let provider = await store.provider(id: ref.providerID),
              let apiKey = await store.apiKey(for: ref.providerID),
              !apiKey.isEmpty
        else {
            throw AIChatServiceError.noDefaultModel
        }

        let prompt = """
        你是论坛发帖助手。请用简洁中文审阅以下草稿，指出风险、不清楚的地方，并给出改进建议（条目化）。不要替用户直接发帖。
        分类: \(categoryName ?? "未知")
        标题: \(title ?? "(无)")
        正文:
        \(content)
        """
        let messages = [AIChatMessage(role: .user, content: prompt)]
        var output = ""
        let stream = AIChatService.streamChat(
            providerType: provider.type,
            baseURL: provider.baseURL,
            apiKey: apiKey,
            model: ref.modelID,
            systemPrompt: "You are a careful forum writing assistant. Reply in Chinese.",
            messages: messages
        )
        for try await chunk in stream {
            output += chunk
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw AIChatServiceError.http(statusCode: -1, message: "empty review")
        }
        return trimmed
    }
}
