import Foundation

/// Display formatting only. Timestamps arrive in UTC; everything here shows them in the device's time zone.
enum Format {
    /// Keeps scores and figures with their units when a sentence wraps (large text sizes): "3–0",
    /// "BRE 3–0 CHE", "6 pts", "81 minutes", "(1 match)", "+£0.1m", "Sat 31 Oct at 15:00" never
    /// split across lines.
    static func keepingFiguresTogether(_ text: String) -> String {
        var out = text.replacing(#/(\d)–(\d)/#) { "\($0.1)\u{2060}–\u{2060}\($0.2)" }
        out = out.replacing(#/([A-Z]{3}) (\d)/#) { "\($0.1)\u{00A0}\($0.2)" }
        out = out.replacing(#/(\d) ([A-Z]{3})\b/#) { "\($0.1)\u{00A0}\($0.2)" }
        out = out.replacing(#/(\d) (pts?|points?|mins?|minutes?|saves?|bonus|of|match|matches|owned)\b/#) {
            "\($0.1)\u{00A0}\($0.2)"
        }
        // A sign stays with its money ("+" / "£0.1m" split; before a digit it can't).
        out = out.replacing(#/([+\-−–])£/#) { "\($0.1)\u{2060}£" }
        // Dates and times: "Sat 31", "31 Oct", "at 15:00".
        out = out.replacing(#/\b(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (\d)/#) { "\($0.1)\u{00A0}\($0.2)" }
        out = out.replacing(#/(\d) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\b/#) { "\($0.1)\u{00A0}\($0.2)" }
        out = out.replacing(#/\bat (\d)/#) { "at\u{00A0}\($0.1)" }
        return out
    }

    /// A "·"-separated line that wraps between its facts, not inside them (large text sizes, Dan's
    /// phone, 1 Oct): each short fact keeps its spaces and slashes ("£5.8m", "0/h", "16.5% owned",
    /// "LEE (H)", "Tomorrow 94.1% (3/5)"), and a line ends with "·" rather than starting with one.
    /// Longer facts can still wrap inside, but keep their figures with their units.
    static func unbroken(_ line: String) -> String {
        line.components(separatedBy: " · ")
            .map { fact in
                guard fact.count <= 24 else { return keepingFiguresTogether(fact) }
                return fact
                    .replacingOccurrences(of: " ", with: "\u{00A0}")
                    .replacingOccurrences(of: "/", with: "/\u{2060}")
                    .replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
                    .replacingOccurrences(of: "-", with: "\u{2011}")
                    .replacing(#/([+−])£/#) { "\($0.1)\u{2060}£" }
            }
            .joined(separator: "\u{00A0}· ")
    }

    /// "820", "12.3k", "1.2m": a count of managers, short enough for a chart's caption.
    static func compactCount(_ n: Int) -> String {
        let a = abs(n)
        let sign = n < 0 ? "−" : ""
        if a < 1_000 { return sign + String(a) }
        if a < 1_000_000 {
            let k = Double(a) / 1_000
            return sign + (k < 100 ? k.formatted(.number.precision(.fractionLength(0...1))) : String(Int(k.rounded()))) + "k"
        }
        return sign + (Double(a) / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "m"
    }

    /// "Sat 10 Oct, 11:00"
    static func deadline(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    /// "Fri 18 Sep"
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "in 13 days", "in 5 h 20 min", "in 12 min", or "passed".
    static func countdown(to date: Date, now: Date = .now) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "passed" }
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        if hours >= 48 { return "in \(days) days" }
        if hours >= 1 { return "in \(hours) h \(minutes % 60) min" }
        return minutes <= 1 ? "in 1 min" : "in \(minutes) min"
    }

    /// "just now", "8 min ago", "3 hr ago", "2 days ago".
    static func ago(_ date: Date, now: Date = .now) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// £m with one decimal place: "£7.5m".
    /// "10d 8h", "8h 20m", "12m", or "Passed": the deadline countdown in a small space.
    static func compactCountdown(to date: Date, now: Date = .now) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "Passed" }
        let minutes = seconds / 60, hours = minutes / 60, days = hours / 24
        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(max(minutes, 1))m"
    }

    /// The same countdown read aloud: "in 10 days 8 hours".
    static func spokenCountdown(to date: Date, now: Date = .now) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "passed" }
        let minutes = seconds / 60, hours = minutes / 60, days = hours / 24
        func unit(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if days > 0 { return "in " + unit(days, "day") + " " + unit(hours % 24, "hour") }
        if hours > 0 { return "in " + unit(hours, "hour") + " " + unit(minutes % 60, "minute") }
        return "in " + unit(max(minutes, 1), "minute")
    }

    /// A rank in full, "345,727": the exact position, never rounded to "346k".
    static func rank(_ value: Int) -> String {
        value.formatted()
    }

    /// A negative amount (an overspent bank) as "−£0.2m", not "£-0.2m".
    static func price(_ value: Double) -> String {
        let amount = "£" + abs(value).formatted(.number.precision(.fractionLength(1))) + "m"
        return value < -0.049 ? "−" + amount : amount
    }

    /// "+1.2%": a signed percentage with up to one decimal place.
    static func signedPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).sign(strategy: .always())) + "%"
    }

    /// "+1.2%" read aloud as "up 1.2 percent".
    static func spokenPercent(_ value: Double) -> String {
        let magnitude = abs(value).formatted(.number.precision(.fractionLength(0...1)))
        return value == 0 ? "0 percent" : "\(value > 0 ? "up" : "down") \(magnitude) percent"
    }

    /// A supporting value with its unit: "75%", "0 min", "-314,391".
    static func supporting(_ value: SupportingValue) -> String {
        switch value.unit {
        case .percent: return value.value.formatted(.number.precision(.fractionLength(0...1))) + "%"
        case .minutes: return value.value.formatted(.number.precision(.fractionLength(0))) + " min"
        case .count, .unknown: return value.value.formatted(.number.precision(.fractionLength(0)))
        }
    }
}

/// Reads a Team ID from what the user typed or pasted: a bare number, or a link containing "entry/<id>".
/// This is input parsing only; the API decides whether the ID is valid.
enum TeamIDInput {
    static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return Int(trimmed)
        }
        if let match = trimmed.firstMatch(of: /entry\/(\d+)/) {
            return Int(match.1)
        }
        return nil
    }
}
