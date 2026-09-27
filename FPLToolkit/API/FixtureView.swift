import Foundation

/// The website's fixture switches: FPL FDR or xFDR, and the lens. The device keeps the choice (the
/// website keeps it in the browser) and sends it with every planner request; the server rates the
/// fixtures, so the numbers always match the website's.
struct FixtureView: Hashable, Sendable {
    enum Model: String, CaseIterable, Identifiable, Sendable {
        case xfdr, fpl
        var id: String { rawValue }
        var label: String {
            switch self {
            case .xfdr: "xFDR"
            case .fpl: "FPL FDR"
            }
        }
    }

    enum Lens: String, CaseIterable, Identifiable, Sendable {
        case position, match, attack
        case cleanSheet = "clean_sheet"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .position: "By position"
            case .match: "Match"
            case .attack: "Attack"
            case .cleanSheet: "Clean sheet"
            }
        }
    }

    static let modelKey = "fixtures.model"
    static let lensKey = "fixtures.lens"

    var model: Model = .xfdr
    var lens: Lens = .position

    /// The saved choice; xFDR by position (the website's default) until one is made.
    nonisolated static var current: FixtureView {
        let defaults = UserDefaults.standard
        return FixtureView(
            model: defaults.string(forKey: modelKey).flatMap(Model.init(rawValue:)) ?? .xfdr,
            lens: defaults.string(forKey: lensKey).flatMap(Lens.init(rawValue:)) ?? .position
        )
    }

    nonisolated var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "model", value: model.rawValue), URLQueryItem(name: "lens", value: lens.rawValue)]
    }

    /// "xFDR · By position", or "FPL FDR" (the lens only changes xFDR).
    var summary: String { model == .fpl ? model.label : "\(model.label) · \(lens.label)" }
}

extension FixtureDifficulty.XFDR {
    /// As the website writes it: xFDR to one decimal place, FPL's difficulty as a whole number.
    var display: String {
        source == .fpl ? String(Int(value.rounded())) : value.formatted(.number.precision(.fractionLength(1)))
    }
}
