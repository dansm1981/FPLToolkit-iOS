import Foundation

/// The fixture switches: Toolkit's xFDR or FPL's official FDR, and xFDR's variant. The device keeps
/// the choice and sends it with every planner request; the server rates the fixtures, so the numbers
/// always match the website's. Names follow Dan's note of 29 Sep: xFDR has Overall, Attack and
/// Defence variants (the server's match, attack and clean_sheet lenses), the active one is always
/// labelled, and official FDR stays a separate, clearly named option.
struct FixtureView: Hashable, Sendable {
    enum Model: String, CaseIterable, Identifiable, Sendable {
        case xfdr, fpl
        var id: String { rawValue }
        var label: String {
            switch self {
            case .xfdr: "xFDR"
            case .fpl: "Official FDR"
            }
        }
    }

    enum Lens: String, CaseIterable, Identifiable, Sendable {
        case position, match, attack
        case cleanSheet = "clean_sheet"
        var id: String { rawValue }
        var label: String {
            switch self {
            // "By position" until batch 3 (Dan's choice, 30 Sep); each row still says which it uses.
            case .position: "Auto"
            case .match: "Overall"
            case .attack: "Attack"
            case .cleanSheet: "Defence"
            }
        }
    }

    static let modelKey = "fixtures.model"
    static let lensKey = "fixtures.lens"

    var model: Model = .xfdr
    var lens: Lens = .position

    /// The saved choice; xFDR · Auto (by position, the website's default) until one is made.
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

    /// "xFDR · Auto", or "Official FDR" (the variant only changes xFDR).
    var summary: String { model == .fpl ? model.label : "\(model.label) · \(lens.label)" }

    /// The variant a player sees under this choice: Auto means Defence for goalkeepers
    /// and defenders and Attack for midfielders and forwards.
    func label(for position: Position) -> String {
        guard model == .xfdr else { return model.label }
        guard lens == .position else { return summary }
        return "xFDR · " + (position == .gk || position == .def ? "Defence" : "Attack")
    }
}

extension FixtureDifficulty.XFDR.Lens {
    /// The variant's name, as the fixture itself reports it.
    var variant: String? {
        switch self {
        case .match: "Overall"
        case .attack: "Attack"
        case .cleanSheet: "Defence"
        case .unknown: nil
        }
    }
}

extension FixtureDifficulty.XFDR {
    /// "xFDR · Defence", or "Official FDR" where FPL's own rating stands in.
    var modelLabel: String {
        if source == .fpl { return "Official FDR" }
        return lens.variant.map { "xFDR · \($0)" } ?? "xFDR"
    }
}

extension FixtureDifficulty.XFDR {
    /// As the website writes it: xFDR to one decimal place, FPL's difficulty as a whole number.
    var display: String {
        source == .fpl ? String(Int(value.rounded())) : value.formatted(.number.precision(.fractionLength(1)))
    }
}
