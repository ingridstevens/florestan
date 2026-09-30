import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
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
                if !model.queuedJobs.isEmpty {
                    Text(model.queuedJobs.count == 1 ? "1 more link waiting" : "\(model.queuedJobs.count) more links waiting")
                        .font(.caption).foregroundStyle(.secondary)
                }
                recent
            }
            .padding(14)
            footer
        }
        .frame(width: 360)
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
    var job: Job
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Thumbnail(url: current?.thumbnailURL ?? job.tracks.first?.thumbnailURL, size: 40, corner: 7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(.headline).lineLimit(1)
                    Text(current.map { "\($0.title)" } ?? job.summary)
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ProgressLine(value: job.progress, tint: tint)
            Text(job.summary).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var current: Track? {
        job.tracks.first { if case .downloading = $0.state { true } else { $0.state == .importing } }
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
        }
        .accessibilityElement(children: .contain)
    }

    private var needsRetry: Bool {
        if case .failed = job.phase { return true }
        return job.failedCount > 0
    }
}
