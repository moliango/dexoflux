import Foundation

enum DohDebugLog {
    private static let lock = NSLock()
    private static let maxLines = 500
    private static var entries: [String] = []
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func record(_ message: String, subsystem: String = "DoH") {
        let line = "\(formatter.string(from: Date())) [\(subsystem)] \(message)"
        lock.lock()
        entries.append(line)
        if entries.count > maxLines {
            entries.removeFirst(entries.count - maxLines)
        }
        lock.unlock()

        #if DEBUG
        print(line)
        #endif
    }

    static func snapshot() -> String {
        lock.lock()
        let text = entries.joined(separator: "\n")
        lock.unlock()
        return text
    }

    static func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
