import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.player.song != nil {
                NowPlayingStrip()
                Divider()
            }
            VStack(alignment: .leading, spacing: 12) {
                if !model.toolsInstalled {
                    ToolsMissingNotice()
                } else if model.botCheckHit {
                    BotCheckNotice(compact: true)
                    Button("Open settings") { open(.settings) }
                }
                if let job = model.activeJob {
                    ActiveJobSummary(job: job, tint: model.settings.theme.accent)
                }
                waiting
                recent
            }
            .padding(14)
            footer
        }
        .frame(width: 360)
        .acceptsLinkDrops(cornerRadius: 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Wordmark(size: 17)
                Spacer()
                Button { open(.downloads) } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .help("Open Florestan.exe")
                .accessibilityLabel("Open Florestan.exe window")
            }
            LinkField()
        }
        .padding(14)
        .background(FrameBackground(colors: model.settings.theme.mesh, flowing: model.isBusy))
    }

    /// Links waiting their turn, so it's clear what's queued before pasting one again.
    @ViewBuilder private var waiting: some View {
        let queued = model.queuedJobs
        if !queued.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Waiting").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(queued.prefix(Self.waitingShown)) { job in
                    WaitingJobRow(job: job, size: 28)
                }
                if queued.count > Self.waitingShown {
                    Button("\(queued.count - Self.waitingShown) more waiting") { open(.downloads) }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let waitingShown = 3

    @ViewBuilder private var recent: some View {
        let finished = Array(model.finishedJobs.prefix(4))
        if finished.isEmpty && model.activeJob == nil {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing downloaded yet")
                    .font(.headline)
                Text("Copy a YouTube link anywhere and press ⌥⌘Y, or paste it above.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if !finished.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(finished) { job in
                    CompactJobRow(job: job, tint: model.settings.theme.accent)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("⌥⌘Y downloads the link you copied")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.4))
    }

    private func open(_ section: Section) {
        model.selectedSection = section
        openWindow(id: "main")
        NSApp.activate()
    }
}

struct ActiveJobSummary: View {
    @Environment(AppModel.self) private var model
    var job: Job
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Thumbnail(url: current?.thumbnailURL ?? job.thumbnailURL, size: 40, corner: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(.headline).lineLimit(1)
                    Text(current.map { "\($0.title)" } ?? job.summary)
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { model.cancel(job) } label: {
                    Image(systemName: "stop.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop downloading")
                .accessibilityLabel("Stop downloading \(job.title)")
            }
            ProgressLine(value: job.progress, tint: tint)
            Text(job.summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var current: Track? {
        job.tracks.first { if case .downloading = $0.state { true } else { $0.state == .importing } }
    }
}

/// What Music is playing, with its controls. Shown only while Music is playing or paused.
struct NowPlayingStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let player = model.player
        if let song = player.song {
            HStack(spacing: 10) {
                Group {
                    if let artwork = song.artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(.quaternary)
                            .overlay(Image(systemName: "music.note").foregroundStyle(.tertiary))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title).font(.headline).lineLimit(1)
                    Text(song.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    Button(action: player.previous) { Image(systemName: "backward.fill") }
                        .help("Previous").accessibilityLabel("Previous")
                    Button(action: player.playPause) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 20)
                    }
                    .help(player.isPlaying ? "Pause" : "Play").accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button(action: player.next) { Image(systemName: "forward.fill") }
                        .help("Next").accessibilityLabel("Next")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing: \(song.title) by \(song.artist)")
        }
    }
}

/// A Job in the Queue: what it is, and a button to drop it.
struct WaitingJobRow: View {
    @Environment(AppModel.self) private var model
    var job: Job
    var size: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: job.thumbnailURL, size: size, corner: 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(job.knownTitle ?? job.link.url.absoluteString)
                    .lineLimit(1).truncationMode(job.knownTitle == nil ? .middle : .tail)
                Text(job.link.isPlaylist ? "Playlist · waiting" : "Waiting")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { model.cancel(job) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Don't download this")
            .accessibilityLabel("Remove \(job.knownTitle ?? "this link") from the queue")
        }
        .accessibilityElement(children: .contain)
    }
}

struct CompactJobRow: View {
    @Environment(AppModel.self) private var model
    var job: Job
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: job.tracks.first?.thumbnailURL, size: 28, corner: 5)
            VStack(alignment: .leading, spacing: 0) {
                Text(job.title).lineLimit(1)
                Text(job.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if needsRetry {
                Button {
                    model.retry(job)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.orange.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .help(job.link.isPlaylist ? "Try the failed songs again" : "Try again")
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(tint)
            }
            if model.canOpenInAppleMusic(job) {
                Button { model.play(job) } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(job.link.isPlaylist ? "Play this playlist" : "Play this song")
                .accessibilityLabel("Play \(job.title)")
                Button { model.openInAppleMusic(job) } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(job.link.isPlaylist ? "Open this playlist in Apple Music" : "Show this song in Apple Music")
                .accessibilityLabel("Open in Apple Music")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var needsRetry: Bool {
        if case .failed = job.phase { return true }
        return job.failedCount > 0
    }
}
