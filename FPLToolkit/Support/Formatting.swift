import Foundation

/// Display formatting only. Timestamps arrive in UTC; everything here shows them in the device's time zone.
enum Format {
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

    /// A rank in a small space: "1.2m", "346k", "8,431".
    static func rank(_ value: Int) -> String {
        if value >= 1_000_000 { return (Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(1))) + "m" }
        if value >= 100_000 { return (Double(value) / 1_000).formatted(.number.precision(.fractionLength(0))) + "k" }
        return value.formatted()
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
