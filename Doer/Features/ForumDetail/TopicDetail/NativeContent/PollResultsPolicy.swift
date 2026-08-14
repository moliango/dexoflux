import Foundation

/// Discourse poll `data-poll-results` visibility — FluxDo `_shouldShowResults`.
/// Cooked HTML still includes vote counts; the UI must hide them until allowed.
enum PollResultsPolicy {
    /// Initial / default: counts stay hidden until the viewer has voted or the poll closed.
    /// `on_close` waits for close even after voting. `staff_only` never reveals in-app.
    static func shouldShowResults(
        resultsMode: String?,
        status: String?,
        hasVoted: Bool
    ) -> Bool {
        let closed = isClosed(status)
        switch normalizedMode(resultsMode) {
        case "on_close":
            return closed
        case "staff_only":
            return false
        default:
            return hasVoted || closed
        }
    }

    /// FluxDo footer toggle: open polls with `always`, or after voting, can flip vote/results.
    static func canToggleResults(
        resultsMode: String?,
        status: String?,
        hasVoted: Bool
    ) -> Bool {
        guard !isClosed(status) else { return false }
        return hasVoted || normalizedMode(resultsMode) == "always"
    }

    private static func isClosed(_ status: String?) -> Bool {
        status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "closed"
    }

    private static func normalizedMode(_ resultsMode: String?) -> String {
        resultsMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }
}
