// Shared building blocks from the UX design pack v1.0 (tasks/ux-redesign.md): one small set of
// components that every redesigned screen reuses, so labels, units, source state and
// accessibility are handled once.
import SwiftUI

// MARK: - Colour roles added by the design pack (adaptive tk.* sets, dark and light)

extension ToolkitColor {
    static let easy = Color("tk.easy")
    static let easyText = Color("tk.easyText")
    static let mid = Color("tk.mid")
    static let midText = Color("tk.midText")
    static let hard = Color("tk.hard")
    static let hardText = Color("tk.hardText")
    static let heroTop = Color("tk.heroTop")
    static let heroBottom = Color("tk.heroBottom")
    static let heroLine = Color("tk.heroLine")
    static let attention = Color("tk.attention")
    static let attentionLine = Color("tk.attentionLine")
    static let pitchTop = Color("tk.pitchTop")
    static let pitchBottom = Color("tk.pitchBottom")
    static let pitchLine = Color("tk.pitchLine")
    static let tile = Color("tk.tile")
    static let tileLine = Color("tk.tileLine")
    static let you = Color("tk.you")
    static let goldTag = Color("tk.goldTag")
    /// A card's hairline edge and its slightly lighter top (design v2's quiet depth).
    static let cardLine = Color("tk.cardLine")
    static let cardTop = Color("tk.cardTop")
}

extension View {
    /// A raised card: surface with a faint lift towards the top and a hairline edge.
    func toolkitCard(radius: CGFloat = ToolkitRadius.card) -> some View {
        background(
            LinearGradient(colors: [ToolkitColor.cardTop, ToolkitColor.surface], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(ToolkitColor.cardLine))
    }
}

extension Color {
    /// "#RRGGBB" from the API; nil for anything else.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

// MARK: - Fixture difficulty in three tones

/// The pack's easy / medium / hard tones for the server's difficulty band (1 easiest … 5
/// hardest). The band is the server's; the app only picks a colour for it, and a missing band
/// is its own state, never "easy".
enum DifficultyTone: Equatable, Sendable {
    case easy, medium, hard, unknown

    init(band: Int?) {
        switch band {
        case .some(...2): self = .easy
        case 3?: self = .medium
        case .some(4...): self = .hard
        default: self = .unknown
        }
    }

    var fill: Color {
        switch self {
        case .easy: ToolkitColor.easy
        case .medium, .unknown: ToolkitColor.mid
        case .hard: ToolkitColor.hard
        }
    }

    var text: Color {
        switch self {
        case .easy: ToolkitColor.easyText
        case .medium, .unknown: ToolkitColor.midText
        case .hard: ToolkitColor.hardText
        }
    }
}

// MARK: - Structure

/// A section title (18–20 pt, bold) with an optional text action on the right, e.g.
/// "Keep an eye on … Watch".
struct SectionHeader: View {
    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ToolkitSpace.sm) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(ToolkitColor.primaryText)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ToolkitSpace.sm)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ToolkitColor.link)
            }
        }
        .padding(.top, ToolkitSpace.sm)
    }
}

/// Rows on one raised surface, e.g. "Your next move". Put `RowDivider()` between rows.
struct CardGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolkitCard()
            .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }
}

struct RowDivider: View {
    var inset: CGFloat = 15
    var body: some View {
        Divider().overlay(ToolkitColor.border).padding(.leading, inset)
    }
}

/// A 35 pt rounded square with a gold symbol, leading a link row.
struct IconBadge: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(ToolkitColor.accent)
            .frame(width: 35, height: 35)
            .background(ToolkitColor.raised, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

/// The look of a tappable row: optional icon, title, optional detail, optional trailing text and
/// a chevron. Use inside a Button or NavigationLink (or `LinkRow`).
struct LinkRowLabel: View {
    let title: String
    var detail: String?
    var systemImage: String?
    var trailing: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: ToolkitSpace.md) {
            if let systemImage { IconBadge(systemImage: systemImage) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ToolkitColor.primaryText)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, ToolkitSpace.md)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct LinkRow: View {
    let title: String
    var detail: String?
    var systemImage: String?
    var trailing: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LinkRowLabel(title: title, detail: detail, systemImage: systemImage, trailing: trailing)
        }
        .buttonStyle(.plain)
    }
}

/// One compact line of source context under a title, e.g. "GW5 squad ⓘ · GW6 fixtures · £2.2m ITB".
/// The first part opens the source sheet; the exact times live there, not on the screen.
struct ContextLine: View {
    let lead: String
    var parts: [String] = []
    var leadHint = "Shows where this comes from"
    let onInfo: () -> Void

    var body: some View {
        // Wraps onto more lines at larger text sizes rather than shrinking or cutting.
        FlowLayout(spacing: 5) {
            leadButton
            ForEach(parts, id: \.self) { part in
                Text("· \(part)")
                    .frame(minHeight: 44)
                    .accessibilityLabel(part)
            }
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.secondaryText)
    }

    private var leadButton: some View {
        Button(action: onInfo) {
            HStack(spacing: 4) {
                Text(lead)
                Image(systemName: "info.circle").imageScale(.small).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lead)
        .accessibilityHint(leadHint)
    }
}

/// A name with its details, and a figure at the end of the line. At the usual sizes it's laid out
/// as before: the details under the name, the figure beside both. From xxLarge the figure stays on
/// the name's line and the details run the full width under them, rather than in a column a word
/// or two wide beside the figure (Dan's phone at xxxLarge, 1 Oct).
struct NameFigureRow<Name: View, Details: View, Figure: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var alignment: VerticalAlignment = .firstTextBaseline
    var spacing: CGFloat = ToolkitSpace.sm
    @ViewBuilder var name: () -> Name
    @ViewBuilder var details: () -> Details
    @ViewBuilder var figure: () -> Figure

    var body: some View {
        if typeSize.stacksRows {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: spacing) {
                    name()
                    Spacer(minLength: spacing)
                    figure()
                        .fixedSize()
                }
                details()
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: alignment, spacing: spacing) {
                VStack(alignment: .leading, spacing: 2) {
                    name()
                    details()
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: spacing)
                figure()
            }
        }
    }
}

extension View {
    /// An accessibility label only when one is given; otherwise the element's own words stand.
    @ViewBuilder func accessibilityLabel(ifGiven label: String?) -> some View {
        if let label { accessibilityLabel(label) } else { self }
    }
}

/// A line of "·"-separated facts that, at the large sizes, wraps between facts rather than inside
/// them (Format.unbroken). The same text at the usual sizes.
struct FactLine: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(typeSize.stacksRows ? Format.unbroken(text) : text)
    }
}

/// Lays views out left to right, wrapping to a new line when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// A green ▲ or red ▼ beside a rank: whether it rose or fell since the week before (Dan, 29 Sep).
/// Decorative; `spoken` says it.
struct RankMoveArrow: View {
    let current: Int
    let previous: Int?

    var body: some View {
        if let previous, previous != current {
            // Big enough that its edges don't blur into the card (the audit's contrast check).
            Image(systemName: current < previous ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(current < previous ? ToolkitColor.positive : ToolkitColor.error)
                .accessibilityHidden(true)
        }
    }

    /// "up 125,655 places", "down 3,210 places", or nil when there's nothing to compare.
    static func spoken(current: Int, previous: Int?) -> String? {
        guard let previous, previous != current else { return nil }
        let places = abs(previous - current).formatted()
        return current < previous ? "up \(places) places" : "down \(places) places"
    }
}

/// Up to four small figures in one card (the Team header's rank, points, value and bank), two
/// by two: four across, the labels wrap and the figures stop lining up.
struct FigureGrid: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        /// What VoiceOver reads for the value (e.g. a rank in full).
        var spoken: String?
        var id: String { label }
    }
    let items: [Item]

    var body: some View {
        // Pairs in a plain grid (not lazy: every figure stays measurable as the text grows).
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { start in
                GridRow {
                    cell(items[start])
                    if start + 1 < items.count { cell(items[start + 1]) } else { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolkitCard()
    }

    private func cell(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.label)
                .font(.caption)
                .foregroundStyle(ToolkitColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(ToolkitColor.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.label): \(item.spoken ?? item.value)")
    }
}

/// The team as a team, not a stray line of text (Dan, 29 Sep): a shirt badge, the name in
/// weight, and the manager under it.
struct TeamIdentity: View {
    let name: String
    var manager: String?
    /// Today's header (Dan's mock, 30 Sep): a big shirt badge and the name in title weight.
    var prominent = false
    @ScaledMetric(relativeTo: .title2) private var badge: CGFloat = 52

    var body: some View {
        HStack(spacing: prominent ? 14 : 10) {
            Image(systemName: "tshirt.fill")
                .font(prominent ? .title2.weight(.semibold) : .footnote.weight(.semibold))
                .foregroundStyle(ToolkitColor.accent)
                .frame(width: prominent ? badge : 30, height: prominent ? badge : 30)
                .background(ToolkitColor.goldTag, in: RoundedRectangle(cornerRadius: prominent ? 14 : 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: prominent ? 2 : 1) {
                Text(name)
                    .font(prominent ? .title2.weight(.bold) : .headline)
                    .foregroundStyle(ToolkitColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let manager {
                    Text(manager)
                        .font(prominent ? .subheadline : .caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(manager.map { "Team \(name), managed by \($0)" } ?? "Team \(name)")
    }
}

// MARK: - Explanations

/// A row inside an explanation sheet that goes somewhere (the sheet closes first).
struct InfoSheetLink: Identifiable {
    let title: String
    var detail: String?
    var systemImage: String?
    let action: () -> Void
    var id: String { title }
}

/// One good home for a definition or a source: a title, the explanation and optional links.
/// Present with `.sheet`; it sizes itself to its content.
struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    var links: [InfoSheetLink] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ToolkitSpace.lg) {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(ToolkitColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if !links.isEmpty {
                        CardGroup {
                            ForEach(Array(links.enumerated()), id: \.element.id) { index, link in
                                if index > 0 { RowDivider() }
                                LinkRow(title: link.title, detail: link.detail, systemImage: link.systemImage) {
                                    dismiss()
                                    link.action()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, ToolkitSpace.page)
                .padding(.bottom, ToolkitSpace.xl)
            }
            .toolkitScreen()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Figures

/// Up to three headline figures in a row, divided by hairlines, e.g. "37 Season points".
struct StatStrip: View {
    struct Item: Identifiable {
        let value: String
        let label: String
        var id: String { label }
    }
    let items: [Item]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: ToolkitSpace.md))
            : AnyLayout(HStackLayout(alignment: .top, spacing: ToolkitSpace.md))
        layout {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.value)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(ToolkitColor.primaryText)
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(ToolkitColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if index < items.count - 1 && !typeSize.isAccessibilitySize {
                    Rectangle().fill(ToolkitColor.border).frame(width: 1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A thin gold bar for progress towards something (e.g. a price threshold). Presentation only.
struct ProgressLine: View {
    /// 0…1; clamped.
    let fraction: Double
    var tint: Color = ToolkitColor.accent

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ToolkitColor.raised)
                Capsule().fill(tint)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), 4))
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

/// The one prominent card on a screen (the gameweek score on Today and Matchday).
struct HeroCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [ToolkitColor.heroTop, ToolkitColor.heroBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.heroLine))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

/// A real problem that needs a decision (e.g. a flagged player in your squad).
struct AttentionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ToolkitColor.attention, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.attentionLine))
    }
}

/// A local exception that affects what's on screen, e.g. "Live updates delayed · last received 15:42".
struct InlineNotice: View {
    let text: String
    var systemImage = "exclamationmark.triangle"

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.warning)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ToolkitColor.warningFill, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(ToolkitColor.attentionLine))
    }
}

/// A small rounded tag, e.g. "In your GW5 squad" or "Final".
struct Tag: View {
    let text: String
    var foreground: Color = ToolkitColor.secondaryText
    var fill: Color = ToolkitColor.raised

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
    }
}
