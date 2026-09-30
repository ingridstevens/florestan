import SwiftUI

struct DownloadsPage: View {
    @Environment(AppModel.self) private var model

    private var tint: Color { model.settings.theme.accent }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                notices
                if let job = model.activeJob {
                    ActiveJobCard(job: job, tint: tint)
                }
                if !model.queuedJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Waiting")
                        ForEach(model.queuedJobs) { job in
                            HStack(spacing: 10) {
                                Image(systemName: job.link.isPlaylist ? "music.note.list" : "music.note")
                                    .foregroundStyle(.secondary).frame(width: 20)
                                Text(job.link.url.absoluteString).lineLimit(1).truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button { model.cancel(job) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.plain)
                                .help("Don't download this")
                                .accessibilityLabel("Remove from the queue")
                            }
                        }
                    }
                }
                if !model.finishedJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            SectionLabel("Earlier")
                            Spacer()
                            Button("Clear") { model.clearHistory() }
                                .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(model.finishedJobs) { job in
                            HistoryRow(job: job, tint: tint)
                            Divider()
                        }
                    }
                }
                if model.jobs.isEmpty && model.toolsInstalled {
                    EmptyDownloads()
                }
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var notices: some View {
        if !model.toolsInstalled { ToolsMissingNotice() }
        if model.botCheckHit { BotCheckNotice() }
        if model.musicNotAuthorized {
            VStack(alignment: .leading, spacing: 8) {
                Label("Florestan can't add songs to Apple Music", systemImage: "lock")
                    .font(.headline)
                Text("Allow Florestan.exe to control Music in System Settings › Privacy & Security › Automation.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    Button("Dismiss") { model.musicNotAuthorized = false }
                }
            }
            .padding(12)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 10))
        }
    }
}

struct SectionLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private struct ActiveJobCard: View {
    @Environment(AppModel.self) private var model
    var job: Job
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Thumbnail(url: job.tracks.first?.thumbnailURL, size: 64, corner: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title).font(.system(size: 20, weight: .bold, design: .rounded)).lineLimit(2)
                    Text(job.summary).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop") { model.cancel(job) }
                    .help("Stop downloading. Songs already added stay; Retry gets the rest.")
            }
            ProgressLine(value: job.progress, tint: tint)
            if job.tracks.count > 1 {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(job.tracks) { track in
                        TrackRow(track: track, tint: tint,
                                 onRemove: job.link.isPlaylist ? { model.removeFromPlaylist(track.videoID, in: job.id) } : nil,
                                 onAddBack: job.link.isPlaylist ? { model.addBackToPlaylist(track.videoID, in: job.id) } : nil)
                    }
                }
            }
        }
        .padding(16)
        .background(tint.opacity(0.07), in: .rect(cornerRadius: 12))
    }
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    var job: Job
    var tint: Color
    @ViewState private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    CompactJobRow(job: job, tint: tint)
                    Text(job.finishedAt ?? job.createdAt, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)
            .accessibilityHint(expanded ? "Hide songs" : "Show songs")

            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(job.tracks) { track in
                        TrackRow(track: track, tint: tint,
                                 onRemove: job.link.isPlaylist ? { model.removeFromPlaylist(track.videoID, in: job.id) } : nil,
                                 onAddBack: job.link.isPlaylist ? { model.addBackToPlaylist(track.videoID, in: job.id) } : nil)
                    }
                }
                .padding(.leading, 38)
                .padding(.bottom, 6)
            }
        }
    }
}

private struct EmptyDownloads: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste a link above to start")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 6) {
                Label("A song link adds that one song to Apple Music.", systemImage: "music.note")
                Label("A playlist link adds every song, plus a playlist with the same name.", systemImage: "music.note.list")
                Label("Copy a link anywhere and press ⌥⌘Y to download it without opening Florestan.", systemImage: "command")
            }
            .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
