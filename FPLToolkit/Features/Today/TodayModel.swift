import Foundation
import Observation

@MainActor
@Observable
final class TodayModel {
    enum Phase {
        case loading
        case loaded(Loaded<Today>)
        case failed(ErrorCopy)
    }

    private(set) var phase: Phase = .loading
    /// A refresh that failed while older results are on screen. The old results stay, labelled.
    private(set) var refreshError: ErrorCopy?

    let entryId: Int
    private let repository: TeamRepository

    init(entryId: Int, repository: TeamRepository) {
        self.entryId = entryId
        self.repository = repository
    }

    func load(bypassCache: Bool = false) async {
        do {
            phase = .loaded(try await repository.today(entryId: entryId, bypassCache: bypassCache))
            refreshError = nil
        } catch let error as APIError {
            if case .loaded = phase {
                refreshError = ErrorCopy(error)
            } else {
                phase = .failed(ErrorCopy(error))
            }
        } catch {
            // Cancelled (e.g. the view went away): leave the state as it was.
        }
    }

    func retry() async {
        phase = .loading
        await load(bypassCache: true)
    }
}
