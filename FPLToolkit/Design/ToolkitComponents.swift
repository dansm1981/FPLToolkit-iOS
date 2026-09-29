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
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.link)
                    .frame(minHeight: 44)
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
            .background(ToolkitColor.surface, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
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
        HStack(spacing: 5) {
            Button(action: onInfo) {
                HStack(spacing: 4) {
                    Text(lead)
                    Image(systemName: "info.circle").imageScale(.small)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lead)
            .accessibilityHint(leadHint)
            ForEach(parts, id: \.self) { part in
                Text("·").accessibilityHidden(true)
                Text(part)
            }
        }
        .font(.footnote)
        .foregroundStyle(ToolkitColor.secondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
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
