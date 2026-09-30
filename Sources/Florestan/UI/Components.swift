import AppKit
import FlorestanCore
import SwiftUI

/// The link field: sits on the frame gradient as a glass capsule.
struct LinkField: View {
    @Environment(AppModel.self) private var model
    @ViewState private var text = ""
    @ViewState private var feedback: String?
    @FocusState private var focused: Bool
    var prefillFromClipboard = true
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(.white.opacity(0.8))
                TextField("", text: $text, prompt: Text("Paste a YouTube or YouTube Music link").foregroundStyle(.white.opacity(0.78)))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: text) { feedback = nil }
                Button(action: submit) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: large ? 14 : 12, weight: .bold))
                        .frame(width: large ? 30 : 24, height: large ? 30 : 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(text.isEmpty ? .white.opacity(0.5) : .black.opacity(0.8))
                .background(Circle().fill(.white.opacity(text.isEmpty ? 0.15 : 0.95)))
                .disabled(text.isEmpty)
                .keyboardShortcut(.defaultAction)
                .help("Download")
                .accessibilityLabel("Download")
                .animation(.snappy(duration: 0.2), value: text.isEmpty)
            }
            .font(.system(size: large ? 15 : 13))
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, large ? 7 : 5)
            .modifier(GlassCapsule())

            if let feedback {
                Text(feedback)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: feedback)
        .onAppear {
            if prefillFromClipboard { prefill() }
            focused = true
        }
    }

    private func prefill() {
        guard text.isEmpty, let clip = NSPasteboard.general.string(forType: .string), Link.parse(clip) != nil else { return }
        text = clip.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !text.isEmpty else { return }
        switch model.submit(text) {
        case .queued:
            text = ""
            feedback = nil
        case .notALink:
            feedback = "That isn't a YouTube link. Copy it from the address bar or the Share menu."
        case .alreadyQueued:
            feedback = "That link is already downloading."
        case .toolsMissing:
            feedback = "Install yt-dlp and ffmpeg first (see below)."
        }
    }
}

/// Square-cropped YouTube thumbnail.
struct Thumbnail: View {
    var url: URL?
    var size: CGFloat = 36
    var corner: CGFloat = 6

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "music.note").foregroundStyle(.tertiary))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: corner))
    }
}

/// A thin progress bar in the theme's accent.
struct ProgressLine: View {
    var value: Double
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: max(4, geo.size.width * value))
            }
        }
        .frame(height: 4)
        .animation(.smooth(duration: 0.3), value: value)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(value * 100)) percent"))
    }
}

struct TrackStateIcon: View {
    var state: Track.State
    var tint: Color

    var body: some View {
        Group {
            switch state {
            case .waiting:
                Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
            case .downloading(let p):
                ZStack {
                    Circle().stroke(.quaternary, lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.04, p)).stroke(tint, style: .init(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
                .animation(.smooth, value: p)
            case .importing:
                ProgressView().controlSize(.mini)
            case .imported:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
            case .skipped:
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
        }
        .frame(width: 18)
    }
}

struct TrackRow: View {
    var track: Track
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: track.thumbnailURL, size: 32, corner: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(isFailure ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)).lineLimit(2)
            }
            Spacer(minLength: 8)
            TrackStateIcon(state: track.state, tint: tint)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var isFailure: Bool { if case .failed = track.state { true } else { false } }

    private var detail: String {
        switch track.state {
        case .failed(let why): why
        case .skipped: [track.artist, "Already in your library"].compactMap { $0 }.joined(separator: ", ")
        case .importing: "Adding to Apple Music…"
        default: track.artist ?? " "
        }
    }
}

/// Explains what to install when yt-dlp or ffmpeg is missing.
struct ToolsMissingNotice: View {
    let command = "brew install yt-dlp ffmpeg"
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Florestan needs yt-dlp and ffmpeg", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            Text("Run this in Terminal, then check again:")
                .foregroundStyle(.secondary)
            HStack {
                Text(command).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
                Button("Check again") { Task { await model.refreshTools() } }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
    }
}

/// Offered after YouTube's bot check blocks a download.
struct BotCheckNotice: View {
    @Environment(AppModel.self) private var model
    var compact = false

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 8) {
            Label("YouTube is blocking downloads on this network", systemImage: "hand.raised")
                .font(.headline)
            Text("YouTube sometimes blocks office, VPN and data-center connections. Try another network, like a phone hotspot, or let Florestan use your browser's YouTube login.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !compact {
                HStack {
                    Toggle("Use my YouTube login from", isOn: $settings.useBrowserLogin)
                    Picker("", selection: $settings.cookieBrowser) {
                        ForEach(CookieBrowser.allCases) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.useBrowserLogin)
                    Spacer()
                    Button("Dismiss") { model.botCheckHit = false }
                }
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

/// Liquid Glass capsule. Snapshot mode gets a flat stand-in, since cached window images can't capture glass.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if SnapshotHarness.outputDirectory != nil {
            content.background(.white.opacity(0.18), in: .capsule)
        } else {
            content.glassEffect(.regular.tint(.white.opacity(0.08)), in: .capsule)
        }
    }
}
