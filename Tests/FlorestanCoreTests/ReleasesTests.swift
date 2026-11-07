import Testing
@testable import FlorestanCore

@Suite struct ReleasesTests {
    @Test(arguments: [
        ("v0.0.3", "0.0.2"),
        ("0.0.10", "0.0.9"),
        ("1.0", "0.9.9"),
        ("0.1", "0.0.99"),
        ("2026.11.04", "2026.10.21"),
        ("2026.10.21.1", "2026.10.21"),
    ])
    func findsLaterVersions(_ candidate: String, _ current: String) {
        #expect(Releases.isNewer(candidate, than: current))
    }

    @Test(arguments: [
        ("0.0.2", "0.0.2"),
        ("v0.0.2", "0.0.2"),
        ("0.0.9", "0.0.10"),
        ("1.0.0", "1.0"),
        ("nightly", "0.0.2"),
        ("", "0.0.2"),
    ])
    func ignoresSameOlderOrUnreadable(_ candidate: String, _ current: String) {
        #expect(!Releases.isNewer(candidate, than: current))
    }

    @Test func findsAFilesChecksum() {
        let sums = """
        1111aaaa  yt-dlp_macos
        2222BBBB  yt-dlp_macos.zip
        3333cccc *yt-dlp.exe
        """
        #expect(Releases.checksum(for: "yt-dlp_macos.zip", in: sums) == "2222bbbb")
        #expect(Releases.checksum(for: "yt-dlp.exe", in: sums) == "3333cccc")
        #expect(Releases.checksum(for: "yt-dlp_linux", in: sums) == nil)
    }

    @Test func readsWhatMusicIsPlaying() {
        let us = "\u{1F}"
        let status = PlayerStatus.parse(["playing", "6001D537F83BBDED", "The Look", "Metronomy", "The English Riviera", "1"].joined(separator: us))
        #expect(status == PlayerStatus(state: .playing, trackID: "6001D537F83BBDED", title: "The Look", artist: "Metronomy",
                                       album: "The English Riviera", wroteArtwork: true))
        #expect(PlayerStatus.parse(["paused", "ID", "A | B", "", "", "0"].joined(separator: us))?.title == "A | B")
    }

    @Test func stoppedOrGarbledIsNothingPlaying() {
        #expect(PlayerStatus.parse("stopped") == nil)
        #expect(PlayerStatus.parse("") == nil)
        #expect(PlayerStatus.parse(["fast forwarding", "ID", "T", "A", "B", "0"].joined(separator: "\u{1F}")) == nil)
    }
}
