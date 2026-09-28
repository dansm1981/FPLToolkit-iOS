import ImageIO
import SwiftUI
import UIKit

/// Player photos and club logos. They come from our own API (`images/players/{id}`,
/// `images/clubs/{id}`), which serves API-Football's images, so the app still talks to nothing
/// else. The loader keeps a disk cache that follows the server's week-long caching, plus a
/// memory cache of images already shrunk to the size they're shown at.
actor ImageLoader {
    static let shared = ImageLoader()

    private enum Outcome: Sendable {
        case image(CGImage)
        case missing
        case failed
    }

    private let session: URLSession
    private var memory: [String: CGImage] = [:]
    private var missing: Set<URL> = []
    private var inFlight: [String: Task<Outcome, Never>] = [:]

    init() {
        let config = URLSessionConfiguration.default
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "images", directoryHint: .isDirectory)
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 64 << 20, directory: directory)
        config.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: config)
    }

    /// The image at `url` no wider than `maxPixels`, or nil when there isn't one (or the network
    /// failed: that isn't remembered, so the next view tries again).
    func image(at url: URL, maxPixels: Int) async -> CGImage? {
        let key = "\(url.absoluteString)#\(maxPixels)"
        if let hit = memory[key] { return hit }
        if missing.contains(url) { return nil }
        let task = inFlight[key] ?? Task { [session] in await Self.fetch(url, maxPixels: maxPixels, session: session) }
        inFlight[key] = task
        let outcome = await task.value
        inFlight[key] = nil
        switch outcome {
        case .image(let image):
            if memory.count > 600 { memory.removeAll(keepingCapacity: true) }
            memory[key] = image
            return image
        case .missing:
            missing.insert(url)
            return nil
        case .failed:
            return nil
        }
    }

    private static func fetch(_ url: URL, maxPixels: Int, session: URLSession) async -> Outcome {
        guard let (data, response) = try? await session.data(from: url),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failed }
        if status == 404 { return .missing }
        guard status == 200, let image = downsample(data, maxPixels: maxPixels) else { return .failed }
        return .image(image)
    }

    /// Decodes straight to the display size, so a 150 px photo in a 32 pt row costs 96 px.
    nonisolated static func downsample(_ data: Data, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixels),
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}

extension APIClient {
    /// A `photo` or `logo` path from the API (relative to the v1 base) as a full URL.
    func imageURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }
}

/// Loads one image for a view at its display size.
private struct RemoteImage: View {
    let path: String?
    let side: CGFloat
    let contentMode: ContentMode
    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .frame(width: side, height: side)
        .task(id: path) {
            guard let url = APIClient.configured.imageURL(path) else {
                image = nil
                return
            }
            image = await ImageLoader.shared.image(at: url, maxPixels: Int((side * displayScale).rounded(.up)))
        }
    }
}

/// A player's photo in a circle. Without one, the circle shows their club's logo, so a missing
/// photo never looks broken. Decorative: the player's name is always shown and read out beside it.
struct PlayerPhoto: View {
    let path: String?
    var clubLogo: String? = nil
    var size: CGFloat = 32
    /// Off when `size` already follows the text size (e.g. the pitch tiles' scaled circle).
    var scalesWithText = true
    @ScaledMetric(relativeTo: .body) private var unit: CGFloat = 1

    var body: some View {
        let side = scalesWithText ? (size * min(unit, 1.5)).rounded() : size
        ZStack {
            Circle().fill(ToolkitColor.raised)
            if path != nil {
                RemoteImage(path: path, side: side, contentMode: .fill)
                    .background(Color.white)
            } else if clubLogo != nil {
                RemoteImage(path: clubLogo, side: side * 0.62, contentMode: .fit)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ToolkitColor.border, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// A club's logo at text size. Decorative: the club's name is always shown or read out beside it.
struct ClubLogo: View {
    @Environment(AppModel.self) private var appModel
    let clubId: Int?
    var size: CGFloat = 16
    @ScaledMetric(relativeTo: .subheadline) private var unit: CGFloat = 1

    var body: some View {
        if let path = appModel.club(clubId)?.logo {
            RemoteImage(path: path, side: (size * min(unit, 1.5)).rounded(), contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}

/// The logo beside a line of text that starts with the club's short name
/// (e.g. "CHE · MID · £5.5"). Without a logo it's just the text.
struct ClubLabel: View {
    let clubId: Int?
    let text: String
    var logoSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 4) {
            ClubLogo(clubId: clubId, size: logoSize)
            Text(text)
        }
    }
}
