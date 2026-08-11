import Foundation

#if DEBUG
/// Lightweight counters for Topic Detail scroll/perf experiments (DEBUG only).
enum TopicDetailPerfCounters {
    static var heightInvalidateRequests = 0
    static var progressiveCompletes = 0
    static var mediaPauseToggles = 0

    static func reset() {
        heightInvalidateRequests = 0
        progressiveCompletes = 0
        mediaPauseToggles = 0
    }

    static var summary: String {
        "heightInv=\(heightInvalidateRequests) progressive=\(progressiveCompletes) mediaPause=\(mediaPauseToggles)"
    }
}
#endif
