import SwiftUI

struct RoleBadge: View {
    let letter: String
    var body: some View {
        Text(letter)
            .font(.caption.weight(.heavy))
            .foregroundStyle(ToolkitColor.onAccent)
            .frame(width: 22, height: 22)
            .background(ToolkitColor.accent, in: Circle())
            .accessibilityLabel(letter == "C" ? "Captain" : "Vice-captain")
    }
}

/// Nothing for available players; an icon plus the published chance (never colour alone) otherwise.
struct AvailabilityBadge: View {
    let availability: PlayerSummary.Availability

    var body: some View {
        switch availability.level {
        case .ok, .unknown:
            EmptyView()
        case .doubt, .out:
            let isOut = availability.level == .out
            Label(chanceText, systemImage: isOut ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOut ? ToolkitColor.error : ToolkitColor.warning)
                .accessibilityLabel(availability.news ?? (isOut ? "Out" : "Doubtful"))
        }
    }

    private var chanceText: String {
        if let chance = availability.chanceNext { return "\(chance)%" }
        return availability.level == .out ? "Out" : "Doubt"
    }
}
