import Foundation

/// Reading release versions and checksums, for keeping Florestan and yt-dlp up to date.
public enum Releases {
    /// True when `candidate` is a later version than `current`. Compares number by number, so "0.0.10" is later than
    /// "0.0.9" and yt-dlp's dates ("2026.10.21") order by date. A leading "v", as in a tag like "v0.0.2", is ignored.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        guard !a.isEmpty, !b.isEmpty else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        let parts = v.split(separator: ".").map { Int($0) }
        return parts.contains(nil) ? [] : parts.compactMap { $0 }
    }

    /// The SHA-256 a checksums file (lines of "<hash>  <file name>", as yt-dlp's SHA2-256SUMS) gives for `fileName`.
    public static func checksum(for fileName: String, in sums: String) -> String? {
        for line in sums.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            // `shasum -b` marks binary files with "*" before the name.
            let name = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if name == fileName { return parts[0].lowercased() }
        }
        return nil
    }
}

/// What the Music app reports it's playing, as Florestan's status script returns it: player state, persistent ID,
/// title, artist, album and whether the cover was saved, separated by the unit separator (U+001F).
public struct PlayerStatus: Equatable, Sendable {
    public enum State: String, Sendable { case playing, paused, stopped }
    public var state: State
    public var trackID: String
    public var title: String
    public var artist: String
    public var album: String
    public var wroteArtwork: Bool

    public init(state: State, trackID: String, title: String, artist: String, album: String, wroteArtwork: Bool) {
        self.state = state; self.trackID = trackID; self.title = title; self.artist = artist; self.album = album
        self.wroteArtwork = wroteArtwork
    }

    /// The status, or nil when Music is stopped or the output isn't a status.
    public static func parse(_ output: String) -> PlayerStatus? {
        let f = output.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 6, let state = State(rawValue: f[0]), state != .stopped else { return nil }
        return PlayerStatus(state: state, trackID: f[1], title: f[2], artist: f[3], album: f[4], wroteArtwork: f[5] == "1")
    }
}
