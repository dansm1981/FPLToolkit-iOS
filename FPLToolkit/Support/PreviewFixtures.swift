#if DEBUG
import Foundation

/// Loads the captured API responses in Fixtures/api-v1 for SwiftUI previews.
/// Previews run on the Mac, so this reads straight from the repo instead of bundling the files in the app.
enum PreviewFixtures {
    static func load<T: Decodable & Sendable>(_ name: String, as type: T.Type) -> Loaded<T> {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // FPLToolkit
            .deletingLastPathComponent() // repo root
        let url = repoRoot.appending(path: "Fixtures/api-v1/\(name).json")
        do {
            let envelope = try APIClient.decode(Envelope<T>.self, from: Data(contentsOf: url))
            return Loaded(value: envelope.data, meta: envelope.meta, savedAt: nil)
        } catch {
            fatalError("Preview fixture \(name): \(error)")
        }
    }
}
#endif
