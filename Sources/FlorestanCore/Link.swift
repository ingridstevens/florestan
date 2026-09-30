import Foundation

/// A YouTube or YouTube Music URL handed to Florestan. See CONTEXT.md.
public enum Link: Equatable, Hashable, Sendable, Codable {
    /// A single video.
    case song(videoID: String)
    /// A playlist or YouTube Music album, including a video link that also names a playlist.
    case playlist(id: String, url: URL)

    /// The canonical URL Florestan hands to yt-dlp.
    public var url: URL {
        switch self {
        case .song(let id): URL(string: "https://www.youtube.com/watch?v=\(id)")!
        case .playlist(_, let url): url
        }
    }

    public var isPlaylist: Bool {
        if case .playlist = self { true } else { false }
    }

    /// Parses pasted text into a Link, or returns nil if it isn't a YouTube or YouTube Music link.
    public static func parse(_ text: String) -> Link? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(" ") else { return nil }
        if !raw.lowercased().hasPrefix("http") { raw = "https://" + raw }
        guard let components = URLComponents(string: raw),
              let host = components.host?.lowercased() else { return nil }

        let query = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let pathParts = components.path.split(separator: "/").map(String.init)

        if host == "youtu.be" || host == "www.youtu.be" {
            guard let id = pathParts.first, isVideoID(id) else { return nil }
            return .song(videoID: id)
        }

        let youtubeHosts: Set = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
        guard youtubeHosts.contains(host) else { return nil }

        // Any link naming a real playlist means the whole playlist, even if it also points at one video in it.
        if let list = query["list"], isPlaylistID(list) {
            return .playlist(id: list, url: URL(string: "https://www.youtube.com/playlist?list=\(list)")!)
        }
        if let v = query["v"], isVideoID(v) {
            return .song(videoID: v)
        }
        if pathParts.count >= 2, ["shorts", "live", "embed"].contains(pathParts[0]), isVideoID(pathParts[1]) {
            return .song(videoID: pathParts[1])
        }
        // YouTube Music album pages: music.youtube.com/browse/MPREb_…
        if host == "music.youtube.com", pathParts.count == 2, pathParts[0] == "browse", pathParts[1].hasPrefix("MPRE") {
            return .playlist(id: pathParts[1], url: URL(string: "https://music.youtube.com/browse/\(pathParts[1])")!)
        }
        return nil
    }

    static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func isPlaylistID(_ s: String) -> Bool {
        // "Mix" radio lists (RD…) are generated per viewer and endless; they aren't real playlists.
        s.count >= 10 && !s.hasPrefix("RD") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
