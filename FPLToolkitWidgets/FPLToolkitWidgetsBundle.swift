import SwiftUI
import WidgetKit

/// FPLToolkit's widget extension: the Matchday Live Activity (Lock Screen, Dynamic Island,
/// StandBy). A Home Screen widget can join it later.
@main
struct FPLToolkitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MatchdayLiveActivity()
    }
}
