import Foundation
import Testing
@testable import FPLToolkit

/// Large text sizes (Dan's phone at xxxLarge, 1 Oct): lines wrap between facts, not inside them.
struct LargeTextFormattingTests {
    private let nbsp = "\u{00A0}"
    private let joiner = "\u{2060}"

    @Test func factsStayWholeAndLinesEndWithTheDot() {
        let line = Format.unbroken("BHA · MID · £5.8m · 16.5% owned · LEE (H) 1.4")
        #expect(line == "BHA\(nbsp)· MID\(nbsp)· £5.8m\(nbsp)· 16.5%\(nbsp)owned\(nbsp)· LEE\(nbsp)(H)\(nbsp)1.4")
        #expect(Format.unbroken("2/h · 0/h") == "2/\(joiner)h\(nbsp)· 0/\(joiner)h")
        #expect(Format.unbroken("15-man") == "15\u{2011}man")
    }

    @Test func signsLabelsAndDatesStayWithTheirValues() {
        #expect(Format.unbroken("EVE · +£0.1m today") == "EVE\(nbsp)· +\(joiner)£0.1m\(nbsp)today")
        #expect(Format.unbroken("Tomorrow 94.1% (3/5)") == "Tomorrow\(nbsp)94.1%\(nbsp)(3/\(joiner)5)")
        #expect(Format.keepingFiguresTogether("Away · Sat 31 Oct at 15:00")
            == "Away · Sat\(nbsp)31\(nbsp)Oct at\(nbsp)15:00")
        #expect(Format.keepingFiguresTogether("(1 match)") == "(1\(nbsp)match)")
    }

    @Test func longFactsCanStillWrap() {
        let long = "Sold for Gibbs-White by three managers"
        #expect(Format.unbroken(long) == long)
    }

    @Test func plainTextIsUnchanged() {
        #expect(Format.unbroken("Haaland") == "Haaland")
        #expect(Format.unbroken("") == "")
    }

    @Test func scoresAndFiguresKeepTogether() {
        #expect(Format.keepingFiguresTogether("Full-time: BRE 3–0 CHE")
            == "Full-time: BRE\(nbsp)3\(joiner)–\(joiner)0\(nbsp)CHE")
        #expect(Format.keepingFiguresTogether("Verbruggen 6 pts · Konsa 1 pt")
            == "Verbruggen 6\(nbsp)pts · Konsa 1\(nbsp)pt")
        #expect(Format.keepingFiguresTogether("After 81 minutes") == "After 81\(nbsp)minutes")
        #expect(Format.keepingFiguresTogether("Hall reaches DEFCON") == "Hall reaches DEFCON")
    }
}
