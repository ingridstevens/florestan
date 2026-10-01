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

    /// Whether an album's songs may be renumbered from a YouTube Music track list. A list missing any of the album's
    /// songs is a different edition (YouTube Music's "Brol La Suite" is only the 8 new songs), so its numbers would be wrong.
    public static func listingCoversAlbum(albumTracks: [String], songTitles: [String]) -> Bool {
        let numbers = trackNumbers(albumTracks: albumTracks, songs: songTitles.enumerated().map { (String($0.offset), $0.element) })
        return numbers.count == songTitles.count
    }

    /// A song as Apple Music has it, with the details that decide whether Music shows its album as one.
    public struct AlbumTrack: Equatable, Sendable {
        public var id: String
        public var title: String
        public var album: String
        public var albumArtist: String
        public var year: Int
        public var cover: Cover?

        public struct Cover: Equatable, Sendable {
            public var width: Int
            public var height: Int
            /// Identifies the image, so songs that already share a cover aren't rewritten.
            public var fingerprint: String
            public var isSquare: Bool { width == height }
            public init(width: Int, height: Int, fingerprint: String) {
                self.width = width; self.height = height; self.fingerprint = fingerprint
            }
        }

        public init(id: String, title: String, album: String, albumArtist: String, year: Int, cover: Cover?) {
            self.id = id; self.title = title; self.album = album; self.albumArtist = albumArtist; self.year = year; self.cover = cover
        }
    }

    /// What to change on one song so its whole album matches. `nil` fields stay as they are.
    public struct AlbumFix: Equatable, Sendable {
        public var trackID: String
        public var album: String
        public var albumArtist: String?
        public var year: Int?
        /// The song whose cover this one should get.
        public var coverFrom: String?
    }

    /// Apple Music splits an album when its songs differ in album artist (even only in how "è" is encoded) or year,
    /// and shows a mix of covers when they differ. For every album with more than one song, this picks the album artist
    /// and year most of its songs have and a square cover (the most common one, else the largest), and lists the changes.
    public static func consistencyFixes(_ tracks: [AlbumTrack]) -> [AlbumFix] {
        let onAlbums = tracks.filter { LibraryMatcher.normalizeTitle($0.album) != LibraryMatcher.normalizeTitle($0.title) }
        var groups: [String: [AlbumTrack]] = [:]
        for track in onAlbums {
            let lead = LibraryMatcher.artistNames(track.albumArtist).sorted().joined(separator: ",")
            groups["\(LibraryMatcher.fold(track.album.precomposedStringWithCanonicalMapping))|\(lead)", default: []].append(track)
        }
        var fixes: [AlbumFix] = []
        for group in groups.values where group.count > 1 {
            let albumArtist = mostCommon(group.map { $0.albumArtist.precomposedStringWithCanonicalMapping })!
            let year = mostCommon(group.map(\.year).filter { $0 > 0 }, tieBreak: <)
            let covers = group.compactMap(\.cover)
            let squares = covers.filter(\.isSquare)
            let pool = squares.isEmpty ? covers : squares
            let best = mostCommon(pool.map(\.fingerprint)) { a, b in
                pool.first { $0.fingerprint == a }!.width > pool.first { $0.fingerprint == b }!.width
            }
            let source = group.first { $0.cover?.fingerprint == best }
            for track in group {
                var fix = AlbumFix(trackID: track.id, album: track.album)
                // Swift's == treats both encodings of "è" as equal; Apple Music doesn't, so compare the characters themselves.
                if !track.albumArtist.unicodeScalars.elementsEqual(albumArtist.unicodeScalars) { fix.albumArtist = albumArtist }
                if let year, track.year != year { fix.year = year }
                if let source, track.cover?.fingerprint != best { fix.coverFrom = source.id }
                if fix.albumArtist != nil || fix.year != nil || fix.coverFrom != nil { fixes.append(fix) }
            }
        }
        return fixes.sorted { ($0.album, $0.trackID) < ($1.album, $1.trackID) }
    }

    /// The value that appears most often; ties go to the one `tieBreak` orders first (by default, the first seen).
    static func mostCommon<T: Hashable>(_ values: [T], tieBreak: ((T, T) -> Bool)? = nil) -> T? {
        var counts: [T: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return values.reduce(into: [T]()) { if !$0.contains($1) { $0.append($1) } }
            .max { a, b in
                if counts[a]! != counts[b]! { return counts[a]! < counts[b]! }
                return tieBreak.map { $0(b, a) } ?? false
            }
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
