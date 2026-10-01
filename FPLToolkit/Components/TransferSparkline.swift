import SwiftUI

/// A player's transfers in and out over the last week, one pair of bars a day (Dan, 1 Oct:
/// "small sparkline graphs of transfers in/out to show recent trends"): in rises above the line in
/// green, out drops below it in red, both on the same scale. The 7-day net sits beside it. The
/// figures come from the API; this only draws them.
struct TransferSparkline: View {
    let days: [Today.TransferDay]
    /// The chart's height, growing a little with the text.
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 34

    private var totalIn: Int { days.reduce(0) { $0 + $1.in } }
    private var totalOut: Int { days.reduce(0) { $0 + $1.out } }
    private var net: Int { totalIn - totalOut }

    var body: some View {
        HStack(alignment: .center, spacing: ToolkitSpace.md) {
            bars
                .frame(width: CGFloat(days.count) * 9, height: min(height, 52))
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.netText(net))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(net > 0 ? ToolkitColor.positive : net < 0 ? ToolkitColor.error : ToolkitColor.primaryText)
                Text("Transfers, last \(days.count) days")
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(days))
    }

    private var bars: some View {
        let peak = max(1, days.map { max($0.in, $0.out) }.max() ?? 1)
        return GeometryReader { geo in
            let half = geo.size.height / 2
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    // In grows up from the line, out grows down from it.
                    VStack(spacing: 0) {
                        bar(day.in, peak: peak, half: half, colour: ToolkitColor.positive)
                            .frame(height: half, alignment: .bottom)
                        bar(day.out, peak: peak, half: half, colour: ToolkitColor.error)
                            .frame(height: half, alignment: .top)
                    }
                    .frame(width: 6)
                }
            }
            .frame(maxHeight: .infinity)
            .overlay(Rectangle().fill(ToolkitColor.border).frame(height: 1))
        }
    }

    /// One half-bar: a sliver for none, so every day keeps its place.
    private func bar(_ value: Int, peak: Int, half: CGFloat, colour: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(colour)
            .frame(height: max(1, half * CGFloat(value) / CGFloat(peak)))
            .opacity(value == 0 ? 0.3 : 1)
    }

    /// "+12.3k net in", "−4.1k net out", "Level".
    nonisolated static func netText(_ net: Int) -> String {
        net > 0 ? "+\(Format.compactCount(net)) net in" : net < 0 ? "−\(Format.compactCount(-net)) net out" : "Level"
    }

    /// "Transfers over the last 7 days: 12,300 in, 4,100 out, 8,200 more in than out. Busiest day
    /// in: 28 Sep."
    nonisolated static func spoken(_ days: [Today.TransferDay]) -> String {
        let ins = days.reduce(0) { $0 + $1.in }
        let outs = days.reduce(0) { $0 + $1.out }
        let net = ins - outs
        var text = "Transfers over the last \(days.count) days: \(ins.formatted()) in, \(outs.formatted()) out"
        text += net == 0 ? ", level." : net > 0 ? ", \(net.formatted()) more in than out." : ", \((-net).formatted()) more out than in."
        let busiest = days.max { max($0.in, $0.out) < max($1.in, $1.out) }
        if let busiest, max(busiest.in, busiest.out) > 0, let day = Self.dayName(busiest.date) {
            text += " Busiest: \(day), \(busiest.in >= busiest.out ? "\(busiest.in.formatted()) in" : "\(busiest.out.formatted()) out")."
        }
        return text
    }

    private nonisolated static func dayName(_ iso: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_GB")
        parser.timeZone = TimeZone(identifier: "Europe/London")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return nil }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.timeZone = TimeZone(identifier: "Europe/London")
        out.dateFormat = "EEEE d MMMM"
        return out.string(from: date)
    }
}
