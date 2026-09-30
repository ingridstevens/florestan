import Foundation

/// The subset of yt-dlp's info JSON that Florestan reads.
public struct VideoInfo: Decodable, Sendable {
    public var id: String
    public var title: String
    public var channel: String?
    public var uploader: String?
    public var track: String?
    public var artist: String?
    public var artists: [String]?
    public var album: String?

    public init(id: String, title: String, channel: String? = nil, uploader: String? = nil,
                track: String? = nil, artist: String? = nil, artists: [String]? = nil, album: String? = nil) {
        self.id = id; self.title = title; self.channel = channel; self.uploader = uploader
        self.track = track; self.artist = artist; self.artists = artists; self.album = album
    }
}

/// The song details Florestan writes into Apple Music.
public struct TrackMetadata: Equatable, Sendable, Codable {
    public var title: String
    public var artist: String
    public var album: String
    /// Apple Music groups songs into one album by album + album artist, so songs of one album must share this.
    public var albumArtist: String?
    public var trackNumber: Int?

    public init(title: String, artist: String, album: String, albumArtist: String? = nil, trackNumber: Int? = nil) {
        self.title = title; self.artist = artist; self.album = album
        self.albumArtist = albumArtist; self.trackNumber = trackNumber
    }

    /// Prefers YouTube Music's own fields; otherwise parses "Artist - Title" and strips video clutter.
    public init(from info: VideoInfo) {
        let musicArtist = info.artists.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? info.artist
        if let track = info.track?.nonBlank, let artist = musicArtist?.nonBlank {
            let leadArtist = info.artists?.first?.nonBlank ?? artist
            self.init(title: track, artist: artist, album: info.album?.nonBlank ?? track, albumArtist: leadArtist)
            return
        }

        let cleaned = Self.stripClutter(info.title)
        if let (artist, title) = Self.splitArtistTitle(cleaned) {
            self.init(title: title, artist: artist, album: title, albumArtist: artist)
        } else {
            let channel = Self.cleanChannel(info.channel ?? info.uploader ?? "").nonBlank ?? "Unknown Artist"
            self.init(title: cleaned, artist: channel, album: cleaned, albumArtist: channel)
        }
    }

    // MARK: - Rules

    private static let clutterWords =
        #"official|video|audio|lyrics?|visuali[sz]er|hd|hq|4k|mv|m/v|videoclip|clip officiel|music video"#

    static func stripClutter(_ title: String) -> String {
        var s = title
        // Bracketed clutter: (Official Video), [4K], 【MV】 …
        let bracketed = #"\s*[\(\[【][^\)\]】]*?\b(?:\#(clutterWords))\b[^\)\]】]*[\)\]】]"#
        s = s.replacingOccurrences(of: bracketed, with: "", options: [.regularExpression, .caseInsensitive])
        // Trailing "| Official Video" style suffixes.
        let piped = #"\s*[|｜].*\b(?:\#(clutterWords))\b.*$"#
        s = s.replacingOccurrences(of: piped, with: "", options: [.regularExpression, .caseInsensitive])
        return s.collapsingWhitespace
    }

    static func splitArtistTitle(_ s: String) -> (String, String)? {
        for separator in [" - ", " – ", " — ", " -- "] {
            if let range = s.range(of: separator) {
                let artist = String(s[..<range.lowerBound]).collapsingWhitespace
                let title = String(s[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”' ")).collapsingWhitespace
                if !artist.isEmpty, !title.isEmpty { return (artist, title) }
            }
        }
        return nil
    }

    static func cleanChannel(_ channel: String) -> String {
        var s = channel
        if s.hasSuffix(" - Topic") { s.removeLast(" - Topic".count) }
        if s.hasSuffix("VEVO"), s.count > 4 { s.removeLast(4) }
        return s.collapsingWhitespace
    }
}

extension String {
    var nonBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var collapsingWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
