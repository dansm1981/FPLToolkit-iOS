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
            .background(ToolkitColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.card))
            .overlay(RoundedRectangle(cornerRadius: ToolkitRadius.card)
                .strokeBorder(ToolkitColor.border, lineWidth: 1))
    }
}

struct ToolkitPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(ToolkitColor.onAccent)
            .padding(.horizontal, ToolkitSpace.page)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(ToolkitColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: ToolkitRadius.button))
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.82 : 1)
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
        Text(text.uppercased())
            .font(.footnote.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(ToolkitColor.secondaryText)
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
    /// The app's page background (tk.bg) behind scrolling content.
    func toolkitScreen() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(ToolkitColor.canvas.ignoresSafeArea())
            .toolbarBackground(ToolkitColor.canvas, for: .navigationBar)
    }
}
