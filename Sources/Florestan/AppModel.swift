import Foundation
import Observation
import FlorestanCore

/// App state: the Queue, Job history, Ledger view, and settings.
@MainActor @Observable
final class AppModel {
    enum SubmitResult: Equatable {
        case queued
        case notALink
        case alreadyQueued
        case toolsMissing
    }

    private(set) var jobs: [Job] = []
    private(set) var librarySongs: [LedgerEntry] = []
    /// Which album artist each album's songs share.
    private var albumBook = AlbumBook()
    private(set) var toolsInstalled = Downloader.toolsInstalled
    private(set) var ytdlpVersion: String?
    /// Set when YouTube asked for a bot check, so the UI can offer the browser-login setting.
    var botCheckHit = false {
        didSet { if botCheckHit { Task { vpnActive = await Downloader.fullTunnelVPNActive() } } }
    }
    /// A VPN is routing all traffic, which is almost always why YouTube blocks downloads.
    private(set) var vpnActive = false
    var musicNotAuthorized = false
    var selectedSection: Section = .downloads

    var settings: Settings

    let ledger: LedgerStore
    private let historyURL: URL
    private let downloadsFolder: URL
    private var runner: Task<Void, Never>?
    private var currentJob: (id: UUID, task: Task<Void, Never>)?
    private var matcherCache: (matcher: LibraryMatcher, songCount: Int, builtAt: Date)?

    static let supportFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Florestan", isDirectory: true)
    }()

    init() {
        let support = Self.supportFolder
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        ledger = LedgerStore(fileURL: support.appendingPathComponent("ledger.json"))
        historyURL = support.appendingPathComponent("history.json")
        downloadsFolder = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Florestan", isDirectory: true)
        settings = Settings()

        if let data = try? Data(contentsOf: historyURL),
           var saved = try? JSONDecoder.florestan.decode([Job].self, from: data) {
            for i in saved.indices where !saved[i].isFinished {
                saved[i].phase = .failed("Stopped when Florestan quit")
            }
            jobs = saved
        }
        Task { await refreshLibrary(); await refreshTools(); await groupOlderSongs(); await reorderEarlierPlaylists()
            cleanUpLeftovers(olderThan: 3 * 24 * 60 * 60) }
    }

    // MARK: - Derived

    var activeJob: Job? { jobs.first(where: \.isActive) }
    var queuedJobs: [Job] { jobs.filter { $0.phase == .queued } }
    var finishedJobs: [Job] { jobs.filter(\.isFinished).sorted { ($0.finishedAt ?? $0.createdAt) > ($1.finishedAt ?? $1.createdAt) } }
    var isBusy: Bool { jobs.contains { $0.isActive || $0.phase == .queued } }

    // MARK: - Submitting

    @discardableResult
    func submit(_ text: String) -> SubmitResult {
        guard let link = Link.parse(text) else { return .notALink }
        guard toolsInstalled else { return .toolsMissing }
        if jobs.contains(where: { $0.link == link && !$0.isFinished }) { return .alreadyQueued }
        let title: String = switch link {
        case .song: "Song"
        case .playlist: "Playlist"
        }
        jobs.append(Job(link: link, title: title))
        startRunner()
        return .queued
    }

    /// Tries the failed songs of a Job again, and only those. A Job that failed before it had any songs
    /// (say, the playlist couldn't be read) starts over.
    func retry(_ job: Job) {
        guard job.isFinished, !jobs.contains(where: { $0.link == job.link && !$0.isFinished }) else { return }
        var again = job
        let hasFailedSongs = again.tracks.contains { if case .failed = $0.state { true } else { false } }
        if hasFailedSongs {
            for i in again.tracks.indices {
                if case .failed = again.tracks[i].state { again.tracks[i].state = .waiting }
            }
            again.retrying = true
        } else {
            again.tracks = []
            again.retrying = nil
        }
        again.phase = .queued
        again.finishedAt = nil
        // Back of the queue, behind links pasted in the meantime.
        jobs.removeAll { $0.id == job.id }
        jobs.append(again)
        saveHistory()
        startRunner()
    }

    func isInLibrary(_ videoID: String) -> Bool {
        librarySongs.contains { $0.videoID == videoID }
    }

    /// True while a Job for this video is waiting or running.
    func isDownloading(_ videoID: String) -> Bool {
        jobs.contains { !$0.isFinished && ($0.link == .song(videoID: videoID) || $0.tracks.contains { $0.videoID == videoID }) }
    }

    /// Takes a song out of a playlist: skips it if it hasn't downloaded yet, removes it from the Mirrored Playlist
    /// in Apple Music if it has, and remembers the choice for the next time this playlist is pasted.
    /// The song itself stays in the library.
    func removeFromPlaylist(_ videoID: String, in jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }), case .playlist(let playlistID, _) = job.link else { return }
        updateTrack(jobID, videoID) { $0.state = .removed }
        saveHistory()
        Task {
            try? await ledger.setRemoved(true, videoID: videoID, from: playlistID)
            if job.isFinished { await mirrorPlaylist(jobID: jobID, youtubePlaylistID: playlistID, showProgress: false) }
        }
    }

    /// Undoes `removeFromPlaylist`. A song that never downloaded comes back with the next Retry.
    func addBackToPlaylist(_ videoID: String, in jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }), case .playlist(let playlistID, _) = job.link else { return }
        Task {
            try? await ledger.setRemoved(false, videoID: videoID, from: playlistID)
            let inLedger = await ledger.contains(videoID)
            updateTrack(jobID, videoID) { $0.state = inLedger ? .skipped : .failed("Not downloaded yet. Use Retry to get it.") }
            saveHistory()
            if job.isFinished, inLedger { await mirrorPlaylist(jobID: jobID, youtubePlaylistID: playlistID, showProgress: false) }
        }
    }

    /// Every song in Apple Music plus everything Florestan imported. Built off the main thread, and reused for
    /// ten minutes or until Florestan imports something, because reading a big library takes a while and holds up imports.
    func libraryMatcher() async -> LibraryMatcher {
        if let cache = matcherCache, cache.songCount == librarySongs.count,
           Date.now.timeIntervalSince(cache.builtAt) < 10 * 60 {
            return cache.matcher
        }
        let imported = librarySongs.map { ($0.metadata.title, $0.metadata.artist) }
        let built = await Task.detached(priority: .utility) { () -> LibraryMatcher in
            var matcher = LibraryMatcher(songs: imported)
            if let songs = try? await MusicLibrary.allSongs() {
                for song in songs { matcher.add(title: song.name, artist: song.artist) }
            }
            return matcher
        }.value
        matcherCache = (built, librarySongs.count, .now)
        return built
    }

    // MARK: - Leftover files

    struct Leftovers { var count: Int; var bytes: Int64 }

    /// Files in ~/Music/Florestan that never made it into Apple Music (failed or stopped downloads).
    /// Files of imported songs are kept: if they're still there, Music is using them directly.
    func leftovers(olderThan age: TimeInterval = 0) -> [URL] {
        let busy = Set(jobs.filter { !$0.isFinished }.flatMap { $0.tracks.map(\.videoID) })
        let imported = Set(librarySongs.map(\.videoID))
        let files = (try? FileManager.default.contentsOfDirectory(at: downloadsFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { file in
            let videoID = String(file.lastPathComponent.split(separator: ".").first ?? "")
            guard !busy.contains(videoID), !imported.contains(videoID) else { return false }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Date.now.timeIntervalSince(modified) >= age
        }
    }

    func leftoverSummary() -> Leftovers {
        let files = leftovers()
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return Leftovers(count: files.count, bytes: bytes)
    }

    /// Deletes leftovers. Automatic clean-ups only take files older than three days, so a quick Retry can reuse them.
    @discardableResult
    func cleanUpLeftovers(olderThan age: TimeInterval = 0) -> Int {
        let files = leftovers(olderThan: age)
        for file in files { try? FileManager.default.removeItem(at: file) }
        return files.count
    }

    /// Whether the Job left something in Apple Music to open.
    func canOpenInAppleMusic(_ job: Job) -> Bool {
        job.isFinished && (job.importedCount + job.skippedCount) > 0
    }

    /// Opens the Mirrored Playlist of a playlist Job, or the song of a song Job, in Music.
    func openInAppleMusic(_ job: Job) {
        switch job.link {
        case .song(let videoID):
            showInAppleMusic(videoID)
        case .playlist(let playlistID, _):
            Task {
                guard let musicID = await ledger.mirroredPlaylist(for: playlistID) else { return }
                do {
                    try await MusicLibrary.revealPlaylist(id: musicID)
                } catch MusicError.notAuthorized {
                    musicNotAuthorized = true
                } catch {
                    Notifier.post(title: "Couldn't find “\(job.title)” in Apple Music", body: "The playlist may have been deleted. Retry recreates it.")
                }
            }
        }
    }

    func openInAppleMusic(jobID: UUID) {
        if let job = jobs.first(where: { $0.id == jobID }) { openInAppleMusic(job) }
    }

    /// True when the latest attempt at this video failed and nothing is retrying it.
    func downloadFailed(_ videoID: String) -> Bool {
        guard !isDownloading(videoID), !isInLibrary(videoID),
              let track = jobs.last(where: { $0.isFinished && $0.tracks.contains { $0.videoID == videoID } })?
                .tracks.first(where: { $0.videoID == videoID }) else { return false }
        if case .failed = track.state { return true }
        return false
    }

    func showInAppleMusic(_ videoID: String) {
        guard let entry = librarySongs.first(where: { $0.videoID == videoID }) else { return }
        Task {
            do {
                try await MusicLibrary.reveal(trackID: entry.musicTrackID)
            } catch MusicError.notAuthorized {
                musicNotAuthorized = true
            } catch {
                Notifier.post(title: "Couldn't find “\(entry.metadata.title)” in Apple Music",
                              body: "It may have been removed. Use Forget in Imported songs to download it again.")
            }
        }
    }

    func clearHistory() {
        jobs.removeAll(where: \.isFinished)
        saveHistory()
    }

    func forget(_ entry: LedgerEntry) async {
        try? await ledger.forget(entry.videoID)
        await refreshLibrary()
    }

    func refreshLibrary() async {
        librarySongs = await ledger.snapshot.songs.values.sorted { $0.importedAt > $1.importedAt }
        for entry in librarySongs {
            if entry.metadata.albumArtist != nil { albumBook.record(entry.metadata) }
        }
    }

    func refreshTools() async {
        toolsInstalled = Downloader.toolsInstalled
        ytdlpVersion = await Downloader.ytdlpVersion()
    }

    // MARK: - Running the Queue

    private func startRunner() {
        guard runner == nil else { return }
        runner = Task {
            while let next = jobs.first(where: { $0.phase == .queued }) {
                let task = Task { await self.run(next.id) }
                currentJob = (next.id, task)
                await task.value
                currentJob = nil
            }
            runner = nil
        }
    }

    /// Stops the running Job (songs already added stay added; Retry picks up the rest) or drops a waiting one.
    func cancel(_ job: Job) {
        if job.phase == .queued {
            jobs.removeAll { $0.id == job.id }
            saveHistory()
        } else if let currentJob, currentJob.id == job.id {
            currentJob.task.cancel()
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }

    private func updateTrack(_ jobID: UUID, _ videoID: String, _ change: (inout Track) -> Void) {
        update(jobID) { job in
            if let t = job.tracks.firstIndex(where: { $0.videoID == videoID }) { change(&job.tracks[t]) }
        }
    }

    private func run(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let downloader = Downloader(cookieBrowser: settings.useBrowserLogin ? settings.cookieBrowser : nil)

        if settings.keepYTDLPUpdated, settings.ytdlpUpgradeDue {
            update(id) { $0.phase = .preparing("Updating yt-dlp…") }
            await Downloader.upgradeYTDLP()
            settings.markYTDLPUpgraded()
            ytdlpVersion = await Downloader.ytdlpVersion()
        }

        // Plan the Tracks, unless this is a Retry of particular songs.
        if job.retrying == true {
            update(id) { $0.phase = .running }
        } else {
            switch job.link {
            case .song(let videoID):
                update(id) { $0.tracks = [Track(videoID: videoID, title: "Fetching song…")] }
                if let quick = await Downloader.quickInfo(videoID: videoID) {
                    let meta = TrackMetadata(from: VideoInfo(id: videoID, title: quick.title, channel: quick.author))
                    update(id) { job in
                        job.title = meta.title
                        job.tracks[0].title = meta.title
                        job.tracks[0].artist = meta.artist
                    }
                }
            case .playlist:
                update(id) { $0.phase = .preparing("Reading playlist…") }
                do {
                    let playlist = try await downloader.fetchPlaylist(job.link)
                    update(id) { job in
                        job.title = playlist.title ?? "Playlist"
                        job.tracks = playlist.entries.map { Track(videoID: $0.id, title: $0.title ?? "Untitled") }
                    }
                } catch {
                    finish(id, failure: Task.isCancelled ? "Stopped" : (error as? DownloadFailure)?.failure.message ?? error.localizedDescription)
                    return
                }
            }

            if case .playlist(let playlistID, _) = job.link {
                let removed = await ledger.removedVideos(from: playlistID)
                update(id) { job in
                    for i in job.tracks.indices where removed.contains(job.tracks[i].videoID) { job.tracks[i].state = .removed }
                }
            }
            for track in jobs.first(where: { $0.id == id })?.tracks ?? [] where track.state == .waiting {
                guard let known = await ledger.entry(for: track.videoID) else { continue }
                updateTrack(id, track.videoID) { t in
                    t.state = .skipped
                    t.title = known.metadata.title; t.artist = known.metadata.artist
                }
            }
            if case .song = job.link, let only = jobs.first(where: { $0.id == id })?.tracks.first, only.state == .skipped {
                update(id) { $0.title = only.title }
            }
            update(id) { $0.phase = .running }
        }

        // Download and Import, up to three Tracks at a time.
        let pending = jobs.first(where: { $0.id == id })?.tracks.filter { $0.state == .waiting }.map(\.videoID) ?? []
        let context = TrackContext(jobID: id, downloader: downloader)
        await withTaskGroup(of: Void.self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<3 {
                guard let videoID = iterator.next() else { break }
                group.addTask { await self.process(videoID, context) }
            }
            while await group.next() != nil {
                guard let videoID = iterator.next() else { continue }
                group.addTask { await self.process(videoID, context) }
            }
        }

        let stopped = Task.isCancelled
        if stopped {
            update(id) { job in
                for i in job.tracks.indices where !job.tracks[i].isDone { job.tracks[i].state = .failed("Stopped") }
            }
        }
        // Even a stopped playlist gets the songs that made it, in order.
        if case .playlist(let playlistID, _) = job.link {
            await numberAlbumTracks(jobID: id)
            await mirrorPlaylist(jobID: id, youtubePlaylistID: playlistID, showProgress: !stopped)
        }
        if stopped, let done = jobs.first(where: { $0.id == id }) {
            finish(id, failure: done.importedCount > 0 ? "Stopped after adding \(done.importedCount)" : "Stopped")
        } else {
            finish(id, failure: nil)
        }
    }

    /// Per-Job state shared by its Tracks.
    private final class TrackContext: @unchecked Sendable {
        let jobID: UUID
        let downloader: Downloader
        var upgradedYTDLP = false
        init(jobID: UUID, downloader: Downloader) { self.jobID = jobID; self.downloader = downloader }
    }

    private func process(_ videoID: String, _ context: TrackContext) async {
        let jobID = context.jobID
        // Removed while it was waiting its turn.
        if jobs.first(where: { $0.id == jobID })?.tracks.first(where: { $0.videoID == videoID })?.state == .removed { return }
        updateTrack(jobID, videoID) { $0.state = .downloading(0) }
        var attempt = 0
        while true {
            attempt += 1
            if Task.isCancelled {
                updateTrack(jobID, videoID) { $0.state = .failed("Stopped") }
                return
            }
            do {
                let downloaded = try await context.downloader.downloadAudio(videoID: videoID, into: downloadsFolder) { progress in
                    Task { @MainActor in
                        self.updateTrack(jobID, videoID) { t in
                            if case .downloading = t.state { t.state = .downloading(progress) }
                        }
                    }
                }
                // Songs of one album share an album artist, so Apple Music shows them as one album.
                let metadata = albumBook.group(TrackMetadata(from: downloaded.info))
                updateTrack(jobID, videoID) { t in
                    t.state = .importing; t.title = metadata.title; t.artist = metadata.artist
                }
                update(jobID) { job in if case .song = job.link { job.title = metadata.title } }

                let imported = try await MusicLibrary.importTrack(file: downloaded.file, metadata: metadata)
                try? await ledger.record(LedgerEntry(videoID: videoID, metadata: metadata, musicTrackID: imported.persistentID))
                // Music copied the file into its media folder; drop our copy.
                if let location = imported.location, location != downloaded.file.path {
                    try? FileManager.default.removeItem(at: downloaded.file)
                }
                updateTrack(jobID, videoID) { $0.state = .imported }
                return
            } catch let error as DownloadFailure {
                if error.failure.shouldUpgradeAndRetry, !context.upgradedYTDLP {
                    context.upgradedYTDLP = true
                    await Downloader.upgradeYTDLP()
                    continue
                }
                if !error.failure.isPermanent, attempt <= Self.retryDelays.count {
                    await waitBeforeRetry(attempt, jobID, videoID)
                    continue
                }
                if error.failure == .botCheck { botCheckHit = true }
                updateTrack(jobID, videoID) { $0.state = .failed(error.failure.message) }
                return
            } catch let error as MusicError {
                if case .notAuthorized = error {
                    musicNotAuthorized = true
                } else if attempt <= Self.retryDelays.count {
                    await waitBeforeRetry(attempt, jobID, videoID)
                    continue
                }
                updateTrack(jobID, videoID) { $0.state = .failed(error.localizedDescription) }
                return
            } catch {
                if attempt <= Self.retryDelays.count {
                    await waitBeforeRetry(attempt, jobID, videoID)
                    continue
                }
                updateTrack(jobID, videoID) { $0.state = .failed(error.localizedDescription) }
                return
            }
        }
    }

    /// Most failures that aren't permanent go away on a second try, so each Track gets two automatic retries.
    private static let retryDelays: [Duration] = [.seconds(3), .seconds(8)]

    private func waitBeforeRetry(_ attempt: Int, _ jobID: UUID, _ videoID: String) async {
        updateTrack(jobID, videoID) { $0.state = .downloading(0) }
        try? await Task.sleep(for: Self.retryDelays[attempt - 1])
    }

    /// Numbers the songs of each album in this playlist in playlist order, so the album plays in sequence.
    /// Counts every song of the playlist that's in the Ledger, including ones imported on an earlier run.
    private func numberAlbumTracks(jobID: UUID) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        var entries: [LedgerEntry] = []
        for track in job.tracks {
            if let entry = await ledger.entry(for: track.videoID) { entries.append(entry) }
        }
        // An album is its name plus its album artist: two "Greatest Hits" in one playlist are numbered separately.
        let byAlbum = Dictionary(grouping: entries, by: { "\($0.metadata.album.lowercased())|\($0.metadata.albumArtist ?? "")" })
        for (_, albumEntries) in byAlbum where albumEntries.count > 1 {
            for (index, var entry) in albumEntries.enumerated() where entry.metadata.trackNumber != index + 1 {
                entry.metadata.trackNumber = index + 1
                try? await MusicLibrary.setAlbumInfo(trackID: entry.musicTrackID, albumArtist: entry.metadata.albumArtist,
                                                     trackNumber: index + 1, trackCount: albumEntries.count)
                try? await ledger.record(entry)
            }
        }
    }

    /// One-time repair: albums and Mirrored Playlists imported before ordering existed get YouTube's order,
    /// using the most recent Job of each playlist.
    private func reorderEarlierPlaylists() async {
        let key = "reorderedPlaylistsV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for playlistID in await ledger.snapshot.mirroredPlaylists.keys {
            guard let job = jobs.last(where: { if case .playlist(playlistID, _) = $0.link { $0.isFinished } else { false } }) else { continue }
            await numberAlbumTracks(jobID: job.id)
            await mirrorPlaylist(jobID: job.id, youtubePlaylistID: playlistID, showProgress: false)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Songs imported before album grouping existed get an album artist now.
    private func groupOlderSongs() async {
        for entry in await ledger.snapshot.songs.values where entry.metadata.albumArtist == nil {
            var updated = entry
            let lead = entry.metadata.artist.components(separatedBy: ", ").first ?? entry.metadata.artist
            updated.metadata.albumArtist = lead
            updated.metadata = albumBook.group(updated.metadata)
            guard (try? await MusicLibrary.setAlbumInfo(trackID: entry.musicTrackID, albumArtist: updated.metadata.albumArtist,
                                                        trackNumber: nil, trackCount: nil)) != nil else { continue }
            try? await ledger.record(updated)
        }
        await refreshLibrary()
    }

    private func mirrorPlaylist(jobID: UUID, youtubePlaylistID: String, showProgress: Bool = true) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        var trackIDs: [String] = []
        for track in job.tracks where track.state != .removed {
            if let entry = await ledger.entry(for: track.videoID) { trackIDs.append(entry.musicTrackID) }
        }
        guard !trackIDs.isEmpty else { return }
        if showProgress { update(jobID) { $0.phase = .preparing("Updating playlist in Apple Music…") } }
        let existing = await ledger.mirroredPlaylist(for: youtubePlaylistID)
        do {
            let playlistID = try await MusicLibrary.mirror(playlistNamed: job.title, existingID: existing, trackIDs: trackIDs)
            try? await ledger.setMirroredPlaylist(playlistID, for: youtubePlaylistID)
        } catch {
            if case MusicError.notAuthorized = error { musicNotAuthorized = true }
        }
    }

    private func finish(_ id: UUID, failure: String?) {
        update(id) { job in
            job.finishedAt = .now
            job.retrying = nil
            if let failure {
                job.phase = .failed(failure)
                if failure == YTDLP.Failure.botCheck.message { botCheckHit = true }
            } else if !job.tracks.isEmpty, job.failedCount == job.tracks.count {
                job.phase = .failed(job.tracks.count == 1 ? Self.failureMessage(job.tracks[0]) : "All \(job.tracks.count) songs failed")
            } else {
                job.phase = .finished
            }
        }
        if let job = jobs.first(where: { $0.id == id }) {
            Notifier.jobFinished(job)
            // Earlier failed attempts of the same link are superseded once this one gets everything in.
            if job.phase == .finished, job.failedCount == 0 {
                jobs.removeAll { $0.id != id && $0.link == job.link && $0.isFinished }
            }
        }
        saveHistory()
        Task { await refreshLibrary() }
    }

    private static func failureMessage(_ track: Track) -> String {
        if case .failed(let why) = track.state { why } else { "Failed" }
    }

    private func saveHistory() {
        let keep = Array(jobs.suffix(100))
        if let data = try? JSONEncoder.florestan.encode(keep) { try? data.write(to: historyURL, options: .atomic) }
    }
}
