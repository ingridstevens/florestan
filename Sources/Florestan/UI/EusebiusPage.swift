import SwiftUI

/// Florestan's calm other half: quiet serif type, pale colors, no hurry.
struct EusebiusPage: View {
    @Environment(EusebiusModel.self) private var eusebius

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Playlists by feel")
                        .font(.system(size: 30, weight: .light, design: .serif))
                    Text("Eusebius listens through your whole Apple Music library and sorts songs by how they feel, not by genre. Keep the playlists you like; they stay up to date. It runs entirely on this Mac.")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 500, alignment: .leading)
                }

                if let reason = eusebius.unavailableReason {
                    Text(reason)
                        .font(.system(size: 14, design: .serif))
                        .padding(14)
                        .background(Eusebius.accent.opacity(0.08), in: .rect(cornerRadius: 10))
                } else {
                    content
                }
            }
            .foregroundStyle(Eusebius.ink)
            .padding(.horizontal, 44)
            .padding(.vertical, 40)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(Eusebius.accent)
        .background(Eusebius.paper)
        // Eusebius is always pale, even in dark mode: the contrast with Florestan is the point.
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder private var content: some View {
        switch eusebius.phase {
        case .idle:
            ListenButtons()
        case .readingLibrary:
            Working(text: "Reading your library…", progress: nil) { eusebius.cancel() }
        case .listening(let done, let total):
            Working(text: "Listening… \(done) of \(total) songs", progress: total == 0 ? nil : Double(done) / Double(total)) {
                eusebius.cancel()
            }
        case .ready:
            VStack(alignment: .leading, spacing: 26) {
                SuggestionList()
                ListenButtons()
            }
        case .failed(let why):
            VStack(alignment: .leading, spacing: 14) {
                Text(why).font(.system(size: 14, design: .serif))
                ListenButtons()
            }
        }
    }
}

/// "Listen for new songs" and "Re-analyze everything".
private struct ListenButtons: View {
    @Environment(EusebiusModel.self) private var eusebius

    var body: some View {
        HStack(spacing: 12) {
            if eusebius.hasListenedBefore {
                QuietButton("Listen for new songs", prominent: true) { eusebius.listen() }
                    .help("Only songs Eusebius hasn't heard yet")
                QuietButton("Re-analyze everything") { eusebius.listen(everything: true) }
                    .help("Forget earlier judgments and listen to the whole library again")
            } else {
                QuietButton("Suggest playlists", prominent: true) { eusebius.listen() }
            }
        }
    }
}

private struct SuggestionList: View {
    @Environment(EusebiusModel.self) private var eusebius
    @ViewState private var showHidden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(eusebius.visibleSuggestions) { suggestion in
                SuggestionRow(suggestion: suggestion)
                Divider().opacity(0.5)
            }
            if let error = eusebius.lastError {
                Text(error).font(.system(size: 12.5, design: .serif)).foregroundStyle(.orange).padding(.top, 8)
            }
            if !eusebius.hiddenMoods.isEmpty {
                Button(showHidden ? "Hide the playlists you turned down" : "\(eusebius.hiddenMoods.count) turned down. Show") {
                    withAnimation(.easeInOut(duration: 0.25)) { showHidden.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, design: .serif).italic())
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                if showHidden {
                    ForEach(eusebius.hiddenMoods, id: \.self) { mood in
                        HStack(spacing: 10) {
                            Image(systemName: mood.symbol).frame(width: 20).foregroundStyle(.tertiary)
                            Text(mood.playlistName).font(.system(size: 14, design: .serif)).foregroundStyle(.secondary)
                            Button("Suggest again") { eusebius.clearFeedback(mood) }
                                .buttonStyle(.plain)
                                .font(.system(size: 12, design: .serif))
                                .foregroundStyle(Eusebius.accent)
                        }
                    }
                }
            }
        }
    }
}

private struct SuggestionRow: View {
    @Environment(EusebiusModel.self) private var eusebius
    var suggestion: MoodSuggestion
    @ViewState private var expanded = false

    private var liked: Bool { eusebius.feedback[suggestion.mood] == .liked }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: suggestion.mood.symbol)
                    .frame(width: 20)
                    .foregroundStyle(Eusebius.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.mood.playlistName)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                    Text(status)
                        .font(.system(size: 12.5, design: .serif))
                        .foregroundStyle(.secondary)
                    Button(expanded ? "Hide songs" : "Show songs") {
                        withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Eusebius.accent)
                    .padding(.top, 2)
                }
                Spacer()
                if eusebius.syncing.contains(suggestion.mood) {
                    ProgressView().controlSize(.small)
                }
                FeedbackButton(symbol: liked ? "hand.thumbsup.fill" : "hand.thumbsup", active: liked,
                               help: liked ? "Kept in Apple Music" : "Keep this playlist in Apple Music") {
                    eusebius.like(suggestion)
                }
                FeedbackButton(symbol: "hand.thumbsdown", active: false, help: "Don't suggest this playlist again") {
                    withAnimation(.easeInOut(duration: 0.3)) { eusebius.dislike(suggestion) }
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(suggestion.tracks.prefix(40)) { track in
                        Text("\(track.artist) – \(track.name)")
                            .font(.system(size: 12.5, design: .serif))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if suggestion.tracks.count > 40 {
                        Text("and \(suggestion.tracks.count - 40) more")
                            .font(.system(size: 12.5, design: .serif).italic())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 10)
    }

    private var status: String {
        let count = "\(suggestion.tracks.count) songs."
        if liked { return "\(count) In Apple Music as “\(suggestion.playlistName)”, kept up to date." }
        return "\(count) \(suggestion.mood.blurb)"
    }
}

private struct FeedbackButton: View {
    var symbol: String
    var active: Bool
    var help: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .foregroundStyle(active ? .white : Eusebius.ink)
                .background(Circle().fill(active ? Eusebius.accent : Eusebius.accent.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct Working: View {
    var text: String
    var progress: Double?
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text).font(.system(size: 15, design: .serif).italic())
            if let progress {
                ProgressLine(value: progress, tint: Eusebius.accent).frame(maxWidth: 360)
            } else {
                ProgressView().controlSize(.small)
            }
            Button("Stop", action: cancel)
                .buttonStyle(.plain)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(Eusebius.accent)
        }
    }
}

private struct QuietButton: View {
    var title: String
    var prominent = false
    var action: () -> Void
    init(_ title: String, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.prominent = prominent; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .serif))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .foregroundStyle(prominent ? .white : Eusebius.ink)
                .background(Capsule().fill(prominent ? Eusebius.accent : Eusebius.accent.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }
}
