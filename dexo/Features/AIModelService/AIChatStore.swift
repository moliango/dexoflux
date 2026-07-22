import Foundation

/// AI 聊天会话与快捷词的本地持久化（JSON 文件，与 AIModelServiceStore 同目录）。
actor AIChatStore {
    static let shared = AIChatStore()

    private struct SessionsFile: Codable {
        var version = 1
        var sessions: [AIChatSession] = []
    }

    private struct PresetsFile: Codable {
        var version = 1
        var seeded = false
        var presets: [AIPromptPreset] = []
    }

    private let directoryURL: URL
    private let maximumSessionCount = 100

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DexoFlux/AIModelService", isDirectory: true)
    }

    // MARK: - Sessions

    func sessions() -> [AIChatSession] {
        loadSessions().sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func latestSession(baseURL: String, topicId: Int) -> AIChatSession? {
        sessions().first { $0.baseURL == baseURL && $0.topicId == topicId }
    }

    func save(_ session: AIChatSession) throws {
        var file = loadSessions()
        var session = session
        session.updatedAt = Date()
        if let index = file.sessions.firstIndex(where: { $0.id == session.id }) {
            file.sessions[index] = session
        } else {
            file.sessions.append(session)
        }
        if file.sessions.count > maximumSessionCount {
            let sorted = file.sessions.sorted { $0.updatedAt > $1.updatedAt }
            file.sessions = Array(sorted.prefix(maximumSessionCount))
        }
        try persistSessions(file)
    }

    func deleteSession(id: UUID) throws {
        var file = loadSessions()
        file.sessions.removeAll { $0.id == id }
        try persistSessions(file)
    }

    // MARK: - Prompt presets

    func presets() -> [AIPromptPreset] {
        var file = loadPresets()
        if !file.seeded, file.presets.isEmpty {
            file.presets = AIPromptPreset.defaultPresets()
            file.seeded = true
            try? persistPresets(file)
        }
        return file.presets
    }

    func savePreset(_ preset: AIPromptPreset) throws {
        var file = loadPresets()
        file.seeded = true
        if let index = file.presets.firstIndex(where: { $0.id == preset.id }) {
            file.presets[index] = preset
        } else {
            file.presets.append(preset)
        }
        try persistPresets(file)
    }

    func deletePreset(id: UUID) throws {
        var file = loadPresets()
        file.seeded = true
        file.presets.removeAll { $0.id == id }
        try persistPresets(file)
    }

    // MARK: - Persistence

    private var sessionsURL: URL {
        directoryURL.appendingPathComponent("chat-sessions.json")
    }

    private var presetsURL: URL {
        directoryURL.appendingPathComponent("prompt-presets.json")
    }

    private func loadSessions() -> SessionsFile {
        guard let data = try? Data(contentsOf: sessionsURL) else { return SessionsFile() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(SessionsFile.self, from: data)) ?? SessionsFile()
    }

    private func persistSessions(_ file: SessionsFile) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: sessionsURL, options: .atomic)
    }

    private func loadPresets() -> PresetsFile {
        guard let data = try? Data(contentsOf: presetsURL) else { return PresetsFile() }
        return (try? JSONDecoder().decode(PresetsFile.self, from: data)) ?? PresetsFile()
    }

    private func persistPresets(_ file: PresetsFile) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(file).write(to: presetsURL, options: .atomic)
    }
}
