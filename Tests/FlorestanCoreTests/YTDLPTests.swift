import Foundation
import Testing
@testable import FlorestanCore

@Suite struct YTDLPTests {
    @Test func progressLines() {
        #expect(YTDLP.progress(fromLine: "FLORESTAN 500 1000") == 0.5)
        #expect(YTDLP.progress(fromLine: "FLORESTAN 500 NA") == nil)
        #expect(YTDLP.progress(fromLine: "[download] 50%") == nil)
    }

    @Test func classifiesFailures() {
        #expect(YTDLP.classify(stderr: "ERROR: [youtube] abc: Sign in to confirm you’re not a bot.") == .botCheck)
        #expect(YTDLP.classify(stderr: "ERROR: [youtube] abc: Sign in to confirm your age.") == .ageRestricted)
        #expect(YTDLP.classify(stderr: "ERROR: [youtube] abc: Private video. Sign in if you've been granted access") == .privateVideo)
        #expect(YTDLP.classify(stderr: "ERROR: [youtube] abc: Video unavailable") == .unavailable)
        #expect(YTDLP.classify(stderr: "ERROR: [youtube] abc: Unable to extract player response").shouldUpgradeAndRetry)
        #expect(YTDLP.classify(stderr: "[Errno 1] Operation not permitted: '/Users/x/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'") == .safariNeedsFullDiskAccess)
        #expect(YTDLP.classify(stderr: "WARNING: x\nERROR: [youtube] abcdefghijk: Something odd") == .other("Something odd"))
    }

    @Test func parsesFlatPlaylist() throws {
        let json = #"{"id":"PL1","title":"Album - Fine Art","entries":[{"id":"a1","title":"One"},{"id":"a2","title":null}]}"#
        let playlist = try YTDLP.parsePlaylist(Data(json.utf8))
        #expect(playlist.title == "Fine Art")
        #expect(playlist.entries.map(\.id) == ["a1", "a2"])
    }
}
