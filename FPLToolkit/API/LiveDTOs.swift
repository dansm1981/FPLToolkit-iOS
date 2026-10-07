import Foundation

// MARK: - Live team (contract §24; happy-backend-pal#36, #37)

/// One team's live gameweek. Every judgement (score, substitutions, bonus, what's close) is the
/// server's; the app lays it out.
struct LiveTeam: Decodable, Sendable {
    enum Status: String, FallbackDecodable {
        case upcoming, live, between, awaitingBonus, finished
        case unknown
        static let fallback = Self.unknown
    }

    struct Total: Decodable, Sendable, Hashable {
        /// confirmed + provisionalBonus.
        let estimated: Int
        /// FPL-recorded points × multipliers − transfer cost.
        let confirmed: Int
        let provisionalBonus: Int
        let transferCost: Int
        let benchPoints: Int
    }

    struct NextPoints: Decodable, Sendable, Hashable {
        struct Defcon: Decodable, Sendable, Hashable {
            let count: Int
            let threshold: Int
            let reached: Bool
        }
        struct Saves: Decodable, Sendable, Hashable {
            let count: Int
            let toNextPoint: Int
        }
        struct Bonus: Decodable, Sendable, Hashable {
            let provisional: Int
            let bps: Int
            let bpsToNext: Int?
        }
        struct CleanSheet: Decodable, Sendable, Hashable {
            let conceded: Int
            let alive: Bool
        }
        let defcon: Defcon?
        let saves: Saves?
        let bonus: Bonus?
        let cleanSheet: CleanSheet?
    }

    struct Player: Decodable, Sendable, Identifiable, Hashable {
        enum State: String, FallbackDecodable {
            case blank, notStarted, inPlay, done
            case unknown
            static let fallback = Self.unknown
        }
        enum Lineup: String, FallbackDecodable {
            case starting, bench, notInSquad
            case unknown
            static let fallback = Self.unknown
        }
        enum AutoSub: String, FallbackDecodable {
            case `in`, out
            case unknown
            static let fallback = Self.unknown
        }
        struct Breakdown: Decodable, Sendable, Hashable {
            let fixtureId: Int
            let stat: String
            let value: Double
            let points: Int
        }
        /// FPL's counts for the gameweek (happy-backend-pal#47): everything the player did,
        /// points or not; a double gameweek adds both matches.
        struct Line: Decodable, Sendable, Hashable {
            let minutes: Int
            let goals: Int
            let assists: Int
            let cleanSheets: Int
            let goalsConceded: Int
            let ownGoals: Int
            let penaltiesSaved: Int
            let penaltiesMissed: Int
            let yellowCards: Int
            let redCards: Int
            let saves: Int
            let bonus: Int
            let bps: Int
            let defensiveContribution: Int
            let clearancesBlocksInterceptions: Int
            let recoveries: Int
            let tackles: Int
            let expectedGoals: Double
            let expectedAssists: Double
        }
        struct Context: Decodable, Sendable, Hashable {
            let rating: String?
            let shots: Int?
            let shotsOn: Int?
            let keyPasses: Int?
            let tackles: Int?
            let interceptions: Int?
            let saves: Int?
        }

        let playerId: Int
        /// 1–11 starting, 12–15 bench in order.
        let position: Int
        let counted: Bool
        let multiplier: Int
        let isCaptain: Bool
        let isViceCaptain: Bool
        let autoSub: AutoSub?
        let state: State
        let minutes: Int
        /// FPL-recorded.
        let points: Int
        /// Toolkit estimate, not yet in `points`.
        let provisionalBonus: Int
        /// Football context; nil while not yet reported.
        let lineup: Lineup?
        let fixtureIds: [Int]
        let next: NextPoints
        let breakdown: [Breakdown]
        /// Nil from servers before happy-backend-pal#47.
        let line: Line?
        let context: Context?

        var id: Int { playerId }
    }

    struct Fixture: Decodable, Sendable, Identifiable, Hashable {
        enum State: String, FallbackDecodable {
            case notStarted, inPlay, finished
            case unknown
            static let fallback = Self.unknown
        }
        let id: Int
        let homeClubId: Int
        let awayClubId: Int
        let kickoff: Date?
        let state: State
        let minute: Int?
        let homeScore: Int?
        let awayScore: Int?
        let bonusConfirmed: Bool
    }

    struct Moment: Decodable, Sendable, Identifiable, Hashable {
        enum Kind: String, FallbackDecodable {
            case goal, ownGoal, assist, penaltyMissed, redCard, subbedOff, subbedOn, defcon, cleanSheetLost, bonus
            case unknown
            static let fallback = Self.unknown
        }
        enum State: String, FallbackDecodable {
            case reported, confirmed, withdrawn
            case unknown
            static let fallback = Self.unknown
        }
        /// Stable across refreshes: the same event keeps its id when its state changes.
        let id: String
        let kind: Kind
        let fixtureId: Int
        let playerId: Int?
        let minute: Int?
        let state: State
        let players: [Int]?
        let points: Int?
    }

    /// One line of the live feed (happy-backend-pal#61; contract §32). The server writes the text,
    /// detail and points; the app only lays them out.
    struct FeedItem: Decodable, Sendable, Identifiable, Hashable {
        enum Kind: String, FallbackDecodable {
            case lineup, kickOff, halfTime, fullTime
            case goal, ownGoal, assist, penaltyMissed, penaltySaved, yellowCard, redCard
            case subbedOff, subbedOn
            case defcon, save, sixtyMinutes, cleanSheet, cleanSheetLost
            case bonusPosition, bonus
            case unknown
            static let fallback = Self.unknown
        }
        /// The app's filters; `match` items show under All only; `watching` is players to watch;
        /// `rivals` is a player only your rivals count.
        enum Group: String, FallbackDecodable {
            case goals, defence, bonus, lineups, match, watching, rivals
            case unknown
            static let fallback = Self.unknown
        }
        /// Stable across refreshes.
        let id: String
        let kind: Kind
        let group: Group
        let fixtureId: Int
        let playerId: Int?
        let minute: Int?
        let at: Date
        let state: Moment.State
        let text: String
        let detail: String?
        /// The points it's worth to the player (before the captain's multiplier); nil when none change.
        let points: Int?
        let players: [Int]?
        let lineup: Player.Lineup?
        /// A watched player's item (group `watching`): why they're watched, e.g. "54% owned".
        var watching: String?
        /// What it did to each saved rival, featured first (happy-backend-pal#68).
        var rivals: [RivalEffect]?
        /// What it did to your estimated overall rank, "↑18k" (Matchday v2 phase 3).
        var rankChangeText: String?
    }

    /// One event's effect on one rivalry: its points × (your multiplier − theirs).
    struct RivalEffect: Decodable, Sendable, Hashable {
        let entryId: Int
        let name: String
        /// Positive helps you.
        let effect: Int
        /// "Gains Andy 12 on you: Andy's captain".
        let text: String
    }

    /// Your saved rivals on the live matchday (`?rivals=1` with this device; happy-backend-pal#68).
    struct Rivals: Decodable, Sendable, Hashable {
        struct Situation: Decodable, Sendable, Hashable, Identifiable {
            enum Kind: String, FallbackDecodable {
                case defcon, saves, bonus
                case unknown
                static let fallback = Self.unknown
            }
            let kind: Kind
            let playerId: Int
            /// Positive helps you, if it happens.
            let effect: Int
            /// "One more defensive action for Hall would gain you 2 on Andy, putting you ahead".
            let text: String
            var id: String { "\(kind.rawValue)-\(playerId)" }
        }
        struct ComingUp: Decodable, Sendable, Hashable, Identifiable {
            let fixtureId: Int
            let kickoff: Date?
            let yours: [Int]
            let theirs: [Int]
            /// "ARS v CHE · you have Saka; Andy has Palmer ×2".
            let text: String
            var id: Int { fixtureId }
        }
        struct Featured: Decodable, Sendable, Hashable {
            let entryId: Int
            let name: String
            /// "You've overtaken Andy", or the latest event that moved it.
            let changed: String?
            let now: [Situation]
            let next: [ComingUp]
        }
        /// Every saved rival, featured first.
        let rows: [RivalSummary]
        let featured: Featured?
    }

    /// Matchday's players to watch (happy-backend-pal#66; contract §34): the groups switched on in
    /// Settings → Notifications → Live matchday, each with its players' live figures.
    struct Watching: Decodable, Sendable, Hashable {
        let groups: [Group]

        struct Group: Decodable, Sendable, Hashable, Identifiable {
            enum Kind: String, FallbackDecodable {
                case highlyOwned, eliteDifferentials, rivals
                case unknown
                static let fallback = Self.unknown
            }
            let kind: Kind
            let title: String
            let detail: String?
            let players: [WatchedPlayer]
            let rivals: [Rival]
            var id: String { kind.rawValue }
        }

        /// One watched player: live figures and why they're there ("54% owned").
        struct WatchedPlayer: Decodable, Sendable, Hashable, Identifiable {
            let playerId: Int
            let reason: String
            let points: Int
            let minutes: Int
            let state: Player.State
            let provisionalBonus: Int
            var id: Int { playerId }
        }

        /// A mini-league rival: where they stand, their live gameweek, their captain and the
        /// players they have that you don't.
        struct Rival: Decodable, Sendable, Hashable, Identifiable {
            let entryId: Int
            let manager: String?
            let team: String?
            let rank: Int?
            /// "1st · leader · 12 pts ahead of you".
            let label: String
            /// FPL total at the league's last sync.
            let total: Int?
            /// Their live gameweek score, FPL-recorded; nil until their picks for it are synced.
            let live: Int?
            /// Toolkit's estimate of their bonus to come, kept out of `live`.
            let provisionalBonus: Int
            let captainId: Int?
            let players: [WatchedPlayer]
            var id: Int { entryId }
        }
    }

    struct Headline: Decodable, Sendable, Hashable {
        let text: String
        let kind: String
    }

    /// Matchday v2's Pulse (happy-backend-pal#86; tasks/matchday-v2.md): what matters now, the
    /// points within reach and the latest moments, worded by the server.
    struct Pulse: Decodable, Sendable, Hashable {
        struct Item: Decodable, Sendable, Hashable, Identifiable {
            enum Tone: String, FallbackDecodable {
                case upside, danger
                case unknown
                static let fallback = Self.unknown
            }
            let id: String
            /// defcon, saves, bonus, sixty or cleanSheet.
            let kind: String
            let playerId: Int
            /// "Hall · 9/10 DEFCON"
            let title: String
            /// "One more action = +2"
            let detail: String
            /// Points at stake for you, the captain's multiplier included.
            let stake: Int
            let tone: Tone
            /// 0–1 for a progress bar.
            let progress: Double?
        }
        struct Moment: Decodable, Sendable, Hashable, Identifiable {
            /// The feed item's id.
            let id: String
            let playerId: Int?
            let text: String
            /// "+10 points as captain"
            let detail: String?
            let at: Date
            /// What it did to your estimated overall rank, "↑18k" (phase 3).
            var rankChangeText: String?
        }
        /// "If nothing changes…" (happy-backend-pal#87): the matches in play ending as they stand,
        /// players still to play scoring as projected.
        struct EndState: Decodable, Sendable, Hashable {
            struct Rival: Decodable, Sendable, Hashable {
                let entryId: Int
                let name: String
                let points: Int
                /// Positive: you'd win the gameweek.
                let margin: Int
            }
            let points: Int
            let stillToPlay: Int
            let basis: String
            let rival: Rival?
        }
        /// Recaps (phase 2): a finished spell between spells, and the gameweek's story at the end.
        struct Recap: Decodable, Sendable, Hashable {
            struct Moment: Decodable, Sendable, Hashable {
                let id: String
                let text: String
                let detail: String
            }
            struct Spell: Decodable, Sendable, Hashable {
                struct Rival: Decodable, Sendable, Hashable {
                    let entryId: Int
                    let name: String
                    /// Positive: you gained on them.
                    let swing: Int
                }
                struct Next: Decodable, Sendable, Hashable {
                    let kickoff: Date
                    let playerIds: [Int]
                }
                let start: Date
                let title: String
                let points: Int
                /// What the spell did to your estimated overall rank, "↑18k" (phase 3).
                var rankChangeText: String?
                let rival: Rival?
                let best: Moment?
                let next: Next?
            }
            struct Final: Decodable, Sendable, Hashable {
                struct Rival: Decodable, Sendable, Hashable {
                    let entryId: Int
                    let name: String
                    let you: Int
                    let them: Int
                    let margin: Int
                }
                struct Gain: Decodable, Sendable, Hashable {
                    let playerId: Int
                    let points: Int
                }
                struct Bench: Decodable, Sendable, Hashable {
                    let points: Int
                    let playerId: Int?
                }
                /// Overall rank before the gameweek and the estimate now (phase 3).
                struct Rank: Decodable, Sendable, Hashable {
                    let before: Int?
                    let after: Int
                    /// "~327k"
                    let text: String
                    /// "↑18k"
                    let movementText: String?
                }
                let gameweek: Int
                let points: Int
                var rank: Rank?
                let confirmed: Bool
                let rival: Rival?
                let decided: Moment?
                let biggestGain: Gain?
                let benchPain: Bench?
            }
            let spell: Spell?
            let final: Final?
        }
        /// Your chance of winning the gameweek against your featured rival (phase 3).
        struct WinProbability: Decodable, Sendable, Hashable {
            let entryId: Int
            let name: String
            /// 0–1, a draw counting half.
            let you: Double
            let draw: Double
            let basis: String

            /// Whole percentages that add up to 100.
            var youPercent: Int { Int((you * 100).rounded()) }
            var themPercent: Int { 100 - youPercent }
        }
        let whatMattersNow: [Item]
        let nextPoints: [Item]
        let justHappened: [Moment]
        var ifNothingChanges: EndState?
        var recap: Recap?
        var winProbability: WinProbability?
    }

    /// The live overall rank estimate (Matchday v2 phase 3): always called an estimate.
    struct Rank: Decodable, Sendable, Hashable {
        let estimate: Int
        /// Overall rank after last gameweek; nil in a first gameweek.
        let previous: Int?
        /// Places moved since (positive: up).
        let movement: Int?
        /// "~327k"
        let text: String
        /// "↑18k"
        let movementText: String?
        /// Sampled managers behind it.
        let sample: Int
        /// How it's worked out, for the info sheet.
        let basis: String
    }

    /// Where you'd be in a saved mini-league if the gameweek ended now (phase 3).
    struct League: Decodable, Sendable, Hashable, Identifiable {
        struct Above: Decodable, Sendable, Hashable {
            let name: String
            let gap: Int
        }
        struct Below: Decodable, Sendable, Hashable {
            let name: String
            let lead: Int
        }
        let id: Int
        let name: String
        let members: Int
        /// Your position after last gameweek.
        let before: Int?
        let now: Int
        let above: Above?
        let below: Below?
        /// Places moved since last gameweek (positive: up).
        let movement: Int?
        /// "2nd, up from 3rd"
        let text: String
        /// "5 behind Pete", "Top by 10 from Andy".
        let detail: String?
    }

    struct Substitution: Decodable, Sendable, Hashable {
        let `in`: Int
        let out: Int
    }

    let entryId: Int
    let gameweek: Int
    let status: Status
    /// The single most relevant thing right now (the Lock Screen's second line); nil from servers
    /// before happy-backend-pal#39.
    let headline: Headline?
    let chip: String?
    let total: Total
    let captainId: Int?
    let playing: Int
    let toPlay: Int
    let autoSubs: [Substitution]
    let squad: [Player]
    let fixtures: [Fixture]
    let moments: [Moment]
    /// Everything that happened to the squad, newest first; nil from servers before
    /// happy-backend-pal#61 (Matchday then shows the moments).
    let feed: [FeedItem]?
    /// Only when the request asked for players to watch.
    var watching: Watching?
    /// Only with `?rivals=1` from this team's own device.
    var rivals: Rivals?
    /// Matchday v2's Pulse; nil from servers before happy-backend-pal#86.
    var pulse: Pulse?
    /// The live overall rank estimate; nil until the gameweek's sample is in (phase 3).
    var rank: Rank?
    /// Your saved mini-leagues live; only with `?rivals=1` from this team's own device (phase 3).
    var leagues: [League]?
    let players: [String: PlayerSummary]
    /// Only on a live matchday replay: what's being replayed and how far through it is.
    var replay: Replay?

    /// A replay's position (happy-backend-pal#58).
    struct Replay: Decodable, Sendable, Hashable {
        let id: String
        let label: String
        /// The moment shown, in the original matchday's time.
        let at: Date
        let elapsedSeconds: Int
        let durationSeconds: Int
    }

    func player(_ id: Int?) -> PlayerSummary? { id.flatMap { players[String($0)] } }
    func fixture(_ id: Int) -> Fixture? { fixtures.first { $0.id == id } }
}

// MARK: - One match's stats (happy-backend-pal#47)

/// A match's FPL tables for the Matches tab: most first in each list.
struct MatchStats: Decodable, Sendable {
    enum Side: String, FallbackDecodable {
        case home, away
        case unknown
        static let fallback = Self.unknown
    }

    struct Entry: Decodable, Sendable, Hashable {
        let playerId: Int
        let side: Side
        let value: Int
    }

    struct Defcon: Decodable, Sendable, Hashable {
        let playerId: Int
        let side: Side
        let value: Int
        let threshold: Int
        let reached: Bool
    }

    let fixtureId: Int
    let homeClubId: Int
    let awayClubId: Int
    let homeScore: Int?
    let awayScore: Int?
    let state: LiveTeam.Fixture.State
    let minute: Int?
    let goals: [Entry]
    let assists: [Entry]
    let ownGoals: [Entry]
    let penaltiesSaved: [Entry]
    let penaltiesMissed: [Entry]
    let yellowCards: [Entry]
    let redCards: [Entry]
    let saves: [Entry]
    /// FPL's bonus once added; before that the Toolkit's estimate from BPS.
    let bonus: [Entry]
    let bonusProvisional: Bool
    let bps: [Entry]
    /// Every outfield player with a DEFCON count, misses included.
    let defcon: [Defcon]
    let players: [String: PlayerSummary]

    func player(_ id: Int) -> PlayerSummary? { players[String(id)] }
}
