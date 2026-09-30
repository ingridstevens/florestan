import Foundation
import Testing
@testable import FlorestanCore

@Suite struct MetadataTests {
    @Test func prefersYouTubeMusicFields() {
        let info = VideoInfo(id: "x", title: "H.O.O.D. (Official Video)", channel: "KneecapVEVO",
                             track: "H.O.O.D.", artists: ["Kneecap"], album: "Fine Art")
        #expect(TrackMetadata(from: info) == TrackMetadata(title: "H.O.O.D.", artist: "Kneecap", album: "Fine Art", albumArtist: "Kneecap"))
    }

    @Test func joinsMultipleArtists() {
        let info = VideoInfo(id: "x", title: "t", track: "Song", artists: ["A", "B"])
        #expect(TrackMetadata(from: info).artist == "A, B")
    }

    @Test(arguments: [
        ("Artist - Song (Official Video)", "Artist", "Song"),
        ("Artist - Song [Official Music Video] [4K]", "Artist", "Song"),
        ("Artist – Song (Lyrics)", "Artist", "Song"),
        ("Artist - \"Song\" | Official Audio", "Artist", "Song"),
        ("Artist - Song (feat. Other) (Official Visualizer)", "Artist", "Song (feat. Other)"),
        ("Artist - Song (Remastered 2011)", "Artist", "Song (Remastered 2011)"),
    ])
    func parsesArtistAndTitle(_ title: String, _ artist: String, _ song: String) {
        let meta = TrackMetadata(from: VideoInfo(id: "x", title: title, channel: "Somebody"))
        #expect(meta.artist == artist)
        #expect(meta.title == song)
    }

    @Test func fallsBackToCleanedChannel() {
        let meta = TrackMetadata(from: VideoInfo(id: "x", title: "Träumerei (Official Audio)", channel: "Robert Schumann - Topic"))
        #expect(meta == TrackMetadata(title: "Träumerei", artist: "Robert Schumann", album: "Träumerei", albumArtist: "Robert Schumann"))
    }

    @Test func stripsVevo() {
        #expect(TrackMetadata.cleanChannel("TaylorSwiftVEVO") == "TaylorSwift")
    }

    @Test func songsOfOneAlbumShareAlbumArtist() {
        var book = AlbumBook()
        book.record(TrackMetadata(title: "Ich grolle nicht", artist: "Barbara Bonney, Antonio Pappano",
                                  album: "Brahms/Schumann Lieder", albumArtist: "Barbara Bonney"))
        let second = TrackMetadata(from: VideoInfo(id: "b", title: "t", track: "Verzicht", artists: ["Anne Sofie von Otter", "Barbara Bonney"],
                                                    album: "Brahms/Schumann Lieder"))
        #expect(second.albumArtist == "Anne Sofie von Otter")
        #expect(book.group(second).albumArtist == "Barbara Bonney")
    }

    @Test func differentAlbumsWithTheSameNameStayApart() {
        var book = AlbumBook()
        book.record(TrackMetadata(title: "Somebody to Love", artist: "Queen", album: "Greatest Hits", albumArtist: "Queen"))
        let abba = TrackMetadata(title: "Waterloo", artist: "ABBA", album: "Greatest Hits", albumArtist: "ABBA")
        #expect(book.group(abba).albumArtist == "ABBA")
        #expect(book.group(TrackMetadata(title: "SOS", artist: "ABBA", album: "Greatest Hits", albumArtist: "ABBA")).albumArtist == "ABBA")
    }

    @Test func retryableFailures() {
        #expect(YTDLP.Failure.other("HTTP Error 500").isPermanent == false)
        #expect(YTDLP.Failure.privateVideo.isPermanent)
        #expect(YTDLP.Failure.botCheck.isPermanent)
    }
}
