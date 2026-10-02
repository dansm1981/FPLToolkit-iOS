import SwiftUI

/// The one player row (design pack p.32): headshot, name with captaincy and availability, a short
/// line of context with the club badge, and one aligned value on the right. Every list that shows
/// players should use it rather than its own multiline layout.
struct PlayerListRow: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let player: PlayerSummary
    /// "C" or "V".
    var role: String?
    /// The line under the name, after the club, e.g. "£4.5m · xFDR · Defence 3.5".
    var detail: String?
    /// The aligned value on the right, e.g. "MUN A" or "8.0".
    var value: String?
    /// A second, smaller line under the value, e.g. "xFDR".
    var valueDetail: String?
    /// A difficulty value under the value, on its tone (e.g. "3.5").
    var valueChip: (text: String, tone: DifficultyTone)?
    var showsChevron = true
    /// What VoiceOver reads after the name; defaults to the visible text.
    var spokenDetail: String?
    /// A long detail (Matchday's players to watch): it runs to as many lines as it needs, and from
    /// xxLarge it takes the full width under the name rather than a narrow column beside the value
    /// (as Player finder rows, Dan's phone at xxxLarge). Others stop at two lines below the
    /// accessibility sizes.
    var wrapsDetail = false
    /// The headshot's text scaling (as PlayerPhoto), to line a detail below up under the name.
    @ScaledMetric(relativeTo: .body) private var photoUnit: CGFloat = 1

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ToolkitSpace.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        let detailBelow = wrapsDetail && typeSize.stacksRows && !typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 4) {
            layout {
                HStack(spacing: 10) {
                    PlayerPhoto(path: player.photo, clubLogo: appModel.club(player.clubId)?.logo, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(player.webName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(ToolkitColor.primaryText)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                            if let role {
                                Text(role)
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(ToolkitColor.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(ToolkitColor.goldTag, in: RoundedRectangle(cornerRadius: 5))
                                    // Caption, not caption2, and never squeezed by a long name: the
                                    // accessibility audit flagged the badge at larger text sizes.
                                    .fixedSize()
                            }
                            AvailabilityBadge(availability: player.availability)
                        }
                        if !detailBelow {
                            ClubLabel(clubId: player.clubId, text: metaLine, logoSize: 13)
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .lineLimit(typeSize.isAccessibilitySize || wrapsDetail ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: ToolkitSpace.sm) }
                if value != nil || valueDetail != nil || valueChip != nil {
                    VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                        if let value {
                            Text(value)
                                .font(.body.weight(.bold).monospacedDigit())
                                .foregroundStyle(ToolkitColor.primaryText)
                        }
                        if let valueDetail {
                            // Caption, not caption2, and never squeezed: the audit reported "+2 est."
                            // in caption2 as not resizing.
                            Text(valueDetail)
                                .font(.caption)
                                .foregroundStyle(ToolkitColor.secondaryText)
                                .fixedSize()
                        }
                        if let valueChip {
                            Text(valueChip.text)
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(valueChip.tone.text)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(valueChip.tone.fill, in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                if showsChevron && !typeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            if detailBelow {
                ClubLabel(clubId: player.clubId, text: metaLine, logoSize: 13)
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, (34 * min(photoUnit, 1.5)).rounded() + 10)
            }
        }
        .padding(.vertical, ToolkitSpace.md)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var metaLine: String {
        let club = appModel.club(player.clubId)?.shortName
        return ([club] + [detail]).compactMap { $0 }.joined(separator: " · ")
    }

    private var spokenLabel: String {
        var parts = [player.webName]
        if role == "C" { parts.append("captain") }
        if role == "V" { parts.append("vice-captain") }
        switch player.availability.level {
        case .doubt: parts.append(player.availability.chanceNext.map { "\($0)% chance of playing" } ?? "doubtful")
        case .out: parts.append("out")
        case .ok, .unknown: break
        }
        if let club = appModel.club(player.clubId)?.name { parts.append(club) }
        if let spokenDetail { parts.append(spokenDetail) } else {
            if let detail { parts.append(detail) }
            if let value { parts.append(value) }
            if let valueChip { parts.append(valueChip.text) }
        }
        return parts.joined(separator: ", ")
    }
}
