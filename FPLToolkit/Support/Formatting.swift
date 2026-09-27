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
    static func price(_ value: Double) -> String {
        "£" + value.formatted(.number.precision(.fractionLength(1))) + "m"
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
