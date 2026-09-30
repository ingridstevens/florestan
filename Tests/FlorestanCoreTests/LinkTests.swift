import Foundation
import Testing
@testable import FlorestanCore

@Suite struct LinkTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=42",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ&feature=share",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "  https://www.youtube.com/watch?v=dQw4w9WgXcQ \n",
    ])
    func songLinks(_ text: String) {
        #expect(Link.parse(text) == .song(videoID: "dQw4w9WgXcQ"))
    }

    @Test func videoInsidePlaylistIsASong() {
        #expect(Link.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG&index=3")
                == .song(videoID: "dQw4w9WgXcQ"))
    }

    @Test(arguments: [
        "https://www.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG",
        "https://music.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG&si=x",
    ])
    func playlistLinks(_ text: String) {
        let link = Link.parse(text)
        #expect(link == .playlist(id: "PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG",
                                  url: URL(string: "https://www.youtube.com/playlist?list=PLx0sYbCqOb8TBPRdmBHs5Iftvv9TPboYG")!))
    }

    @Test func musicAlbum() {
        let link = Link.parse("https://music.youtube.com/browse/MPREb_abcdefghijk")
        #expect(link?.isPlaylist == true)
        #expect(link?.url.absoluteString == "https://music.youtube.com/browse/MPREb_abcdefghijk")
    }

    @Test(arguments: [
        "", "hello world", "https://vimeo.com/12345", "https://www.youtube.com/",
        "https://www.youtube.com/watch?v=short", "https://www.youtube.com/@somechannel",
        "https://www.youtube.com/watch?list=RDdQw4w9WgXcQ",
    ])
    func notLinks(_ text: String) {
        #expect(Link.parse(text) == nil)
    }
}
