import SwiftUI

/// "Replay · GW5: Sat 26 Sep, 15:00 kick-offs": shown on Matchday and Today while a live matchday
/// replay runs, so a replay is never mistaken for a real matchday.
struct ReplayBanner: View {
    let replay: LiveTeam.Replay
    let onEnd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: ToolkitSpace.sm) {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replay · \(replay.label)")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Showing \(Self.moment.string(from: replay.at)) · \(Self.remaining(replay)) left")
                    .font(.footnote.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: ToolkitSpace.sm)
            Button("End", action: onEnd)
                .font(.subheadline.weight(.bold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("End replay")
        }
        .foregroundStyle(ToolkitColor.onAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ToolkitColor.accent, in: RoundedRectangle(cornerRadius: ToolkitRadius.card))
    }

    /// The original matchday's time, as it was in the UK.
    private static let moment: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = TimeZone(identifier: "Europe/London")
        f.dateFormat = "EEE d MMM HH:mm"
        return f
    }()

    private static func remaining(_ replay: LiveTeam.Replay) -> String {
        let seconds = max(0, replay.durationSeconds - replay.elapsedSeconds)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Settings → Developer → Live matchday replay: the past matchdays the server can replay.
/// Choosing one starts it and opens Matchday. Debug builds only.
struct LiveReplayPicker: View {
    @Environment(AppModel.self) private var appModel
    /// Called after a replay starts, to open Matchday.
    let onStart: () -> Void
    @State private var replays: [LiveReplays.Item]?
    @State private var loadError: ErrorCopy?
    @State private var active = LiveReplay.current

    var body: some View {
        List {
            Section {
                Text("Plays a past matchday through Matchday, Today and the Lock Screen in about 20 minutes, from what the live job recorded. The server keeps 30 days.")
                    .font(.subheadline)
                    .foregroundStyle(ToolkitColor.secondaryText)
            }
            .listRowBackground(ToolkitColor.surface)

            if let active {
                Section("Running") {
                    Text(active.label)
                    Button("End replay", role: .destructive) {
                        LiveReplay.end()
                        self.active = nil
                    }
                }
                .listRowBackground(ToolkitColor.surface)
            }

            Section("Matchdays") {
                if let loadError {
                    Text("\(loadError.title). \(loadError.message)")
                        .foregroundStyle(ToolkitColor.secondaryText)
                } else if let replays {
                    if replays.isEmpty {
                        Text("No matchdays recorded in the last 30 days.")
                            .foregroundStyle(ToolkitColor.secondaryText)
                    }
                    ForEach(replays) { item in
                        Button {
                            LiveReplay.start(id: item.id, label: item.label, durationSeconds: item.durationSeconds)
                            active = LiveReplay.current
                            onStart()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.label)
                                    .foregroundStyle(ToolkitColor.primaryText)
                                Text("\(item.durationSeconds / 60) min · \(item.speed.formatted(.number.precision(.fractionLength(0...1))))× real time")
                                    .font(.footnote)
                                    .foregroundStyle(ToolkitColor.secondaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ProgressView()
                }
            }
            .listRowBackground(ToolkitColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(ToolkitColor.canvas.ignoresSafeArea())
        .navigationTitle("Live matchday replay")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                replays = try await appModel.liveRepository.replays().replays
            } catch let error as APIError {
                loadError = ErrorCopy(error)
            } catch {}
        }
    }
}
