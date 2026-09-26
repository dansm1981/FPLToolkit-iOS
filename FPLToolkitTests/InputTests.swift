import Foundation
import Testing
@testable import FPLToolkit

struct TeamIDInputTests {
    @Test(arguments: [
        ("1234567", 1234567),
        ("  71191 \n", 71191),
        ("https://fantasy.premierleague.com/entry/3612045/event/5", 3612045),
        ("fantasy.premierleague.com/entry/895045/history", 895045),
    ])
    func parses(input: String, expected: Int) {
        #expect(TeamIDInput.parse(input) == expected)
    }

    @Test(arguments: ["", "   ", "abc", "12a34", "https://fantasy.premierleague.com/leagues"])
    func rejects(input: String) {
        #expect(TeamIDInput.parse(input) == nil)
    }
}

struct ErrorCopyTests {
    @Test func invalidIdIsNotFPLDown() {
        let invalid = ErrorCopy(.server(code: .invalidEntryId, message: "", retryable: false))
        let notFound = ErrorCopy(.server(code: .entryNotFound, message: "", retryable: false))
        let down = ErrorCopy(.server(code: .upstreamUnavailable, message: "", retryable: true))
        #expect(!invalid.canRetry)
        #expect(!notFound.canRetry)
        #expect(down.canRetry)
        #expect(down.message.contains("doesn't mean your ID is wrong"))
        #expect(Set([invalid.title, notFound.title, down.title]).count == 3)
    }
}
