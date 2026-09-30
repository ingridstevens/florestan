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
                    Text("Eusebius listens through your whole Apple Music library and sorts songs by how they feel, not by genre. It runs entirely on this Mac.")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 480, alignment: .leading)
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
            .frame(maxWidth: 680, alignment: .leading)
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
            QuietButton("Suggest playlists") { eusebius.suggest() }
        case .readingLibrary:
            Working(text: "Reading your library…", progress: nil) { eusebius.cancel() }
        case .listening(let done, let total):
            Working(text: "Listening… \(done) of \(total) songs", progress: total == 0 ? nil : Double(done) / Double(total)) {
                eusebius.cancel()
            }
        case .suggestions, .creating:
            SuggestionList()
        case .created(let count):
            VStack(alignment: .leading, spacing: 14) {
                Text(count == 1 ? "1 playlist is waiting in Apple Music." : "\(count) playlists are waiting in Apple Music.")
                    .font(.system(size: 17, design: .serif))
                Text("Run it again later. Eusebius only listens to songs it hasn't heard yet, and updates these playlists in place.")
                    .font(.system(size: 13, design: .serif)).foregroundStyle(.secondary)
                QuietButton("Suggest again") { eusebius.suggest() }
            }
        case .failed(let why):
            VStack(alignment: .leading, spacing: 14) {
                Text(why).font(.system(size: 14, design: .serif))
                QuietButton("Try again") { eusebius.suggest() }
            }
        }
    }
}

private struct SuggestionList: View {
    @Environment(EusebiusModel.self) private var eusebius

    var body: some View {
        @Bindable var eusebius = eusebius
        let selectedCount = eusebius.suggestions.count(where: \.selected)
        VStack(alignment: .leading, spacing: 4) {
            ForEach($eusebius.suggestions) { $suggestion in
                SuggestionRow(suggestion: $suggestion)
                Divider().opacity(0.5)
            }
            HStack(spacing: 16) {
                QuietButton(selectedCount == 1 ? "Create 1 playlist" : "Create \(selectedCount) playlists", prominent: true) {
                    eusebius.createSelected()
                }
                .disabled(selectedCount == 0 || eusebius.phase == .creating)
                if eusebius.phase == .creating {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.top, 18)
        }
    }
}

private struct SuggestionRow: View {
    @Binding var suggestion: MoodSuggestion
    @ViewState private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Toggle("", isOn: $suggestion.selected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Create \(suggestion.mood.playlistName)")
                Image(systemName: suggestion.mood.symbol)
                    .frame(width: 20)
                    .foregroundStyle(Eusebius.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.mood.playlistName)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                    Text("\(suggestion.tracks.count) songs. \(suggestion.mood.blurb)")
                        .font(.system(size: 12.5, design: .serif))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(expanded ? "Hide songs" : "Show songs") {
                    withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(Eusebius.accent)
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
                .padding(.leading, 70)
            }
        }
        .padding(.vertical, 10)
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
