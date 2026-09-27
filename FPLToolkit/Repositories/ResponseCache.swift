import Foundation

/// The last good response per endpoint, as raw bytes on disk. The file's modification
/// date is when it was saved. Anything read back is shown as "Saved at …", never as fresh.
struct ResponseCache: Sendable {
    let directory: URL

    static let shared = ResponseCache(
        directory: URL.cachesDirectory.appending(path: "api-v1", directoryHint: .isDirectory))

    func write(_ data: Data, for path: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: path), options: .atomic)
        } catch {
            // A failed cache write only means less offline data; never fail the request for it.
        }
    }

    func read(_ path: String) -> (data: Data, savedAt: Date)? {
        let url = fileURL(for: path)
        guard let data = try? Data(contentsOf: url),
              let savedAt = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        else { return nil }
        return (data, savedAt)
    }

    func remove(_ path: String) {
        try? FileManager.default.removeItem(at: fileURL(for: path))
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(for path: String) -> URL {
        directory.appending(path: path.replacingOccurrences(of: "/", with: "_") + ".json")
    }
}
