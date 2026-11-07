import AppKit
import FlorestanCore
import Observation

/// Plays music in the Music app. Florestan is only the remote control: Music does the playing, so everything in the
/// library plays, and media keys, Control Center and AirPlay keep working. Its commands have their own queue, so
/// pressing Play never waits behind an import.
enum MusicPlayer {
    private static let lane = SerialQueue()
    static let musicBundleID = "com.apple.Music"

    static var musicIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleID).isEmpty
    }

    /// Plays a song from the library, on its own: Music doesn't go on to other songs afterwards, so Next does
    /// nothing until something else plays. Playing a playlist plays it through.
    static func play(trackID: String) async throws {
        try await run("""
        on run argv
            tell application "Music" to play (first track of library playlist 1 whose persistent ID is (item 1 of argv))
        end run
        """, [trackID])
    }

    /// Plays a playlist from its first song.
    static func play(playlistID: String) async throws {
        try await run("""
        on run argv
            tell application "Music" to play (first user playlist whose persistent ID is (item 1 of argv))
        end run
        """, [playlistID])
    }

    static func playPause() async throws {
        try await run(#"tell application "Music" to playpause"#)
    }

    static func next() async throws {
        try await run(#"tell application "Music" to next track"#)
    }

    /// Back to the start of the song, or to the one before when it has only just started, like Music's own button.
    static func previous() async throws {
        try await run(#"tell application "Music" to back track"#)
    }

    /// What Music is playing, or nil when it's stopped or closed. Writes the song's cover to `artworkFile` unless the
    /// song is still `knownTrackID`, whose cover is already shown.
    static func status(knownTrackID: String?, artworkFile: URL) async throws -> PlayerStatus? {
        guard musicIsRunning else { return nil }
        let output = try await run("""
        on run argv
            set us to (ASCII character 31)
            tell application "Music"
                -- Not "st": AppleScript reads that as an ordinal suffix ("1st").
                set playerState to player state as text
                if playerState is not "playing" and playerState is not "paused" then return playerState
                set t to current track
                set pid to ""
                try
                    set pid to persistent ID of t
                end try
                set wrote to "0"
                if pid is not item 1 of argv then
                    try
                        set d to raw data of artwork 1 of t
                        set fh to open for access (POSIX file (item 2 of argv)) with write permission
                        set eof fh to 0
                        write d to fh
                        close access fh
                        set wrote to "1"
                    end try
                end if
                return playerState & us & pid & us & (name of t) & us & (artist of t) & us & (album of t) & us & wrote
            end tell
        end run
        """, [knownTrackID ?? "", artworkFile.path])
        return PlayerStatus.parse(output)
    }

    @discardableResult
    private static func run(_ script: String, _ arguments: [String] = []) async throws -> String {
        try await MusicLibrary.run(script, arguments, on: lane)
    }
}

/// What Music is playing, kept current from the notification Music sends whenever playback changes, and the
/// controls for it. Reads nothing while Music is closed, so it never opens Music by itself.
@MainActor @Observable
final class NowPlaying {
    struct Song: Equatable {
        var trackID: String
        var title: String
        var artist: String
        var album: String
        var artwork: NSImage?
    }

    private(set) var song: Song?
    private(set) var isPlaying = false
    /// Called when macOS won't let Florestan control Music, so the app can explain how to allow it.
    var onNotAuthorized: (() -> Void)?

    private let artworkFile = FileManager.default.temporaryDirectory.appendingPathComponent("florestan-now-playing-cover")
    private var refreshing: Task<Void, Never>?

    init() {
        // The screenshots' demo state shows a made-up song and never reads Music, which would show the real one.
        if let home = AppModel.homeOverride {
            song = Song(trackID: "demo", title: "Song Title Here", artist: "Artista Artita", album: "Song Title Here",
                        artwork: NSImage(contentsOf: home.appendingPathComponent("Thumbnails/demo0000001.png")))
            isPlaying = true
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func play(trackID: String) { send { try await MusicPlayer.play(trackID: trackID) } }
    func play(playlistID: String) { send { try await MusicPlayer.play(playlistID: playlistID) } }
    func playPause() {
        isPlaying.toggle()
        send { try await MusicPlayer.playPause() }
    }
    func next() { send { try await MusicPlayer.next() } }
    func previous() { send { try await MusicPlayer.previous() } }

    private func send(_ command: @escaping @Sendable () async throws -> Void) {
        Task {
            do {
                try await command()
            } catch MusicError.notAuthorized {
                onNotAuthorized?()
            } catch {}
            refresh()
        }
    }

    /// Reads Music's state again; a refresh already under way is replaced, so the latest state wins.
    func refresh() {
        guard AppModel.homeOverride == nil else { return }
        refreshing?.cancel()
        let known = song?.artwork == nil ? nil : song?.trackID
        let file = artworkFile
        refreshing = Task {
            let status: PlayerStatus?
            do {
                status = try await MusicPlayer.status(knownTrackID: known, artworkFile: file)
            } catch MusicError.notAuthorized {
                onNotAuthorized?()
                return
            } catch {
                return
            }
            if Task.isCancelled { return }
            guard let status else {
                song = nil
                isPlaying = false
                return
            }
            let artwork = status.wroteArtwork ? NSImage(contentsOf: file) : (status.trackID == song?.trackID ? song?.artwork : nil)
            song = Song(trackID: status.trackID, title: status.title, artist: status.artist, album: status.album, artwork: artwork)
            isPlaying = status.state == .playing
        }
    }
}
