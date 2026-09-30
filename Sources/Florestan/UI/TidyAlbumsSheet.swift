import FlorestanCore
import SwiftUI

/// Review screen for Tidy albums: proposed album moves, songs YouTube Music doesn't know, and duplicates.
struct TidyAlbumsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ViewState private var tidy = TidyAlbumsModel()
    @ViewState private var confirmRemoval: (copy: LedgerEntry, kept: LedgerEntry)?

    private var tint: Color { model.settings.theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tidy albums").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Songs from plain YouTube videos come without an album, so each one sits alone. Florestan looks them up on YouTube Music and puts them on their album, in album order.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer.padding(14)
        }
        .frame(width: 620, height: 560)
        .onAppear { if tidy.phase == .idle { tidy.scan(using: model) } }
        .confirmationDialog("Remove this copy of “\(confirmRemoval?.copy.metadata.title ?? "")”?",
                            isPresented: Binding(get: { confirmRemoval != nil }, set: { if !$0 { confirmRemoval = nil } }),
                            presenting: confirmRemoval) { pair in
            Button("Remove from Apple Music", role: .destructive) { tidy.removeDuplicate(pair.copy, keeping: pair.kept, using: model) }
        } message: { pair in
            Text("It's removed from your library and its file goes to the Trash. The copy on “\(pair.kept.metadata.album)” stays.")
        }
    }

    @ViewBuilder private var content: some View {
        switch tidy.phase {
        case .idle, .scanning:
            let progress: (Int, Int) = if case .scanning(let d, let t) = tidy.phase { (d, t) } else { (0, 0) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(progress.1 == 0 ? "Looking at your songs…" : "Looking up albums… \(progress.0) of \(progress.1)")
                        .monospacedDigit()
                }
                Text("Takes a few seconds per song.").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(20)
        case .review, .applying:
            reviewList
        case .done(let moved):
            VStack(alignment: .leading, spacing: 8) {
                Label(moved == 1 ? "Moved 1 song onto its album." : "Moved \(moved) songs onto their albums.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(tint)
                if !tidy.renumbered.isEmpty {
                    Text("Also put \(tidy.renumbered.count) songs in album order.").foregroundStyle(.secondary)
                }
                if let error = tidy.lastError { Text(error).foregroundStyle(.orange) }
            }
            .padding(20)
        }
    }

    private var reviewList: some View {
        @Bindable var tidy = tidy
        return List {
            if tidy.proposals.isEmpty && tidy.duplicates.isEmpty {
                Text(tidy.notFound.isEmpty ? "Everything is already on an album." : "YouTube Music didn't know the albums of these songs.")
                    .foregroundStyle(.secondary)
            }
            if !tidy.proposals.isEmpty {
                SwiftUI.Section("Move onto an album") {
                    ForEach($tidy.proposals) { $proposal in
                        Toggle(isOn: $proposal.selected) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(proposal.entry.metadata.title)
                                Text("\(proposal.entry.metadata.artist)  →  \(proposal.destination.name)\(proposal.trackNumber.map { ", track \($0)" } ?? "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            if !tidy.duplicates.isEmpty {
                SwiftUI.Section("Duplicates") {
                    ForEach(tidy.duplicates, id: \.first!.videoID) { group in
                        let kept = group[0]
                        ForEach(group.dropFirst(), id: \.videoID) { copy in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(copy.metadata.title)
                                    Text("On “\(copy.metadata.album)”. You also have it on “\(kept.metadata.album)”.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Remove this copy") { confirmRemoval = (copy, kept) }
                            }
                        }
                    }
                }
            }
            if !tidy.notFound.isEmpty {
                SwiftUI.Section("No album found") {
                    ForEach(tidy.notFound) { entry in
                        Text("\(entry.metadata.artist) – \(entry.metadata.title)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack {
            if let error = tidy.lastError, tidy.phase != .done(moved: 0) {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            Spacer()
            switch tidy.phase {
            case .review, .applying:
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                let count = tidy.proposals.count(where: \.selected)
                Button(count == 1 ? "Move 1 song" : "Move \(count) songs") { tidy.apply(using: model) }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .keyboardShortcut(.defaultAction)
                    .disabled(tidy.phase == .applying || (count == 0 && tidy.renumbered.isEmpty))
            case .done:
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Cancel") { tidy.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
