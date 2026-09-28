import Foundation
import Testing
import UIKit
@testable import FPLToolkit

/// Player photos and club logos (Phase 3, P3-1; happy-backend-pal#35).
struct ImageTests {
    @Test func photoAndLogoDecode() throws {
        let player = #"""
        {"id":426,"webName":"B.Fernandes","photo":"images/players/426?v=tm195r","clubId":16,"position":"MID",
         "price":9.1,"availability":{"code":"a","level":"ok","chanceNext":null,"news":null},
         "selectedByPct":30.1,"nextFixture":null}
        """#
        let decoded = try APIClient.decode(PlayerSummary.self, from: Data(player.utf8))
        #expect(decoded.photo == "images/players/426?v=tm195r")

        // Older payloads (and players without a provider photo) have no photo.
        let bare = player.replacingOccurrences(of: #""photo":"images/players/426?v=tm195r","#, with: "")
        #expect(try APIClient.decode(PlayerSummary.self, from: Data(bare.utf8)).photo == nil)
        let null = player.replacingOccurrences(of: #""images/players/426?v=tm195r""#, with: "null")
        #expect(try APIClient.decode(PlayerSummary.self, from: Data(null.utf8)).photo == nil)

        let club = #"{"id":1,"name":"Arsenal","shortName":"ARS","logo":"images/clubs/1?v=tm1c6w"}"#
        #expect(try APIClient.decode(Bootstrap.Club.self, from: Data(club.utf8)).logo == "images/clubs/1?v=tm1c6w")
        let plainClub = #"{"id":1,"name":"Arsenal","shortName":"ARS"}"#
        #expect(try APIClient.decode(Bootstrap.Club.self, from: Data(plainClub.utf8)).logo == nil)
    }

    @Test func pathsResolveAgainstTheAPIBase() {
        let client = APIClient.production
        #expect(client.imageURL("images/players/426?v=tm195r")?.absoluteString
            == "https://www.fpltoolkit.co.uk/api/mobile/v1/images/players/426?v=tm195r")
        #expect(client.imageURL("images/clubs/1")?.absoluteString
            == "https://www.fpltoolkit.co.uk/api/mobile/v1/images/clubs/1")
        #expect(client.imageURL(nil) == nil)
        #expect(client.imageURL("") == nil)
        let local = APIClient(baseURL: URL(string: "http://127.0.0.1:5199/api/mobile/v1/")!)
        #expect(local.imageURL("images/clubs/3")?.absoluteString == "http://127.0.0.1:5199/api/mobile/v1/images/clubs/3")
    }

    @Test func imagesAreDecodedAtDisplaySize() throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 150, height: 150), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }()).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 150, height: 150))
        }
        let small = try #require(ImageLoader.downsample(png, maxPixels: 96))
        #expect(small.width == 96 && small.height == 96)
        // Never scaled up past the source.
        let full = try #require(ImageLoader.downsample(png, maxPixels: 400))
        #expect(full.width == 150)
        #expect(ImageLoader.downsample(Data("not an image".utf8), maxPixels: 96) == nil)
    }
}
