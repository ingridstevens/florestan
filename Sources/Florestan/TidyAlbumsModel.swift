import Foundation
import FlorestanCore
import Observation

/// A song Tidy albums wants to move onto an album.
struct AlbumProposal: Identifiable {
    var entry: LedgerEntry
    var destination: AlbumTidy.KnownAlbum
    var trackNumber: Int?
    var trackCount: Int?
    var selected = true
    var id: String { entry.videoID }
}

/// "Tidy albums": finds the real album of songs imported from plain YouTube videos (which carry no album) by
/// looking them up on YouTube Music, numbers album tracks in album order, makes each album's songs agree on
/// album artist, year and a square cover (so Apple Music shows the album once), and points out duplicates.
@MainActor @Observable
final class TidyAlbumsModel {
    enum Phase: Equatable {
        case idle
        case scanning(done: Int, total: Int)
        case review
        case applying
        case done(moved: Int)
    }

    private(set) var phase: Phase = .idle
    var proposals: [AlbumProposal] = []
    private(set) var notFound: [LedgerEntry] = []
    private(set) var duplicates: [[LedgerEntry]] = []
    /// Songs already on the right album that get a track number from the album's track list.
    private(set) var renumbered: [AlbumProposal] = []
    /// Albums whose songs disagree on album artist, year or cover, by name, with how many songs change.
    private(set) var mismatchedAlbums: [(album: String, songs: Int)] = []
    private(set) var matchedSongs = 0
    private(set) var lastError: String?
    private var work: Task<Void, Never>?

    func scan(using model: AppModel) {
        work?.cancel()
        work = Task { await runScan(using: model) }
    }

    /// Quietly files newly downloaded songs onto their albums, with no review step.
    /// Only confident matches are applied (same song, same artist); others are left for Tidy albums.
    func autoTidy(_ videoIDs: Set<String>, using model: AppModel) {
        guard !videoIDs.isEmpty, work == nil else { return }
        work = Task {
            await runScan(using: model, only: videoIDs)
            if !proposals.isEmpty || !renumbered.isEmpty || !mismatchedAlbums.isEmpty { await applyChosen(using: model) }
            phase = .idle
            work = nil
        }
    }

    func cancel() {
        work?.cancel()
        phase = .idle
    }

    private func runScan(using model: AppModel, only: Set<String>? = nil) async {
        // Music is the truth: the Ledger remembers each song as imported, not as filed since, and acting on that
        // would pull songs back off albums they were put on by hand or by an earlier tidy.
        let current = (try? await MusicLibrary.albumTracks(ids: Array(Set(model.librarySongs.map(\.musicTrackID))))) ?? []
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = model.librarySongs.compactMap { entry -> LedgerEntry? in
            guard let track = byID[entry.musicTrackID] else { return nil }
            var updated = entry
            updated.metadata.album = track.album
            updated.metadata.albumArtist = track.albumArtist
            return updated
        }
        // A group whose copies all point at one Apple Music track was already resolved.
        duplicates = only == nil ? AlbumTidy.duplicates(entries).filter { Set($0.map(\.musicTrackID)).count > 1 } : []
        let candidates = entries.filter { AlbumTidy.needsAlbum($0.metadata) && (only?.contains($0.videoID) ?? true) }
        proposals = []
        notFound = []
        renumbered = []
        mismatchedAlbums = []
        matchedSongs = 0
        lastError = nil
        phase = .scanning(done: 0, total: candidates.count)

        let downloader = model.downloader
        var found: [(LedgerEntry, VideoInfo)] = []
        var done = 0
        await withTaskGroup(of: (LedgerEntry, VideoInfo?).self) { group in
            var pending = candidates.makeIterator()
            func addNext() {
                guard let entry = pending.next() else { return }
                group.addTask { (entry, await Self.lookUp(entry, downloader: downloader)) }
            }
            for _ in 0..<3 { addNext() }
            while let (entry, info) = await group.next() {
                if Task.isCancelled { return }
                if let info { found.append((entry, info)) } else { notFound.append(entry) }
                done += 1
                phase = .scanning(done: done, total: candidates.count)
                addNext()
            }
        }
        if Task.isCancelled { return }

        var known = Self.knownAlbums(in: entries)
        for (entry, info) in found.sorted(by: { $0.0.metadata.title < $1.0.metadata.title }) {
            let artist = info.artists?.joined(separator: ", ") ?? info.artist ?? entry.metadata.artist
            let destination = AlbumTidy.destination(foundAlbum: info.album ?? "", artist: artist, existing: known)
            if !known.contains(destination) { known.append(destination) }
            proposals.append(AlbumProposal(entry: entry, destination: destination))
        }
        await numberTracks(entries: entries, downloader: downloader)
        mismatchedAlbums = Self.mismatches(in: current, after: proposals, only: only.map { ids in
            Set(entries.filter { ids.contains($0.videoID) }.map(\.musicTrackID))
        })
        phase = .review
    }

    /// Top YouTube Music matches for the song, checked until one is the same song and names an album.
    nonisolated private static func lookUp(_ entry: LedgerEntry, downloader: Downloader) async -> VideoInfo? {
        let lead = entry.metadata.artist.components(separatedBy: ", ").first ?? entry.metadata.artist
        guard let results = try? await downloader.musicSearch("\(lead) \(entry.metadata.title)", kind: .songs) else { return nil }
        for result in results.prefix(3) {
            guard let info = try? await downloader.videoInfo(videoID: result.id), let album = info.album, !album.isEmpty else { continue }
            let foundArtist = info.artists?.joined(separator: ", ") ?? info.artist ?? ""
            if AlbumTidy.isSameSong(title: entry.metadata.title, artist: entry.metadata.artist,
                                    foundTitle: info.track ?? info.title, foundArtist: foundArtist) {
                return info
            }
        }
        return nil
    }

    private static func knownAlbums(in entries: [LedgerEntry]) -> [AlbumTidy.KnownAlbum] {
        var albums: [AlbumTidy.KnownAlbum] = []
        for entry in entries where !AlbumTidy.needsAlbum(entry.metadata) {
            let album = AlbumTidy.KnownAlbum(name: entry.metadata.album, albumArtist: entry.metadata.albumArtist ?? entry.metadata.artist)
            if !albums.contains(album) { albums.append(album) }
        }
        return albums
    }

    /// Looks up the track list of every album that's gaining songs, and numbers all of that album's songs by it.
    private func numberTracks(entries: [LedgerEntry], downloader: Downloader) async {
        let albums = Set(proposals.map { "\($0.destination.name)|\($0.destination.albumArtist)" })
        for key in albums {
            let parts = key.components(separatedBy: "|")
            let (name, albumArtist) = (parts[0], parts[1])
            guard let album = try? await downloader.musicSearch("\(albumArtist) \(name)", kind: .albums, limit: 1).first,
                  let urlString = album.url, let url = URL(string: urlString),
                  let listing = try? await downloader.fetchPlaylist(.playlist(id: album.id, url: url)) else { continue }
            let titles = listing.entries.compactMap(\.title)
            let alreadyThere = entries.filter { $0.metadata.album == name && ($0.metadata.albumArtist ?? $0.metadata.artist) == albumArtist }
            let moving = proposals.filter { $0.destination.name == name && $0.destination.albumArtist == albumArtist }
            guard AlbumTidy.listingCoversAlbum(albumTracks: titles,
                                               songTitles: (alreadyThere + moving.map(\.entry)).map(\.metadata.title)) else { continue }
            let numbers = AlbumTidy.trackNumbers(albumTracks: titles,
                                                 songs: (alreadyThere + moving.map(\.entry)).map { ($0.videoID, $0.metadata.title) })
            for i in proposals.indices where moving.contains(where: { $0.id == proposals[i].id }) {
                proposals[i].trackNumber = numbers[proposals[i].id]
                proposals[i].trackCount = titles.count
            }
            for entry in alreadyThere {
                guard let number = numbers[entry.videoID], number != entry.metadata.trackNumber else { continue }
                renumbered.append(AlbumProposal(entry: entry, destination: .init(name: name, albumArtist: albumArtist),
                                                trackNumber: number, trackCount: titles.count))
            }
        }
    }

    /// What making albums match would change, given the moves about to happen. With `only`, just the albums of those tracks.
    private static func mismatches(in tracks: [AlbumTidy.AlbumTrack], after moves: [AlbumProposal],
                                   only: Set<String>?) -> [(album: String, songs: Int)] {
        var projected = tracks
        for move in moves {
            guard let i = projected.firstIndex(where: { $0.id == move.entry.musicTrackID }) else { continue }
            projected[i].album = move.destination.name
            projected[i].albumArtist = move.destination.albumArtist
        }
        var fixes = AlbumTidy.consistencyFixes(projected)
        if let only {
            let albums = Set(projected.filter { only.contains($0.id) }.map(\.album))
            fixes.removeAll { !albums.contains($0.album) }
        }
        return Dictionary(grouping: fixes, by: \.album).map { ($0.key, $0.value.count) }.sorted { $0.album < $1.album }
    }

    // MARK: - Applying

    func apply(using model: AppModel) {
        guard proposals.contains(where: \.selected) || !renumbered.isEmpty || !mismatchedAlbums.isEmpty else { return }
        work = Task {
            await applyChosen(using: model)
            work = nil
        }
    }

    private func applyChosen(using model: AppModel) async {
        let chosen = proposals.filter(\.selected) + renumbered
        phase = .applying
        var moved = 0
        for proposal in chosen {
            do {
                try await MusicLibrary.setAlbum(trackID: proposal.entry.musicTrackID, album: proposal.destination.name,
                                                albumArtist: proposal.destination.albumArtist,
                                                trackNumber: proposal.trackNumber, trackCount: proposal.trackCount)
                var updated = proposal.entry
                updated.metadata.album = proposal.destination.name
                updated.metadata.albumArtist = proposal.destination.albumArtist
                updated.metadata.trackNumber = proposal.trackNumber
                try? await model.ledger.record(updated)
                if proposals.contains(where: { $0.id == proposal.id }) { moved += 1 }
            } catch {
                lastError = error.localizedDescription
            }
        }
        await makeAlbumsMatch(using: model)
        await model.refreshLibrary()
        phase = .done(moved: moved)
    }

    /// Reads the albums again after the moves and gives each one's songs the same album artist, year and square cover.
    private func makeAlbumsMatch(using model: AppModel) async {
        let albums = Set(mismatchedAlbums.map(\.album) + proposals.filter(\.selected).map(\.destination.name))
        guard !albums.isEmpty else { return }
        let ids = Array(Set(model.librarySongs.map(\.musicTrackID)))
        guard let tracks = try? await MusicLibrary.albumTracks(ids: ids) else { return }
        for fix in AlbumTidy.consistencyFixes(tracks) where albums.contains(fix.album) {
            do {
                try await MusicLibrary.apply(fix)
                matchedSongs += 1
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Deletes a duplicate from Apple Music and moves its file to the Trash (so it can be recovered).
    /// The duplicate's YouTube video stays in the Ledger, pointing at the copy that's kept, so it isn't downloaded again.
    func removeDuplicate(_ copy: LedgerEntry, keeping kept: LedgerEntry, using model: AppModel) {
        Task {
            do {
                if let path = try await MusicLibrary.deleteTrack(trackID: copy.musicTrackID) {
                    try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                }
                var redirected = copy
                redirected.musicTrackID = kept.musicTrackID
                redirected.metadata = kept.metadata
                try? await model.ledger.record(redirected)
                await model.refreshLibrary()
                duplicates = AlbumTidy.duplicates(model.librarySongs).filter { group in
                    Set(group.map(\.musicTrackID)).count > 1
                }
                proposals.removeAll { $0.id == copy.videoID }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
