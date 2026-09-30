import SwiftUI

/// The website's player insights (/insights): every player, sorted by any of the website's columns.
/// Batch 3 opened it straight on the players (the opportunity map and its top 12 went) with the
/// finder's fuller filters, shared with the Shortlist's "All players".
struct PlayerInsightsView: View {
    var body: some View {
        PlayerFinder(advanced: true)
            .toolkitScreen()
            .navigationTitle("Player insights")
            .navigationBarTitleDisplayMode(.inline)
    }
}
