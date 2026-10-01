// FPL Toolkit visual system v1.0, from design/visual-development-pack/developer/ToolkitTheme.swift.
// Colours are the adaptive "tk.*" sets in Assets.xcassets (dark and light).
import SwiftUI

enum ToolkitColor {
    static let canvas = Color("tk.bg")
    static let surface = Color("tk.surface")
    static let raised = Color("tk.raised")
    static let border = Color("tk.line")
    static let primaryText = Color("tk.text")
    static let secondaryText = Color("tk.muted")
    static let accent = Color("tk.gold")
    static let onAccent = Color("tk.goldInk")
    static let link = Color("tk.accentText")
    static let information = Color("tk.blue")
    static let informationFill = Color("tk.blueBg")
    static let warning = Color("tk.amber")
    static let warningFill = Color("tk.amberBg")
    static let error = Color("tk.red")
    static let errorFill = Color("tk.redBg")
    static let positive = Color("tk.green")
    static let positiveFill = Color("tk.greenBg")
    static let nav = Color("tk.nav")
    /// Destructive swipe buttons (white text): a deep red that reads in light and dark mode.
    /// The app tint would otherwise make them gold, and the dark-mode red is too pale for white text.
    static let destructiveAction = Color(red: 0.639, green: 0.153, blue: 0.239)
}

extension DynamicTypeSize {
    /// The sizes where side-by-side rows run out of width (xxLarge and up, Dan's own setting
    /// included): rows put their details on full-width lines under the name instead. Below this
    /// the layouts are unchanged.
    var stacksRows: Bool { self >= .xxLarge }
}

enum ToolkitSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let page: CGFloat = 20
    static let xl: CGFloat = 24
    static let section: CGFloat = 32
}

enum ToolkitRadius {
    static let card: CGFloat = 18
    static let button: CGFloat = 15
    static let pill: CGFloat = 8
}

struct ToolkitCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(ToolkitSpace.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolkitCard()
    }
}

struct ToolkitPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            // Disabled: a muted but still readable button, not a faded gold one (contrast).
            .foregroundStyle(isEnabled ? ToolkitColor.onAccent : ToolkitColor.secondaryText)
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? ToolkitColor.accent : ToolkitColor.raised)
            .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.button))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct ToolkitSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(ToolkitColor.primaryText)
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(ToolkitColor.raised)
            .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.button))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.button)
                .strokeBorder(ToolkitColor.border, lineWidth: 1))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.82 : 1)
    }
}

/// A small uppercase label on a tinted fill, e.g. "AVAILABILITY" or "LAST PUBLISHED · GW5".
struct Pill: View {
    let text: String
    var foreground: Color = ToolkitColor.information
    var fill: Color = ToolkitColor.informationFill

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.pill))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        // Uppercased, but "xFDR" keeps its casing.
        Text(text.uppercased().replacingOccurrences(of: "XFDR", with: "xFDR"))
            .font(.footnote.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(ToolkitColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The brand mark plus the app name, as in the top-left of S01/S05.
struct BrandLockup: View {
    var markSize: CGFloat = 28
    var body: some View {
        HStack(spacing: ToolkitSpace.md) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: markSize, height: markSize)
                .accessibilityHidden(true)
            Text("FPLToolkit")
                .font(.title3.weight(.bold))
                .foregroundStyle(ToolkitColor.primaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

extension TeamInsight.Tone {
    var foreground: Color {
        switch self {
        case .bad: ToolkitColor.error
        case .warn: ToolkitColor.warning
        case .good: ToolkitColor.positive
        case .info: ToolkitColor.information
        }
    }
    var fill: Color {
        switch self {
        case .bad: ToolkitColor.errorFill
        case .warn: ToolkitColor.warningFill
        case .good: ToolkitColor.positiveFill
        case .info: ToolkitColor.informationFill
        }
    }
}

extension View {
    /// The app's page background: rich navy with a quiet glow at the top (design v2), behind
    /// scrolling content.
    func toolkitScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ToolkitScreenBackground().ignoresSafeArea())
            .toolbarBackground(ToolkitColor.canvas, for: .navigationBar)
    }
}

/// tk.bgTop fading into tk.bg over the first few hundred points.
struct ToolkitScreenBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            ToolkitColor.canvas
            LinearGradient(colors: [Color("tk.bgTop"), ToolkitColor.canvas], startPoint: .top, endPoint: .bottom)
                .frame(height: 420)
        }
    }
}

/// Fixture difficulty colours: the website's five bands (its `--fdr-1` … `--fdr-5`), the same in
/// light and dark. The number drawn on them is dark on the two greens and white on the rest, which
/// keeps every band above 4.5:1 (the website's white on dark green is 3.2:1).
enum DifficultyColor {
    static func fill(_ band: Int) -> Color {
        switch band {
        case ...1: Color(red: 0.000, green: 0.634, blue: 0.308)
        case 2: Color(red: 0.251, green: 0.802, blue: 0.427)
        case 3: Color(red: 0.412, green: 0.450, blue: 0.491)
        case 4: Color(red: 0.831, green: 0.047, blue: 0.103)
        default: Color(red: 0.565, green: 0.000, blue: 0.000)
        }
    }

    static func text(_ band: Int) -> Color {
        band <= 2 ? Color(red: 0.011, green: 0.057, blue: 0.020) : .white
    }
}
