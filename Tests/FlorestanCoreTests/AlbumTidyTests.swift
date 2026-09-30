import Foundation
import Testing
@testable import FlorestanCore

@Suite struct AlbumTidyTests {
    @Test func singlesNeedAnAlbum() {
        #expect(AlbumTidy.needsAlbum(TrackMetadata(title: "Jalousie", artist: "Angèle", album: "Jalousie")))
        #expect(!AlbumTidy.needsAlbum(TrackMetadata(title: "Perdus", artist: "Angèle", album: "Brol La Suite")))
    }

    @Test func prefersTheExpandedEditionYouHave() {
        let existing = [AlbumTidy.KnownAlbum(name: "Brol La Suite", albumArtist: "Angèle"),
                        AlbumTidy.KnownAlbum(name: "Brol", albumArtist: "Someone Else")]
        let pick = AlbumTidy.destination(foundAlbum: "Brol", artist: "Angèle", existing: existing)
        #expect(pick == AlbumTidy.KnownAlbum(name: "Brol La Suite", albumArtist: "Angèle"))
    }

    @Test func newAlbumWhenYouHaveNone() {
        let pick = AlbumTidy.destination(foundAlbum: "Nonante-Cinq", artist: "Angèle, Damso", existing: [])
        #expect(pick == AlbumTidy.KnownAlbum(name: "Nonante-Cinq", albumArtist: "Angèle"))
    }

    @Test func doesNotJumpToADifferentAlbumThatStartsTheSame() {
        let existing = [AlbumTidy.KnownAlbum(name: "Brolly Songs", albumArtist: "Angèle")]
        #expect(AlbumTidy.destination(foundAlbum: "Brol", artist: "Angèle", existing: existing).name == "Brol")
    }

    @Test func rejectsADifferentSong() {
        #expect(AlbumTidy.isSameSong(title: "Jalousie", artist: "Angèle", foundTitle: "Jalousie", foundArtist: "Angèle"))
        #expect(!AlbumTidy.isSameSong(title: "Jalousie", artist: "Angèle", foundTitle: "Je veux tes yeux", foundArtist: "Angèle"))
    }

    @Test func numbersSongsFromTheTrackList() {
        let numbers = AlbumTidy.trackNumbers(albumTracks: ["La Thune", "Balance ton quoi", "Jalousie"],
                                             songs: [("a", "Jalousie"), ("b", "Balance Ton Quoi"), ("c", "Nope")])
        #expect(numbers == ["a": 3, "b": 2])
    }

    @Test func findsDuplicatesAndPrefersTheAlbumCopy() {
        let single = LedgerEntry(videoID: "v1", metadata: .init(title: "Perdus", artist: "Angèle", album: "Perdus"),
                                 musicTrackID: "A", importedAt: Date(timeIntervalSince1970: 1))
        let album = LedgerEntry(videoID: "v2", metadata: .init(title: "Perdus", artist: "Angèle", album: "Brol La Suite"),
                                musicTrackID: "B", importedAt: Date(timeIntervalSince1970: 2))
        let other = LedgerEntry(videoID: "v3", metadata: .init(title: "Flemme", artist: "Angèle", album: "Flemme"), musicTrackID: "C")
        let groups = AlbumTidy.duplicates([single, album, other])
        #expect(groups.count == 1)
        #expect(groups[0].map(\.videoID) == ["v2", "v1"])
    }
}
