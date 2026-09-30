import Foundation

/// Decides which album artist a song gets so songs of one album group together in Apple Music,
/// without merging different albums that happen to share a name ("Greatest Hits" by Queen and by ABBA).
/// A song joins an album already on record when the album names match and their artists overlap.
public struct AlbumBook: Sendable {
    private struct Album: Sendable {
        var albumArtist: String
        var artists: Set<String>
    }

    private var albums: [String: [Album]] = [:]

    public init() {}

    /// Returns `metadata` with the album artist of the matching album on record, recording a new album if there's none.
    public mutating func group(_ metadata: TrackMetadata) -> TrackMetadata {
        var copy = metadata
        let key = metadata.album.lowercased()
        let names = Self.names(of: metadata)
        if let i = albums[key]?.firstIndex(where: { LibraryMatcher.overlap($0.artists, names) }) {
            albums[key]![i].artists.formUnion(names)
            copy.albumArtist = albums[key]![i].albumArtist
        } else if let artist = metadata.albumArtist {
            albums[key, default: []].append(Album(albumArtist: artist, artists: names))
        }
        return copy
    }

    /// Records an album already in Apple Music.
    public mutating func record(_ metadata: TrackMetadata) {
        _ = group(metadata)
    }

    private static func names(of metadata: TrackMetadata) -> Set<String> {
        LibraryMatcher.artistNames(metadata.artist).union(LibraryMatcher.artistNames(metadata.albumArtist ?? ""))
    }
}
