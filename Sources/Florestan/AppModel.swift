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
        Task { await refreshLibrary(); await refreshTools() }
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
                await run(next.id)
            }
            runner = nil
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

        // Plan the Tracks.
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
                finish(id, failure: (error as? DownloadFailure)?.failure.message ?? error.localizedDescription)
                return
            }
        }

        for track in jobs.first(where: { $0.id == id })?.tracks ?? [] where await ledger.contains(track.videoID) {
            let known = await ledger.entry(for: track.videoID)
            updateTrack(id, track.videoID) { t in
                t.state = .skipped
                if let known { t.title = known.metadata.title; t.artist = known.metadata.artist }
            }
        }
        if case .song = job.link, let only = jobs.first(where: { $0.id == id })?.tracks.first, only.state == .skipped {
            update(id) { $0.title = only.title }
        }
        update(id) { $0.phase = .running }

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

        if case .playlist(let playlistID, _) = job.link {
            await mirrorPlaylist(jobID: id, youtubePlaylistID: playlistID)
        }
        finish(id, failure: nil)
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
        updateTrack(jobID, videoID) { $0.state = .downloading(0) }
        var retried = false
        while true {
            do {
                let downloaded = try await context.downloader.downloadAudio(videoID: videoID, into: downloadsFolder) { progress in
                    Task { @MainActor in
                        self.updateTrack(jobID, videoID) { t in
                            if case .downloading = t.state { t.state = .downloading(progress) }
                        }
                    }
                }
                let metadata = TrackMetadata(from: downloaded.info)
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
                if error.failure.shouldUpgradeAndRetry, !retried, !context.upgradedYTDLP {
                    context.upgradedYTDLP = true
                    retried = true
                    await Downloader.upgradeYTDLP()
                    continue
                }
                if error.failure == .botCheck { botCheckHit = true }
                updateTrack(jobID, videoID) { $0.state = .failed(error.failure.message) }
                return
            } catch let error as MusicError {
                if case .notAuthorized = error { musicNotAuthorized = true }
                updateTrack(jobID, videoID) { $0.state = .failed(error.localizedDescription) }
                return
            } catch {
                updateTrack(jobID, videoID) { $0.state = .failed(error.localizedDescription) }
                return
            }
        }
    }

    private func mirrorPlaylist(jobID: UUID, youtubePlaylistID: String) async {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        var trackIDs: [String] = []
        for track in job.tracks {
            if let entry = await ledger.entry(for: track.videoID) { trackIDs.append(entry.musicTrackID) }
        }
        guard !trackIDs.isEmpty else { return }
        update(jobID) { $0.phase = .preparing("Updating playlist in Apple Music…") }
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
            if let failure {
                job.phase = .failed(failure)
                if failure == YTDLP.Failure.botCheck.message { botCheckHit = true }
            } else if !job.tracks.isEmpty, job.failedCount == job.tracks.count {
                job.phase = .failed(job.tracks.count == 1 ? Self.failureMessage(job.tracks[0]) : "All \(job.tracks.count) songs failed")
            } else {
                job.phase = .finished
            }
        }
        if let job = jobs.first(where: { $0.id == id }) { Notifier.jobFinished(job) }
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
