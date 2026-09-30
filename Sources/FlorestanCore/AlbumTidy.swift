import Foundation

/// The rules behind "Tidy albums": which songs need an album, which album a lookup result lands on,
/// which songs are duplicates, and what number each song gets on its album.
public enum AlbumTidy {
    /// Songs imported from plain YouTube videos carry no album, so Florestan filed each under its own title.
    public static func needsAlbum(_ metadata: TrackMetadata) -> Bool {
        LibraryMatcher.normalizeTitle(metadata.album) == LibraryMatcher.normalizeTitle(metadata.title)
    }

    public struct KnownAlbum: Equatable, Sendable {
        public var name: String
        public var albumArtist: String
        public init(name: String, albumArtist: String) { self.name = name; self.albumArtist = albumArtist }
    }

    /// Where a song should go, given the album YouTube Music names for it. Prefers an album already in the library
    /// by the same artist that is that album or an expanded edition of it ("Brol" → "Brol La Suite"), so songs
    /// end up together instead of split across editions.
    public static func destination(foundAlbum: String, artist: String, existing: [KnownAlbum]) -> KnownAlbum {
        let names = LibraryMatcher.artistNames(artist)
        let found = LibraryMatcher.normalizeTitle(foundAlbum)
        let sameArtist = existing.filter { LibraryMatcher.overlap(LibraryMatcher.artistNames($0.albumArtist), names) }
        let editions = sameArtist.filter {
            let name = LibraryMatcher.normalizeTitle($0.name)
            return name == found || name.hasPrefix(found + " ")
        }
        if let pick = editions.min(by: { $0.name.count > $1.name.count }) { return pick }
        let lead = artist.components(separatedBy: ", ").first ?? artist
        return KnownAlbum(name: foundAlbum, albumArtist: lead)
    }

    /// Whether a lookup result is really the song asked about, not a different song by the same artist.
    public static func isSameSong(title: String, artist: String, foundTitle: String, foundArtist: String) -> Bool {
        let matcher = LibraryMatcher(songs: [(title, artist)])
        return matcher.contains(title: foundTitle, artist: foundArtist)
    }

    /// Track numbers for `songs` from an album's track list, matched by title.
    public static func trackNumbers(albumTracks: [String], songs: [(id: String, title: String)]) -> [String: Int] {
        let keys = albumTracks.map(LibraryMatcher.normalizeTitle)
        var result: [String: Int] = [:]
        for song in songs {
            let key = LibraryMatcher.normalizeTitle(song.title)
            if let i = keys.firstIndex(where: { $0 == key || LibraryMatcher.isVersion(of: $0, key) }) { result[song.id] = i + 1 }
        }
        return result
    }

    /// Groups of songs that are the same song by the same artist. Each group is ordered best copy first:
    /// the one filed on a real album, then the earliest imported.
    public static func duplicates(_ entries: [LedgerEntry]) -> [[LedgerEntry]] {
        var groups: [String: [LedgerEntry]] = [:]
        for entry in entries {
            let lead = LibraryMatcher.artistNames(entry.metadata.artist.components(separatedBy: ", ").first ?? "").sorted().joined()
            groups["\(LibraryMatcher.normalizeTitle(entry.metadata.title))|\(lead)", default: []].append(entry)
        }
        return groups.values.filter { $0.count > 1 }.map { group in
            group.sorted { a, b in
                let aAlbum = !needsAlbum(a.metadata), bAlbum = !needsAlbum(b.metadata)
                return aAlbum != bAlbum ? aAlbum : a.importedAt < b.importedAt
            }
        }
        .sorted { $0[0].metadata.title < $1[0].metadata.title }
    }
}
