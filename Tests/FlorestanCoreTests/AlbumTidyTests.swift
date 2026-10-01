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

    @Test func refusesATrackListFromAnotherEdition() {
        let suiteOnly = ["Oui ou non", "Perdus", "Insomnies", "Tu me regardes", "Que du love", "Victime des réseaux", "Nombreux", "Ta reine"]
        #expect(!AlbumTidy.listingCoversAlbum(albumTracks: suiteOnly, songTitles: ["La Thune", "Perdus", "Nombreux"]))
        #expect(AlbumTidy.listingCoversAlbum(albumTracks: suiteOnly, songTitles: ["Perdus", "Nombreux"]))
    }

    @Test func storesAccentsOneWay() {
        let decomposed = "Ange\u{300}le"
        let metadata = TrackMetadata(title: "Libre", artist: decomposed, album: "Nonante-Cinq", albumArtist: decomposed)
        #expect(metadata.albumArtist!.unicodeScalars.count == 6)
        #expect(metadata.artist == "Angèle")
    }

    private func track(_ id: String, _ title: String, album: String = "Brol", artist: String = "Angèle", year: Int = 2018,
                       cover: (Int, Int, String)? = (720, 720, "brol")) -> AlbumTidy.AlbumTrack {
        AlbumTidy.AlbumTrack(id: id, title: title, album: album, albumArtist: artist, year: year,
                             cover: cover.map { .init(width: $0.0, height: $0.1, fingerprint: $0.2) })
    }

    @Test func makesAnAlbumAgreeOnArtistYearAndCover() {
        let fixes = AlbumTidy.consistencyFixes([
            track("a", "La Thune"),
            track("b", "Jalousie", year: 2017),
            track("c", "Flemme", artist: "Ange\u{300}le", cover: (1280, 720, "video still")),
            track("d", "Perdus", album: "Perdus", year: 2019, cover: (720, 720, "single")),
        ])
        #expect(fixes == [
            .init(trackID: "b", album: "Brol", albumArtist: nil, year: 2018, coverFrom: nil),
            .init(trackID: "c", album: "Brol", albumArtist: "Angèle", year: nil, coverFrom: "a"),
        ])
    }

    @Test func prefersASquareCoverEvenWhenMostAreWide() {
        let fixes = AlbumTidy.consistencyFixes([
            track("a", "Flip", album: "Zaba", cover: (1280, 720, "wide")),
            track("b", "Gooey", album: "Zaba", cover: (1280, 720, "wide")),
            track("c", "Toes", album: "Zaba", cover: (600, 600, "square")),
        ])
        #expect(fixes.map(\.coverFrom) == ["c", "c"])
    }

    @Test func leavesSinglesAndTidyAlbumsAlone() {
        #expect(AlbumTidy.consistencyFixes([track("a", "La Thune"), track("b", "Jalousie")]).isEmpty)
        #expect(AlbumTidy.consistencyFixes([track("a", "Jalousie", album: "Jalousie"),
                                            track("b", "Perdus", album: "Perdus", year: 2019)]).isEmpty)
    }
}
