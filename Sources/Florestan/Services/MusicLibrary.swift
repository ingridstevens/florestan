import Foundation
import FlorestanCore

enum MusicError: Error, LocalizedError {
    case notAuthorized
    case script(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            "Florestan isn't allowed to control Music. Turn it on in System Settings › Privacy & Security › Automation."
        case .script(let message):
            "Apple Music: \(message)"
        }
    }
}

/// Talks to the Music app through its scripting interface. Scripts receive values via `argv`, never string interpolation.
enum MusicLibrary {
    struct ImportedTrack {
        var persistentID: String
        /// Where Music keeps the file. Differs from the source when Music copied it into its media folder.
        var location: String?
    }

    static func importTrack(file: URL, metadata: TrackMetadata) async throws -> ImportedTrack {
        let script = """
        on run argv
            -- Music rejects a bare file reference with error -50; it needs an alias and an explicit destination.
            set f to (POSIX file (item 1 of argv)) as alias
            tell application "Music"
                set t to add f to library playlist 1
                set name of t to item 2 of argv
                set artist of t to item 3 of argv
                set album of t to item 4 of argv
                set pid to persistent ID of t
                set loc to ""
                try
                    set loc to POSIX path of (get location of t)
                end try
                return pid & linefeed & loc
            end tell
        end run
        """
        let output = try await run(script, [file.path, metadata.title, metadata.artist, metadata.album])
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let id = lines.first, !id.isEmpty else { throw MusicError.script("Music didn't return the imported track.") }
        return ImportedTrack(persistentID: id, location: lines.dropFirst().first?.nonEmpty)
    }

    /// Finds the playlist by persistent ID (or creates one named `name`) and appends any of `trackIDs` it doesn't contain yet, in order.
    /// Returns the playlist's persistent ID.
    static func mirror(playlistNamed name: String, existingID: String?, trackIDs: [String]) async throws -> String {
        let script = """
        on run argv
            set plName to item 1 of argv
            set plID to item 2 of argv
            set trackIDs to items 3 thru -1 of argv
            tell application "Music"
                set p to missing value
                if plID is not "" then
                    try
                        set p to first user playlist whose persistent ID is plID
                    end try
                end if
                if p is missing value then set p to make new user playlist with properties {name:plName}
                set existing to {}
                try
                    set existing to persistent ID of every track of p
                end try
                repeat with tid in trackIDs
                    set tid to tid as text
                    if existing does not contain tid then
                        try
                            duplicate (first track of library playlist 1 whose persistent ID is tid) to p
                        end try
                    end if
                end repeat
                return persistent ID of p
            end tell
        end run
        """
        // A trailing "" keeps `items 3 thru -1` valid when there are no tracks.
        let args = [name, existingID ?? ""] + (trackIDs.isEmpty ? [""] : trackIDs)
        return try await run(script, args).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    struct LibraryTrack: Sendable, Identifiable, Hashable {
        var id: String
        var name: String
        var artist: String
        var album: String
        var genre: String
    }

    /// Every song in the library (music only, no podcasts or videos).
    static func allSongs() async throws -> [LibraryTrack] {
        let script = """
        on run argv
            set us to (ASCII character 31)
            set rs to (ASCII character 30)
            -- One bulk request per property; per-track requests take minutes on big libraries.
            tell application "Music"
                set src to a reference to (every track of library playlist 1 whose media kind is song)
                set tIDs to persistent ID of src
                set tNames to name of src
                set tArtists to artist of src
                set tAlbums to album of src
                set tGenres to genre of src
            end tell
            set out to {}
            repeat with i from 1 to count of tIDs
                set end of out to (item i of tIDs) & us & (item i of tNames) & us & (item i of tArtists) & us & (item i of tAlbums) & us & (item i of tGenres)
            end repeat
            set AppleScript's text item delimiters to rs
            return out as text
        end run
        """
        let output = try await run(script, [])
        return output.split(separator: "\u{1E}").compactMap { record in
            let f = record.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 5 else { return nil }
            return LibraryTrack(id: f[0].trimmingCharacters(in: .whitespacesAndNewlines), name: f[1], artist: f[2], album: f[3], genre: f[4])
        }
    }

    private static func run(_ script: String, _ arguments: [String]) async throws -> String {
        let osascript = URL(fileURLWithPath: "/usr/bin/osascript")
        let result = try await Shell.run(osascript, ["-e", script] + arguments)
        guard result.succeeded else {
            if result.stderr.contains("-1743") { throw MusicError.notAuthorized }
            let message = result.stderr.replacingOccurrences(of: #"^.*execution error: "#, with: "", options: .regularExpression)
            throw MusicError.script(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.stdout.trimmingCharacters(in: CharacterSet.newlines)
    }
}
