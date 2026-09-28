import SwiftUI

/// "What we checked": every source the response used, with its age and state (meta.freshness).
struct WhatWeCheckedSection: View {
    let sources: [FreshnessSource]
    /// Set when these results are a saved copy: states were true when saved, not necessarily now.
    var savedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: ToolkitSpace.md) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "What we checked")
                if let savedAt {
                    Spacer()
                    Text("Saved \(Format.deadline(savedAt))")
                        .font(.footnote)
                        .foregroundStyle(ToolkitColor.warning)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    FreshnessRow(source: source, isSaved: savedAt != nil)
                    if index < sources.count - 1 {
                        Divider().overlay(ToolkitColor.border)
                    }
                }
            }
        }
    }
}

struct FreshnessRow: View {
    let source: FreshnessSource
    var isSaved = false

    var body: some View {
        HStack(alignment: .center, spacing: ToolkitSpace.md) {
            Image(systemName: source.source.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(stateColor)
                .frame(width: 44, height: 44)
                .background(stateFill, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.source.displayName)
                    .font(.headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: ToolkitSpace.sm)

            Text(stateText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(source.state == .fresh ? ToolkitColor.primaryText : stateColor)
        }
        .padding(.vertical, ToolkitSpace.md)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let label = source.label { parts.append(label) }
        if let asOf = source.asOf {
            parts.append("updated \(Format.ago(asOf))")
        } else {
            parts.append("no timestamp yet")
        }
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var stateText: String {
        switch source.state {
        case .fresh: isSaved ? "Checked" : "Up to date"
        case .stale: "Out of date"
        case .unknown: "Unknown"
        }
    }

    private var stateColor: Color {
        switch source.state {
        case .fresh: ToolkitColor.positive
        case .stale: ToolkitColor.warning
        case .unknown: ToolkitColor.secondaryText
        }
    }

    private var stateFill: Color {
        switch source.state {
        case .fresh: ToolkitColor.positiveFill
        case .stale: ToolkitColor.warningFill
        case .unknown: ToolkitColor.raised
        }
    }
}

extension FreshnessSource.Kind {
    var displayName: String {
        switch self {
        case .fplCore: "Players and fixtures"
        case .availability: "Availability"
        case .pricePredictions: "Price projections"
        case .picks: "Your squad"
        case .elite: "Top 100 managers"
        case .xfdr: "Fixture difficulty"
        case .defcon: "Defensive contributions"
        case .livePoints: "FPL live points"
        case .matchEvents: "Match events"
        case .unknown: "Other data"
        }
    }

    var symbol: String {
        switch self {
        case .fplCore: "list.bullet.rectangle"
        case .availability: "checkmark.shield"
        case .pricePredictions: "chart.line.uptrend.xyaxis"
        case .picks: "tshirt"
        case .elite: "star"
        case .xfdr: "calendar"
        case .defcon: "shield.lefthalf.filled"
        case .livePoints: "dot.radiowaves.left.and.right"
        case .matchEvents: "sportscourt"
        case .unknown: "questionmark"
        }
    }
}
