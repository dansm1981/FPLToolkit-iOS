// The one squad system (design pack p.30): pitch tiles, the pitch and the bench, shared by Team,
// Planner, templates and Matchday. Each screen keeps its own meaning; the parts are the same.
import SwiftUI

// MARK: - Club-colour shirt

/// A drawn shirt in the club's colours (Dan, 29 Sep: no licensed kit artwork, and no FPL/PL
/// images). Outfield players wear the primary colour with secondary trim; goalkeepers wear the
/// secondary colour with primary trim, so they stand apart. Without club colours it's a neutral
/// shirt of the same size, so layouts never shift. Always decorative: the name is beside it.
struct KitShirt: View {
    let colors: Bootstrap.Club.Colors?
    var goalkeeper = false
    var size: CGFloat = 26

    var body: some View {
        let primary = colors.flatMap { Color(hex: $0.primary) }
        let secondary = colors.flatMap { Color(hex: $0.secondary) }
        let body = (goalkeeper ? secondary : primary) ?? ToolkitColor.raised
        let trim = (goalkeeper ? primary : secondary) ?? ToolkitColor.secondaryText
        ZStack {
            ShirtShape().fill(body)
            ShirtCuffs().fill(trim)
            ShirtCollar().stroke(trim, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round, lineJoin: .round))
            ShirtShape().stroke(Color.black.opacity(0.28), lineWidth: 0.75)
        }
        .frame(width: size, height: size * 0.92)
        .accessibilityHidden(true)
    }
}

private enum ShirtPoints {
    // A shirt in a unit square, clockwise from the left of the neck.
    static let outline: [CGPoint] = [
        CGPoint(x: 0.36, y: 0.05), CGPoint(x: 0.64, y: 0.05), CGPoint(x: 0.86, y: 0.13),
        CGPoint(x: 1.00, y: 0.37), CGPoint(x: 0.85, y: 0.46), CGPoint(x: 0.79, y: 0.39),
        CGPoint(x: 0.79, y: 0.97), CGPoint(x: 0.21, y: 0.97), CGPoint(x: 0.21, y: 0.39),
        CGPoint(x: 0.15, y: 0.46), CGPoint(x: 0.00, y: 0.37), CGPoint(x: 0.14, y: 0.13),
    ]
}

private func scaled(_ p: CGPoint, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
}

private struct ShirtShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = ShirtPoints.outline.map { scaled($0, in: rect) }
        path.move(to: points[0])
        // The neckline dips between the first two points.
        path.addQuadCurve(to: points[1], control: scaled(CGPoint(x: 0.5, y: 0.2), in: rect))
        for point in points.dropFirst(2) { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

private struct ShirtCollar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: scaled(CGPoint(x: 0.36, y: 0.05), in: rect))
        path.addQuadCurve(to: scaled(CGPoint(x: 0.64, y: 0.05), in: rect),
                          control: scaled(CGPoint(x: 0.5, y: 0.2), in: rect))
        return path
    }
}

private struct ShirtCuffs: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // A band at the end of each sleeve.
        for (outer, inner) in [((1.00, 0.37), (0.85, 0.46)), ((0.00, 0.37), (0.15, 0.46))] {
            let dx = outer.0 < 0.5 ? 0.05 : -0.05
            path.move(to: scaled(CGPoint(x: outer.0, y: outer.1), in: rect))
            path.addLine(to: scaled(CGPoint(x: inner.0, y: inner.1), in: rect))
            path.addLine(to: scaled(CGPoint(x: inner.0 + dx, y: inner.1 - 0.07), in: rect))
            path.addLine(to: scaled(CGPoint(x: outer.0 + dx, y: outer.1 - 0.08), in: rect))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Pitch tile

/// What one tile shows. The screen builds it; the tile only lays it out.
struct PitchTileModel: Identifiable, Hashable {
    enum Metric: Hashable {
        /// Opponent and venue with the difficulty value, e.g. "LIV A" "3.1".
        case fixture(label: String, value: String?, tone: DifficultyTone)
        /// A plain value, e.g. "£5.7m" or "CS 29%" (an unknown chance is "—", never 0%).
        case text(String)
        case none
    }

    let playerId: Int
    let name: String
    let colors: Bootstrap.Club.Colors?
    let isGoalkeeper: Bool
    /// "C" or "V".
    var role: String?
    var flagged = false
    var metric: Metric = .none
    /// The full description VoiceOver reads (name, role, opponent, venue, metric).
    let accessibilityLabel: String

    var id: Int { playerId }
}

struct PitchTile: View {
    let model: PitchTileModel
    var height: CGFloat = 91
    var onBench = false
    /// Ringed in gold (the player chosen with "Swap with…").
    var highlighted = false
    /// Text follows Dynamic Type (the Team tab shows the list at accessibility sizes instead).
    @ScaledMetric(relativeTo: .caption2) private var badge: CGFloat = 17

    var body: some View {
        VStack(spacing: 3) {
            KitShirt(colors: model.colors, goalkeeper: model.isGoalkeeper, size: 30)
                .padding(.top, 1)
            // Wraps rather than being cut off (a long surname at a larger text size).
            Text(model.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ToolkitColor.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            metric
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity)
        .frame(minHeight: height)
        .background(onBench ? ToolkitColor.canvas : ToolkitColor.tile, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(onBench ? ToolkitColor.border : ToolkitColor.tileLine))
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(ToolkitColor.accent, lineWidth: 2.5)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let role = model.role {
                Text(role)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(ToolkitColor.onAccent)
                    .frame(width: badge, height: badge)
                    .background(ToolkitColor.accent, in: Circle())
                    .padding(4)
            }
        }
        .overlay(alignment: .topLeading) {
            if model.flagged {
                Text("!")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(ToolkitColor.accent)
                    .padding(.leading, 6)
                    .padding(.top, 3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
    }

    @ViewBuilder private var metric: some View {
        switch model.metric {
        case .fixture(let label, let value, let tone):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 3) {
                    Text(label)
                    if let value { Text(value).fontWeight(.bold) }
                }
                VStack(spacing: 0) {
                    Text(label)
                    if let value { Text(value).fontWeight(.bold) }
                }
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(tone.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, minHeight: 21)
            .background(tone.fill, in: RoundedRectangle(cornerRadius: 5))
        case .text(let text):
            Text(text)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(ToolkitColor.midText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, minHeight: 21)
                .background(ToolkitColor.mid, in: RoundedRectangle(cornerRadius: 5))
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Pitch and bench

/// The starting XI on a pitch, one row per line (keeper, defenders, midfielders, forwards), so
/// any formation lays itself out. Rows of five get narrower tiles; the text doesn't shrink further.
struct SquadPitch: View {
    let rows: [[PitchTileModel]]
    let onSelect: (PitchTileModel) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                TileRowLayout {
                    ForEach(row) { model in
                        Button { onSelect(model) } label: { PitchTile(model: model) }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(PitchBackground())
        .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.card))
        .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card).strokeBorder(ToolkitColor.pitchLine))
    }
}

/// Lays out a line of tiles: four to a row's width, so two or three tiles keep the size of four
/// (centred), and five share the width. Tiles never get narrower than five across.
struct TileRowLayout: Layout {
    var spacing: CGFloat = 5

    private func tileWidth(_ width: CGFloat, count: Int) -> CGFloat {
        let across = CGFloat(max(count, 4))
        return max(0, (width - spacing * (across - 1)) / across)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 350
        let w = tileWidth(width, count: subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = tileWidth(bounds.width, count: subviews.count)
        let total = w * CGFloat(subviews.count) + spacing * CGFloat(max(subviews.count - 1, 0))
        var x = bounds.minX + (bounds.width - total) / 2
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}

/// The pitch: a green gradient with its markings (decorative).
struct PitchBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let line = ToolkitColor.pitchLine.opacity(0.55)
            ZStack {
                LinearGradient(colors: [ToolkitColor.pitchTop, ToolkitColor.pitchBottom],
                               startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(line)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 13)
                Rectangle().fill(line).frame(height: 1).padding(.horizontal, 12)
                Ellipse().strokeBorder(line)
                    .frame(width: size.width * 0.3, height: 70)
                // The penalty area behind the keeper.
                VStack {
                    Rectangle().strokeBorder(line)
                        .frame(width: size.width * 0.42, height: 54)
                        .padding(.top, 13)
                    Spacer()
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The bench: goalkeeper, then the ordered outfield substitutes.
struct BenchStrip: View {
    let tiles: [PitchTileModel]
    let onSelect: (PitchTileModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bench")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ToolkitColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("GK · 1 · 2 · 3")
                    .font(.caption)
                    .foregroundStyle(ToolkitColor.secondaryText)
                    .accessibilityLabel("Goalkeeper, then substitutes 1, 2 and 3")
            }
            TileRowLayout {
                ForEach(tiles) { model in
                    Button { onSelect(model) } label: { PitchTile(model: model, height: 83, onBench: true) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .padding(.top, 6)
    }
}

/// An empty place in a draft: "+" and the position, dashed, the size of a tile.
struct EmptyPitchTile: View {
    let position: Position
    var height: CGFloat = 91
    var onBench = false
    /// Opens the picker; nil when the gameweek can't be edited.
    var onTap: (() -> Void)?

    var body: some View {
        Button { onTap?() } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                Text(position.rawValue)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(onTap == nil ? ToolkitColor.secondaryText : ToolkitColor.link)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background((onBench ? ToolkitColor.canvas : ToolkitColor.tile).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(onTap == nil ? ToolkitColor.border : ToolkitColor.link, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityLabel("Add a \(position.spokenName)\(onBench ? " on the bench" : "")")
    }
}
