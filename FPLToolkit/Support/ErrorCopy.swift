import Foundation

/// What to tell the user for each failure. An invalid ID, a missing team and FPL being down
/// are different problems, and reviewers test all three (S24).
struct ErrorCopy: Equatable {
    let title: String
    let message: String
    /// True when trying the same thing again might work (FPL down, offline), false when the input is wrong.
    let canRetry: Bool

    init(title: String, message: String, canRetry: Bool) {
        self.title = title
        self.message = message
        self.canRetry = canRetry
    }

    init(_ error: APIError) {
        switch error {
        case .server(.invalidEntryId, _, _):
            self.init(title: "That doesn't look like an FPL Team ID",
                      message: "Team IDs are numbers only, like 1234567. You can also paste your team's link.",
                      canRetry: false)
        case .server(.entryNotFound, _, _):
            self.init(title: "We couldn't find that team",
                      message: "Check the number on your FPL Points page and try again.",
                      canRetry: false)
        case .server(.upstreamUnavailable, _, _), .server(.rateLimited, _, _):
            self.init(title: "FPL isn't responding right now",
                      message: "This doesn't mean your ID is wrong. FPL may be updating; try again in a few minutes.",
                      canRetry: true)
        case .server(.dataUnavailable, _, _), .server(.internal, _, _):
            self.init(title: "We couldn't load that just now",
                      message: "Something went wrong on our side. Try again in a few minutes.",
                      canRetry: true)
        case .server(.invalidAction, let message, _):
            self.init(title: "That move isn't allowed", message: message, canRetry: false)
        case .server(.draftNotFound, _, _):
            self.init(title: "That draft isn't here any more",
                      message: "It may have been deleted, or the app's data was reset.",
                      canRetry: false)
        case .server(.tooManyDrafts, let message, _):
            self.init(title: "You've reached the draft limit", message: message, canRetry: false)
        case .server(.shortlistFull, let message, _):
            self.init(title: "Your shortlist is full", message: message, canRetry: false)
        case .server(.leagueNotFound, let message, _):
            self.init(title: "League not found", message: message, canRetry: false)
        case .server(.tooManyLeagues, let message, _):
            self.init(title: "You've reached the league limit", message: message, canRetry: false)
        case .server(_, let message, let retryable):
            self.init(title: "Something went wrong", message: message, canRetry: retryable)
        case .offline:
            self.init(title: "You're offline",
                      message: "Connect to the internet and try again.",
                      canRetry: true)
        case .timedOut:
            self.init(title: "That took too long",
                      message: "The connection timed out. Try again.",
                      canRetry: true)
        case .unexpected, .decoding:
            self.init(title: "Something went wrong",
                      message: "We couldn't read the response. Try again, and update the app if this keeps happening.",
                      canRetry: true)
        }
    }

    static let invalidInput = ErrorCopy(
        title: "That doesn't look like an FPL Team ID",
        message: "Enter the number from your FPL Points page, or paste your team's link.",
        canRetry: false)
}
