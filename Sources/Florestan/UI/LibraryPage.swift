import FlorestanCore
import SwiftUI

/// The Ledger: songs Florestan has imported and will skip next time.
struct LibraryPage: View {
    @Environment(AppModel.self) private var model
    @ViewState private var search = ""
    @ViewState private var tidying = false

    private var songs: [LedgerEntry] {
        guard !search.isEmpty else { return model.librarySongs }
        return model.librarySongs.filter {
            $0.metadata.title.localizedCaseInsensitiveContains(search) || $0.metadata.artist.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Imported songs",
                       subtitle: "Florestan skips these next time. Forget a song to download it again.") {
                HStack {
                    Button {
                        tidying = true
                    } label: {
                        Label("Tidy albums", systemImage: "square.stack")
                    }
                    .disabled(model.librarySongs.isEmpty)
                    .help("Put songs from YouTube videos onto their albums, and find duplicates")
                    TextField("Search", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
            .padding([.horizontal, .top], 24)

            if model.librarySongs.isEmpty {
                Text("Songs appear here after Florestan adds them to Apple Music.")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                Spacer()
            } else {
                List(songs) { entry in
                    LedgerRow(entry: entry)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(isPresented: $tidying) { TidyAlbumsSheet() }
    }
}

private struct LedgerRow: View {
    @Environment(AppModel.self) private var model
    var entry: LedgerEntry
    @ViewState private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: URL(string: "https://i.ytimg.com/vi/\(entry.videoID)/mqdefault.jpg"), size: 34, corner: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.metadata.title).lineLimit(1)
                Text(entry.metadata.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if hovering {
                Button("Show in Apple Music") { model.showInAppleMusic(entry.videoID) }
                    .controlSize(.small)
                Button("Forget") { Task { await model.forget(entry) } }
                    .controlSize(.small)
            } else {
                Text(entry.importedAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Show in Apple Music") { model.showInAppleMusic(entry.videoID) }
            Button("Open on YouTube") {
                NSWorkspace.shared.open(URL(string: "https://www.youtube.com/watch?v=\(entry.videoID)")!)
            }
            Button("Forget") { Task { await model.forget(entry) } }
        }
    }
}
